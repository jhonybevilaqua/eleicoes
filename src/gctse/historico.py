"""Serie temporal da apuracao: uma linha por boletim publicado.

O 'estado.json' guarda SO o ultimo boletim de cada alvo - ele existe para
deduplicar e barrar regressao, e sobrescreve o valor anterior a cada ciclo.
Isso resolve o ar, mas impede qualquer grafico de evolucao: sem os pontos
anteriores nao ha curva de apuracao, nao ha momento da virada e nao ha
previsao de fechamento.

Este modulo guarda esses pontos. Formato JSONL - uma linha JSON por registro,
acrescentada no fim do arquivo:

* acrescentar linha e barato e nao reescreve o que ja esta gravado, entao o
  custo nao cresce junto com a apuracao;
* arquivo truncado por queda de energia perde a ultima linha, nao o dia
  inteiro, e a leitura descarta linha ilegivel sem derrubar o processo;
* qualquer ferramenta le: Excel, Power BI, pandas, ou o proprio painel.

As chaves sao curtas ('t', 'pct', 'st') de proposito: sao ~700 registros por
alvo num dia de apuracao, e nome de campo longo multiplicado por 700 vira
arquivo grande sem devolver nada em troca.

NAO usa a escrita atomica de util/arquivos.py, e isso e deliberado: aquela
troca o arquivo inteiro a cada gravacao, o que aqui significaria reescrever
todo o historico a cada 20 segundos. Nenhum GC le este arquivo - ele alimenta
grafico e conferencia -, entao o risco que a escrita atomica evita (o GC ler um
arquivo pela metade) nao existe aqui.
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

from .modelos import Apuracao

log = logging.getLogger("gctse.historico")

# Pontos usados na projecao de fechamento. Poucos demais e a conta oscila a
# cada boletim; muitos demais e ela carrega o arranque rapido do inicio da
# noite, que nao se repete no fim.
PONTOS_PROJECAO = 12


@dataclass
class Ponto:
    """Um instante da apuracao de um alvo."""

    instante: datetime
    pct: float
    secoes_totalizadas: int
    secoes_total: int
    candidatos: list[tuple[str, int, float]]   # (numero, votos, percentual)

    @property
    def lider(self) -> str:
        return self.candidatos[0][0] if self.candidatos else ""


class Historico:
    def __init__(self, caminho: str | Path, ativo: bool = True):
        self.caminho = Path(caminho)
        self.ativo = ativo

    # --- escrita ---

    def registrar(self, chave: str, ap: Apuracao) -> bool:
        """Acrescenta um ponto. Devolve False se nao gravou."""
        if not self.ativo:
            return False
        linha = {
            "t": (ap.gerado_em or ap.capturado_em or datetime.now()).isoformat(timespec="seconds"),
            "k": chave,
            "pct": round(ap.pct_secoes, 2),
            "st": ap.secoes_totalizadas,
            "s": ap.secoes_total,
            "vv": ap.votos_validos,
            "vb": ap.votos_brancos,
            "vn": ap.votos_nulos,
            "c": [[c.numero, c.votos, round(c.percentual, 2)] for c in ap.candidatos],
        }
        try:
            self.caminho.parent.mkdir(parents=True, exist_ok=True)
            with open(self.caminho, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(linha, ensure_ascii=False) + "\n")
                fh.flush()
                os.fsync(fh.fileno())
            return True
        except OSError as exc:
            # Historico e para grafico e conferencia, nunca para o ar: falhar
            # aqui registra no log e segue, jamais interrompe a publicacao.
            log.warning("nao foi possivel gravar o historico em %s: %s", self.caminho, exc)
            return False

    # --- leitura ---

    def series(self) -> dict[str, list[Ponto]]:
        """Todos os pontos, agrupados por alvo e em ordem cronologica."""
        if not self.caminho.exists():
            return {}
        series: dict[str, list[Ponto]] = {}
        try:
            texto = self.caminho.read_text(encoding="utf-8")
        except OSError as exc:
            log.warning("historico ilegivel em %s: %s", self.caminho, exc)
            return {}

        for numero, linha in enumerate(texto.splitlines(), start=1):
            linha = linha.strip()
            if not linha:
                continue
            try:
                dados = json.loads(linha)
                instante = datetime.fromisoformat(str(dados["t"]))
            except (json.JSONDecodeError, KeyError, ValueError):
                # linha truncada por queda no meio da gravacao: descarta a
                # linha, nao o arquivo
                log.debug("historico: linha %d ilegivel, descartada", numero)
                continue
            series.setdefault(str(dados.get("k", "")), []).append(
                Ponto(
                    instante=instante,
                    pct=float(dados.get("pct", 0.0)),
                    secoes_totalizadas=int(dados.get("st", 0)),
                    secoes_total=int(dados.get("s", 0)),
                    candidatos=[
                        (str(c[0]), int(c[1]), float(c[2]))
                        for c in dados.get("c", [])
                        if isinstance(c, list) and len(c) >= 3
                    ],
                )
            )
        for pontos in series.values():
            pontos.sort(key=lambda p: p.instante)
        return series

    def serie(self, chave: str) -> list[Ponto]:
        return self.series().get(chave, [])


# --- analise da serie ---


def velocidade(pontos: list[Ponto], amostra: int = PONTOS_PROJECAO) -> float:
    """Pontos percentuais por minuto, pelos ultimos registros.

    Regressao linear simples sobre (minutos, pct). Usa uma janela recente
    porque o ritmo da apuracao nao e constante: a noite comeca rapida e
    termina arrastada, e uma media do dia inteiro projetaria um fechamento
    cedo demais justamente quando o dado importa.
    """
    recentes = [p for p in pontos[-amostra:]]
    if len(recentes) < 2:
        return 0.0
    base = recentes[0].instante
    xs = [(p.instante - base).total_seconds() / 60.0 for p in recentes]
    ys = [p.pct for p in recentes]
    n = len(xs)
    media_x, media_y = sum(xs) / n, sum(ys) / n
    denominador = sum((x - media_x) ** 2 for x in xs)
    if denominador <= 0:
        return 0.0
    return sum((x - media_x) * (y - media_y) for x, y in zip(xs, ys)) / denominador


def projecao(pontos: list[Ponto], amostra: int = PONTOS_PROJECAO) -> dict:
    """Quanto falta e a que horas fecha, no ritmo atual.

    E projecao de RITMO, nao de resultado: responde 'a que horas fecha' para a
    coordenacao decidir escala, intervalo e liberacao de equipe. Nao diz nada
    sobre quem ganha, e nao deve ir ao ar como se dissesse.

    Quando o ritmo e zero ou negativo (apuracao parada, ou boletim repetido),
    devolve 'previsao' vazia em vez de um horario inventado.
    """
    if not pontos:
        return {"pontos": 0, "pct": 0.0, "pontos_por_minuto": 0.0, "previsao": "", "minutos": None}

    ultimo = pontos[-1]
    ritmo = velocidade(pontos, amostra)
    restante = max(0.0, 100.0 - ultimo.pct)

    if ultimo.pct >= 100.0:
        return {
            "pontos": len(pontos),
            "pct": ultimo.pct,
            "pontos_por_minuto": round(ritmo, 3),
            "previsao": ultimo.instante.strftime("%H:%M"),
            "minutos": 0,
            "totalizada": True,
        }
    if ritmo <= 0:
        return {
            "pontos": len(pontos),
            "pct": ultimo.pct,
            "pontos_por_minuto": round(ritmo, 3),
            "previsao": "",
            "minutos": None,
        }

    minutos = restante / ritmo
    return {
        "pontos": len(pontos),
        "pct": ultimo.pct,
        "pontos_por_minuto": round(ritmo, 3),
        "urnas_por_minuto": round(ritmo / 100.0 * ultimo.secoes_total, 1) if ultimo.secoes_total else 0.0,
        "minutos": round(minutos),
        "previsao": (ultimo.instante + timedelta(minutes=minutos)).strftime("%H:%M"),
        "totalizada": False,
    }


def viradas(pontos: list[Ponto]) -> list[dict]:
    """Instantes em que o 1o colocado mudou.

    Vira tarja no ar ('X assume a lideranca as 20h41') e vira retranca no dia
    seguinte. Detecta pela troca do NUMERO na primeira posicao, que e o
    identificador estavel - nome muda de grafia entre boletins, numero nao.
    """
    trocas: list[dict] = []
    anterior = ""
    for ponto in pontos:
        atual = ponto.lider
        if not atual:
            continue
        if anterior and atual != anterior:
            trocas.append(
                {
                    "hora": ponto.instante.strftime("%H:%M"),
                    "instante": ponto.instante.isoformat(timespec="seconds"),
                    "assumiu": atual,
                    "perdeu": anterior,
                    "pct_apurado": ponto.pct,
                }
            )
        anterior = atual
    return trocas
