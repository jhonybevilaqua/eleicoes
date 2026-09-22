"""Orquestracao: coleta -> normaliza -> guarda -> exporta.

Um ciclo percorre todos os alvos configurados (abrangencia x cargo), busca o
boletim, aplica as guardas de seguranca e entrega aos exporters do alvo.
Alvos sao independentes: falha em um nao impede os demais.
"""

from __future__ import annotations

import hashlib
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
from .historico import Historico, Ponto, projecao, viradas
from .modelos import Apuracao
from .painel import renderizar as renderizar_painel
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
        # Serie temporal: alimenta curva de apuracao, previsao de fechamento e
        # marcos de virada. Carregada uma vez na partida e mantida em memoria,
        # para o ciclo nao reler o arquivo inteiro a cada 20 segundos.
        self.historico = Historico(
            cfg.coleta.get("arquivo_historico", "dados/estado/historico.jsonl"),
            ativo=bool(cfg.coleta.get("historico", True)),
        )
        self._serie: dict[str, list[Ponto]] = self.historico.series() if self.historico.ativo else {}

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
        self.grupos = cfg.grupos

        # ultima apuracao boa de cada alvo, para montar os rodizios no fim do
        # ciclo. Mantida mesmo quando o boletim nao mudou, senao a praca sumiria
        # da lista so por estar estavel.
        self._ultima: dict[str, Apuracao] = {}
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
        rodizios = self._publicar_rodizios()
        self.ciclos += 1
        self.estado.salvar()
        self._escrever_saude(resultados)
        self._escrever_graficos()
        self._escrever_painel(resultados, rodizios)
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
        self._ultima[alvo.nome] = apuracao
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
            if hasattr(exporter, "exportar_lista"):
                # exporter de rodizio: so faz sentido com a lista inteira de
                # pracas, montada no fim do ciclo. Listado num alvo por engano,
                # seria um erro por ciclo ate alguem notar.
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
        self._registrar_historico(alvo.nome, ap)
        log.info(
            "alvo '%s': %.2f%% apurado, %d candidato(s), %d arquivo(s)",
            alvo.nome, ap.pct_secoes, len(ap.candidatos), len(escritos),
        )
        return f"publicado({ap.pct_secoes:.2f}%)"

    def _publicar_rodizios(self) -> dict[str, tuple[int, int]]:
        """Junta varias pracas num arquivo so: rodizio de tarja e mapa.

        Os dois tem a mesma forma - uma lista de pracas, um arquivo - e por
        isso passam pelo mesmo caminho, com o mesmo dedupe: o mapa tambem so e
        reescrito quando alguma praca do grupo muda.
        """
        situacao: dict[str, tuple[int, int]] = {}
        apelidos = {a.nome: (a.apelido_abrangencia or a.abrangencia.upper()) for a in self.alvos}
        for nome, grupo in self.grupos.items():
            exporter = self.exporters.get(grupo.get("exporter", ""))
            if exporter is None or not hasattr(exporter, "exportar_lista"):
                continue
            itens = [
                (ordem, apelidos.get(alvo, alvo), self._ultima.get(alvo))
                for ordem, alvo in enumerate(grupo.get("alvos") or [], start=1)
            ]
            arquivo = str(grupo.get("nome_arquivo") or nome)

            # dedupe proprio: sem isso o arquivo do rodizio seria reescrito a
            # cada ciclo mesmo quando nenhuma das pracas mudou
            montado = exporter.montar(itens)
            impressao = hashlib.sha1(
                json.dumps(montado, ensure_ascii=False, sort_keys=True).encode("utf-8")
            ).hexdigest()
            chave = f"grupo:{nome}"
            situacao[nome] = (len(itens), sum(1 for _, _, ap in itens if ap))
            if not self.estado.mudou(chave, impressao) and not bool(
                self.cfg.saida.get("reescrever_sempre", False)
            ):
                continue
            try:
                escritos = exporter.exportar_lista(itens, arquivo)
            except Exception as exc:
                log.exception("grupo '%s' falhou", nome)
                self.alertas.enviar(f"grupo:{nome}", f"grupo '{nome}' falhou: {exc}", "ERRO")
                continue
            com_dado = sum(1 for _, _, ap in itens if ap)
            situacao[nome] = (len(itens), com_dado)
            self.estado.registrar(chave, impressao, None, {"pracas": len(itens), "com_dado": com_dado})
            log.info("grupo '%s': %d de %d praca(s) com dado, %d arquivo(s)",
                     nome, com_dado, len(itens), len(escritos))
        return situacao

    # --- historico e projecao ---

    def _registrar_historico(self, nome_alvo: str, ap: Apuracao) -> None:
        if not self.historico.ativo:
            return
        if self.historico.registrar(nome_alvo, ap):
            self._serie.setdefault(nome_alvo, []).append(
                Ponto(
                    instante=ap.gerado_em or ap.capturado_em or datetime.now(),
                    pct=ap.pct_secoes,
                    secoes_totalizadas=ap.secoes_totalizadas,
                    secoes_total=ap.secoes_total,
                    candidatos=[(c.numero, c.votos, c.percentual) for c in ap.candidatos],
                )
            )

    def projecoes(self) -> dict[str, dict]:
        """Previsao de fechamento por alvo, a partir da serie em memoria."""
        return {nome: projecao(pontos) for nome, pontos in self._serie.items() if pontos}

    def _escrever_graficos(self) -> None:
        """Arquivo unico com o que os graficos de evolucao precisam.

        Serie, previsao de fechamento e marcos de virada, por alvo. Sai
        separado do 'saude.json' porque tem outro publico: saude e para o
        monitoramento da emissora, este e para grafico, site e conferencia.
        """
        caminho = self.cfg.coleta.get("arquivo_graficos")
        if not caminho or not self._serie:
            return
        limite = int(self.cfg.coleta.get("pontos_por_grafico", 240))
        corpo = {
            "atualizado_em": datetime.now().isoformat(timespec="seconds"),
            "alvos": {
                nome: {
                    "projecao": projecao(pontos),
                    "viradas": viradas(pontos),
                    "serie": [
                        {
                            "hora": ponto.instante.strftime("%H:%M:%S"),
                            "pct": ponto.pct,
                            "secoes_totalizadas": ponto.secoes_totalizadas,
                            "candidatos": [
                                {"numero": n, "votos": v, "percentual": pc}
                                for n, v, pc in ponto.candidatos
                            ],
                        }
                        # Grafico nao ganha nada com 700 pontos numa linha de
                        # 600px: os ultimos N bastam, e o arquivo fica leve
                        # para quem le pela rede.
                        for ponto in pontos[-limite:]
                    ],
                }
                for nome, pontos in self._serie.items()
                if pontos
            },
        }
        try:
            escrever_texto(Path(caminho), json.dumps(corpo, ensure_ascii=False, indent=2), nova_linha="\n")
        except OSError as exc:
            log.error("nao foi possivel escrever o arquivo de graficos: %s", exc)

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

    def _escrever_painel(self, resultados: dict[str, str], rodizios: dict[str, tuple[int, int]]) -> None:
        """Tela de validacao para o coordenador acompanhar durante a apuracao."""
        caminho = self.cfg.coleta.get("arquivo_painel")
        if not caminho:
            return
        try:
            renderizar_painel(
                caminho=caminho,
                fonte=str(self.cfg.coleta.get("fonte", "tse")),
                modo=self.cfg.modo,
                ciclos=self.ciclos,
                intervalo=self.cfg.intervalo,
                resultados=resultados,
                apuracoes=self._ultima,
                rodizios=rodizios,
                projecoes=self.projecoes(),
            )
        except OSError as exc:
            log.error("nao foi possivel escrever o painel: %s", exc)

    def _escrever_saude(self, resultados: dict[str, str]) -> None:
        """Arquivo de saude para o monitoramento da emissora acompanhar."""
        caminho = self.cfg.coleta.get("arquivo_saude")
        if not caminho:
            return
        corpo = {
            "atualizado_em": datetime.now().isoformat(timespec="seconds"),
            "ciclos": self.ciclos,
            "modo": self.cfg.modo,
            "fonte": self.cfg.coleta.get("fonte", "tse"),
            "alvos": resultados,
            "falhas": self._falhas,
        }
        try:
            escrever_texto(Path(caminho), json.dumps(corpo, ensure_ascii=False, indent=2), nova_linha="\n")
        except OSError as exc:
            log.error("nao foi possivel escrever o arquivo de saude: %s", exc)
