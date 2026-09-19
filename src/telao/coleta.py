"""Coleta propria do telao: o nacional e os 27 estados, a cada ciclo.

Usa a biblioteca de leitura do TSE do gctse - cliente com cache condicional,
parser das abreviacoes, travas de fase e de regressao - mas com estado, pasta e
processo proprios. Nada aqui depende de o gctse estar rodando.

As duas travas sao repetidas aqui de proposito, com o mesmo criterio do GC:

1. FASE. O TSE publica simulados nos mesmos caminhos nos dias que antecedem o
   pleito. Boletim fora da fase 'O' e descartado, entao um simulado nao vira
   tela cheia com cara de resultado.
2. REGRESSAO. A CDN pode servir uma copia antiga de um no diferente. Boletim
   com hora de geracao anterior a ultima aceita e descartado: o numero no
   telao nao anda para tras.

O que NAO e repetido: a deduplicacao de arquivo. Aqui ela vive no desenho -
uma tela so e reescrita quando o SVG muda -, que e o lugar certo para este
sistema.
"""

from __future__ import annotations

import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from gctse.historico import Historico, Ponto
from gctse.modelos import Apuracao
from gctse.simulador import Simulador
from gctse.tse.cliente import ClienteTSE, Resposta
from gctse.tse.endpoints import Endpoints
from gctse.tse.parser import analisar

from .config import Config

log = logging.getLogger("telao.coleta")


