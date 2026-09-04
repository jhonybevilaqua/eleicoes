"""Orquestracao: coleta -> normaliza -> guarda -> exporta.

Um ciclo percorre todos os alvos configurados (abrangencia x cargo), busca o
boletim, aplica as guardas de seguranca e entrega aos exporters do alvo.
Alvos sao independentes: falha em um nao impede os demais.
"""

from __future__ import annotations

import json
import logging
import signal
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

from .alertas import Alertas
from .config import Alvo, Config
from .estado import Estado
from .exporters import criar
from .exporters.base import Exporter
from .fontes import criar_fonte
from .modelos import Apuracao
from .tse.cliente import ClienteTSE
from .tse.endpoints import Endpoints
from .tse.parser import analisar
from .util.arquivos import escrever_texto

log = logging.getLogger("gctse.pipeline")


class Pipeline:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.alertas = Alertas(cfg.alertas)
        self.estado = Estado(cfg.coleta.get("arquivo_estado", "dados/estado/estado.json"))

        self.endpoints = Endpoints(cfg.tse)
        self.cliente = ClienteTSE(
            timeout=float(cfg.coleta.get("timeout_segundos", 8)),
            tentativas=int(cfg.coleta.get("tentativas", 3)),
            backoff=float(cfg.coleta.get("backoff", 1.5)),
            usar_cache=bool(cfg.coleta.get("cache_condicional", True)),
            user_agent=cfg.coleta.get("user_agent"),
        )
        self.fonte = criar_fonte(cfg, self.cliente, self.endpoints)

        self.exporters: dict[str, Exporter] = {
            nome: criar(nome, opcoes, cfg.texto, cfg.saida) for nome, opcoes in cfg.exporters.items()
        }
        self.alvos: list[Alvo] = cfg.alvos

        self._parar = threading.Event()
        self._falhas: dict[str, int] = {}
        self._ultimo_sucesso: dict[str, float] = {}
        self.ciclos = 0

    # --- controle de execucao ---

    def instalar_sinais(self) -> None:
        def encerrar(signum, _frame):
            log.info("sinal %s recebido: encerrando apos o ciclo atual", signum)
            self._parar.set()

        for sinal in (signal.SIGINT, signal.SIGTERM):
            try:
                signal.signal(sinal, encerrar)
            except (ValueError, OSError):  # fora da thread principal / Windows
                pass

    def parar(self) -> None:
        self._parar.set()

    def fechar(self) -> None:
        self.estado.salvar()
        self.fonte.fechar()

    # --- ciclo ---

    def rodar_uma_vez(self) -> dict[str, str]:
        trabalhadores = max(1, int(self.cfg.coleta.get("paralelismo", 4)))
        resultados: dict[str, str] = {}
        with ThreadPoolExecutor(max_workers=trabalhadores, thread_name_prefix="gctse") as executor:
            futuros = {executor.submit(self.processar_alvo, alvo): alvo for alvo in self.alvos}
            for futuro, alvo in futuros.items():
                try:
                    resultados[alvo.nome] = futuro.result()
                except Exception as exc:  # nunca deixar uma excecao derrubar o ciclo
                    log.exception("erro inesperado no alvo '%s'", alvo.nome)
                    resultados[alvo.nome] = f"erro: {exc}"
        self.ciclos += 1
        self.estado.salvar()
        self._escrever_saude(resultados)
        return resultados

    def rodar(self) -> None:
        intervalo = self.cfg.intervalo
        log.info(
            "iniciando: %d alvo(s), intervalo de %ds, fonte '%s'",
            len(self.alvos), intervalo, self.cfg.coleta.get("fonte", "tse"),
        )
        while not self._parar.is_set():
            comeco = time.monotonic()
            resultados = self.rodar_uma_vez()
            self._verificar_estagnacao()
            resumo = ", ".join(f"{k}={v}" for k, v in sorted(resultados.items()))
            log.info("ciclo %d concluido em %.1fs | %s", self.ciclos, time.monotonic() - comeco, resumo)
            restante = intervalo - (time.monotonic() - comeco)
            if restante > 0:
                self._parar.wait(restante)
        log.info("encerrado apos %d ciclo(s)", self.ciclos)

    # --- por alvo ---

    def processar_alvo(self, alvo: Alvo) -> str:
        resposta = self.fonte.obter(alvo.abrangencia, alvo.cargo, alvo.turno)

        if resposta.inalterado:
            self._ultimo_sucesso[alvo.nome] = time.time()
            return "sem-mudanca"

        if not resposta.ok:
            falhas = self._falhas.get(alvo.nome, 0) + 1
            self._falhas[alvo.nome] = falhas
            limite = int(self.cfg.coleta.get("falhas_para_alerta", 3))
            if resposta.status == 404 and falhas == 1:
                log.info("alvo '%s': boletim ainda nao publicado (%s)", alvo.nome, resposta.url)
            elif falhas >= limite:
                self.alertas.enviar(
                    f"falha:{alvo.nome}",
                    f"alvo '{alvo.nome}' falhou {falhas}x seguidas: {resposta.erro or resposta.status}",
                    "ERRO",
                )
            return f"falha({resposta.erro or resposta.status})"

        self._falhas.pop(alvo.nome, None)
        self.alertas.resolver(f"falha:{alvo.nome}")

        apuracao = analisar(
            resposta.dados or {},
            abrangencia=alvo.abrangencia,
            cargo=alvo.cargo,
            turno=alvo.turno,
            fonte_url=resposta.url,
            mapeamento=self.cfg.mapeamento,
            limite_candidatos=alvo.limite_candidatos,
            nome_abrangencia=alvo.apelido_abrangencia,
        )
        if alvo.apelido_abrangencia:
            apuracao.abrangencia_nome = alvo.apelido_abrangencia

        self._ultimo_sucesso[alvo.nome] = time.time()
        return self._publicar(alvo, apuracao)

    def _publicar(self, alvo: Alvo, ap: Apuracao) -> str:
        chave = f"{alvo.nome}|{ap.chave}"
        seguranca = self.cfg.seguranca

        # Guarda 1: boletim nao oficial nunca vai para a pasta do ar sem opt-in.
        if not ap.oficial and bool(seguranca.get("bloquear_nao_oficial", True)):
            if str(self.cfg.coleta.get("fonte", "tse")).lower() == "tse":
                log.warning(
                    "alvo '%s': boletim em fase '%s' (nao oficial) descartado por seguranca", alvo.nome, ap.fase
                )
                self.alertas.enviar(
                    f"fase:{alvo.nome}", f"alvo '{alvo.nome}' recebendo fase '{ap.fase_nome}' - nada publicado", "AVISO"
                )
                return f"bloqueado(fase={ap.fase or '?'})"

        # Guarda 2: a CDN pode servir copia antiga; o placar nao anda para tras.
        if bool(seguranca.get("bloquear_regressao", True)) and self.estado.regrediu(chave, ap.gerado_em):
            log.warning(
                "alvo '%s': boletim mais antigo que o publicado (%s) - descartado",
                alvo.nome, ap.gerado_em,
            )
            return "regressao-descartada"

        # Guarda 3: se nada mudou, nao reescreve (hot folder nao pisca).
        impressao = ap.impressao()
        if not self.estado.mudou(chave, impressao) and not bool(self.cfg.saida.get("reescrever_sempre", False)):
            return "sem-mudanca"

        # Guarda 4: minimo de apuracao antes de liberar o placar no ar.
        minimo = float(seguranca.get("pct_minimo_para_publicar", 0))
        if ap.pct_secoes < minimo:
            log.info("alvo '%s': %.2f%% apurado, abaixo do minimo de %.2f%%", alvo.nome, ap.pct_secoes, minimo)
            return f"aguardando({ap.pct_secoes:.2f}%)"

        escritos: list[Path] = []
        for nome_exporter in alvo.exporters:
            exporter = self.exporters.get(nome_exporter)
            if exporter is None:
                continue
            try:
                escritos.extend(exporter.exportar(ap, alvo.nome))
            except Exception as exc:
                log.exception("alvo '%s': exporter '%s' falhou", alvo.nome, nome_exporter)
                self.alertas.enviar(
                    f"exporter:{alvo.nome}:{nome_exporter}",
                    f"exporter '{nome_exporter}' falhou no alvo '{alvo.nome}': {exc}",
                    "ERRO",
                )

        self.estado.registrar(
            chave,
            impressao,
            ap.gerado_em,
            {"pct": ap.pct_secoes, "fase": ap.fase, "arquivos": [str(p) for p in escritos]},
        )
        log.info(
            "alvo '%s': %.2f%% apurado, %d candidato(s), %d arquivo(s)",
            alvo.nome, ap.pct_secoes, len(ap.candidatos), len(escritos),
        )
        return f"publicado({ap.pct_secoes:.2f}%)"

    # --- supervisao ---

    def _verificar_estagnacao(self) -> None:
        limite = int(self.cfg.coleta.get("segundos_sem_dado_para_alerta", 300))
        if limite <= 0:
            return
        agora = time.time()
        for alvo in self.alvos:
            ultimo = self._ultimo_sucesso.get(alvo.nome)
            if ultimo and agora - ultimo > limite:
                self.alertas.enviar(
                    f"parado:{alvo.nome}",
                    f"alvo '{alvo.nome}' sem dado novo ha {int(agora - ultimo)}s",
                    "ERRO",
                )

    def _escrever_saude(self, resultados: dict[str, str]) -> None:
        """Arquivo de saude para o monitoramento da emissora acompanhar."""
        caminho = self.cfg.coleta.get("arquivo_saude")
        if not caminho:
            return
        corpo = {
            "atualizado_em": datetime.now().isoformat(timespec="seconds"),
            "ciclos": self.ciclos,
            "fonte": self.cfg.coleta.get("fonte", "tse"),
            "alvos": resultados,
            "falhas": self._falhas,
        }
        try:
            escrever_texto(Path(caminho), json.dumps(corpo, ensure_ascii=False, indent=2), nova_linha="\n")
        except OSError as exc:
            log.error("nao foi possivel escrever o arquivo de saude: %s", exc)