class Coletor:
    """Mantem a leitura mais recente de cada praca."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.endpoints = Endpoints(cfg.tse)
        self.cliente = ClienteTSE(
            timeout=float(cfg.coleta.get("timeout_segundos", 8)),
            tentativas=int(cfg.coleta.get("tentativas", 3)),
            backoff=float(cfg.coleta.get("backoff", 1.5)),
            usar_cache=bool(cfg.coleta.get("cache_condicional", True)),
            user_agent=cfg.coleta.get("user_agent"),
        )
        self.simulador: Simulador | None = None
        if str(cfg.coleta.get("fonte", "tse")).lower() == "simulador":
            travado = cfg.coleta.get("simulador_progresso")
            self.simulador = Simulador(
                duracao_segundos=int(cfg.coleta.get("simulador_duracao_segundos", 900)),
                progresso_fixo=float(travado) if travado is not None else None,
            )
            log.warning("FONTE = SIMULADOR (dados ficticios, fase 'S'). Nao use no ar.")

        self.historico = Historico(
            cfg.coleta.get("arquivo_historico", str(cfg.destino / "historico.jsonl")),
            ativo=bool(cfg.coleta.get("historico", True)),
        )

        # ultima leitura aceita de cada praca; 'BR' e o nacional
        self.nacional: Apuracao | None = None
        self.estados: dict[str, Apuracao] = {}
        self.serie: dict[str, list[Ponto]] = self.historico.series() if self.historico.ativo else {}

        self._gerado_em: dict[str, datetime] = {}
        self._falhas: dict[str, int] = {}
        self._trava = threading.Lock()
        self.ciclos = 0

    # --- ciclo ---

    @property
    def pracas(self) -> list[str]:
        """'br' primeiro: e o numero que abre a maioria das telas."""
        return ["br"] + [s.lower() for s in self.cfg.estados]

    def ciclo(self) -> dict[str, str]:
        trabalhadores = max(1, int(self.cfg.coleta.get("paralelismo", 8)))
        resultados: dict[str, str] = {}
        with ThreadPoolExecutor(max_workers=trabalhadores, thread_name_prefix="telao") as executor:
            futuros = {executor.submit(self._buscar, praca): praca for praca in self.pracas}
            for futuro, praca in futuros.items():
                try:
                    resultados[praca] = futuro.result()
                except Exception as exc:  # nenhuma praca derruba o ciclo
                    log.exception("erro inesperado na praca '%s'", praca)
                    resultados[praca] = f"erro: {exc}"
        self.ciclos += 1
        return resultados

    def _obter(self, praca: str) -> Resposta:
        if self.simulador is not None:
            dados = self.simulador.gerar(praca, self.cfg.cargo, self.cfg.turno)
            return Resposta(url=f"simulador://{praca}", dados=dados, status=200)
        return self.cliente.buscar_json(self.endpoints.resultado(praca, self.cfg.cargo))

    def _buscar(self, praca: str) -> str:
        resposta = self._obter(praca)

        if resposta.inalterado:
            return "sem-mudanca"
        if not resposta.ok:
            falhas = self._falhas.get(praca, 0) + 1
            self._falhas[praca] = falhas
            if resposta.status == 404 and falhas == 1:
                log.info("praca '%s': boletim ainda nao publicado", praca)
            elif falhas == int(self.cfg.coleta.get("falhas_para_alerta", 3)):
                log.warning("praca '%s' falhou %dx seguidas: %s", praca, falhas,
                            resposta.erro or resposta.status)
            return f"falha({resposta.erro or resposta.status})"
        self._falhas.pop(praca, None)

        ap = analisar(
            resposta.dados or {},
            abrangencia=praca,
            cargo=self.cfg.cargo,
            turno=self.cfg.turno,
            fonte_url=resposta.url,
            mapeamento=self.cfg.bruto.get("mapeamento") or {},
        )

        # Trava 1: nada fora da fase oficial vai para a tela.
        if not ap.oficial and bool(self.cfg.seguranca.get("bloquear_nao_oficial", True)):
            if self.simulador is None:
                log.warning("praca '%s': fase '%s' (nao oficial) descartada", praca, ap.fase)
                return f"bloqueado(fase={ap.fase or '?'})"

        # Trava 2: boletim mais antigo que o ja aceito nao substitui o que esta
        # no ar - o numero da tela nunca anda para tras.
        if bool(self.cfg.seguranca.get("bloquear_regressao", True)):
            anterior = self._gerado_em.get(praca)
            if anterior and ap.gerado_em and ap.gerado_em < anterior:
                log.warning("praca '%s': boletim mais antigo que o exibido - descartado", praca)
                return "regressao-descartada"

        with self._trava:
            if praca == "br":
                self.nacional = ap
            else:
                self.estados[praca.upper()] = ap
            if ap.gerado_em:
                self._gerado_em[praca] = ap.gerado_em
            self._registrar(praca, ap)
        return f"ok({ap.pct_secoes:.2f}%)"

    def _registrar(self, praca: str, ap: Apuracao) -> None:
        """Serie temporal - so o nacional, que e o que a curva usa."""
        if praca != "br" or not self.historico.ativo:
            return
        if self.historico.registrar("nacional", ap):
            self.serie.setdefault("nacional", []).append(
                Ponto(
                    instante=ap.gerado_em or ap.capturado_em or datetime.now(),
                    pct=ap.pct_secoes,
                    secoes_totalizadas=ap.secoes_totalizadas,
                    secoes_total=ap.secoes_total,
                    candidatos=[(c.numero, c.votos, c.percentual) for c in ap.candidatos],
                )
            )

    # --- numeros agregados ---

    def total_secoes(self) -> tuple[int, int]:
        """Urnas totalizadas e total, preferindo o boletim nacional.

        O nacional e a fonte certa quando existe: e o proprio TSE somando. A
        soma dos estados so entra enquanto o arquivo nacional nao saiu, e vem
        rotulada como parcial nas telas que a usam.
        """
        if self.nacional is not None and self.nacional.secoes_total:
            return self.nacional.secoes_totalizadas, self.nacional.secoes_total
        com_dado = list(self.estados.values())
        return (
            sum(a.secoes_totalizadas for a in com_dado),
            sum(a.secoes_total for a in com_dado),
        )

    def fechar(self) -> None:
        self.cliente.fechar()


def rodar(cfg: Config, aplicar, parar: threading.Event | None = None) -> None:
    """Loop de operacao: coleta, chama 'aplicar', espera o intervalo."""
    coletor = Coletor(cfg)
    parar = parar or threading.Event()
    log.info(
        "telao iniciado: cargo %d, %d praca(s), intervalo de %ds",
        cfg.cargo, len(coletor.pracas), cfg.intervalo,
    )
    try:
        while not parar.is_set():
            comeco = time.monotonic()
            resultados = coletor.ciclo()
            try:
                aplicar(coletor)
            except Exception:
                # desenhar nao pode derrubar a coleta: o proximo ciclo tenta de novo
                log.exception("falha ao desenhar as telas")
            ok = sum(1 for v in resultados.values() if v.startswith("ok"))
            log.info("ciclo %d em %.1fs | %d praca(s) com boletim novo",
                     coletor.ciclos, time.monotonic() - comeco, ok)
            restante = cfg.intervalo - (time.monotonic() - comeco)
            if restante > 0:
                parar.wait(restante)
    finally:
        coletor.fechar()
    log.info("telao encerrado apos %d ciclo(s)", coletor.ciclos)
