"""Simulador de apuracao no formato do TSE.

Serve para ensaiar a operacao antes do dia da eleicao: gera arquivos com a
mesma estrutura do 'dados-simplificados' e faz o percentual de secoes avancar
com o tempo, para o time testar templates, hot folder, giro de placar e
procedimento de contingencia sem depender de dado real.

A fase gerada e 'S' (simulado) - os exporters marcam o selo e, se
'seguranca.bloquear_nao_oficial' estiver ligado, nada vai para a pasta do ar.
"""

from __future__ import annotations

import math
import random
import time
from typing import Any

# Chapa ficticia por cargo. Nomes inventados de proposito, para ninguem
# confundir ensaio com apuracao real.
CHAPAS: dict[int, list[tuple[str, str, str]]] = {
    1: [
        ("10", "CANDIDATO ENSAIO A", "PART-A"),
        ("20", "CANDIDATO ENSAIO B", "PART-B"),
        ("30", "CANDIDATO ENSAIO C", "PART-C"),
        ("40", "CANDIDATO ENSAIO D", "PART-D"),
        ("50", "CANDIDATO ENSAIO E", "PART-E"),
    ],
    3: [
        ("11", "GOVERNO ENSAIO 1", "PART-A"),
        ("22", "GOVERNO ENSAIO 2", "PART-B"),
        ("33", "GOVERNO ENSAIO 3", "PART-C"),
        ("44", "GOVERNO ENSAIO 4", "PART-D"),
    ],
    5: [
        ("100", "SENADO ENSAIO 1", "PART-A"),
        ("200", "SENADO ENSAIO 2", "PART-B"),
        ("300", "SENADO ENSAIO 3", "PART-C"),
    ],
}
CHAPA_GENERICA = [(f"{n}", f"CANDIDATO ENSAIO {n}", f"PART-{n}") for n in range(11, 19)]


def _fmt_int(valor: int) -> str:
    return f"{valor:,}".replace(",", ".")


def _fmt_pct(valor: float) -> str:
    return f"{valor:.2f}".replace(".", ",")


class Simulador:
    """Gera boletins ficticios que evoluem ao longo de 'duracao_segundos'."""

    def __init__(
        self,
        *,
        duracao_segundos: int = 900,
        semente: int = 2026,
        secoes_base: int = 472000,
        progresso_fixo: float | None = None,
    ):
        self.duracao = max(1, duracao_segundos)
        self.inicio = time.time()
        self.semente = semente
        self.secoes_base = secoes_base
        # trava a apuracao num percentual: util para gerar arquivo de exemplo
        # com placar cheio, ou para conferir como a cena fica em 50%.
        self.progresso_fixo = progresso_fixo

    def progresso(self) -> float:
        """0..100 - curva com arranque rapido e cauda longa, como na vida real."""
        if self.progresso_fixo is not None:
            return round(max(0.0, min(100.0, float(self.progresso_fixo))), 2)
        decorrido = min(1.0, (time.time() - self.inicio) / self.duracao)
        return round(100.0 * (1 - math.exp(-3.2 * decorrido)) / (1 - math.exp(-3.2)), 2)

    def gerar(self, abrangencia: str, cargo: int, turno: int = 1) -> dict[str, Any]:
        pct = self.progresso()
        aleatorio = random.Random(f"{self.semente}:{abrangencia}:{cargo}:{turno}")
        chapa = CHAPAS.get(cargo, CHAPA_GENERICA)

        # forcas fixas por candidato (nao mudam a cada ciclo) + ruido pequeno,
        # para o placar oscilar de forma plausivel sem virar loteria
        forcas = [aleatorio.uniform(0.5, 1.0) for _ in chapa]
        ruido_seq = random.Random(int(time.time()) // 5)
        forcas = [f * ruido_seq.uniform(0.97, 1.03) for f in forcas]
        soma = sum(forcas) or 1.0

        escala = self.secoes_base if abrangencia == "br" else max(2000, self.secoes_base // 27)
        secoes_total = escala
        secoes_totalizadas = int(secoes_total * pct / 100.0)
        eleitorado = secoes_total * 320
        comparecimento = int(eleitorado * 0.79 * pct / 100.0)
        brancos = int(comparecimento * 0.014)
        nulos = int(comparecimento * 0.032)
        validos = max(0, comparecimento - brancos - nulos)

        candidatos = []
        for indice, ((numero, nome, partido), forca) in enumerate(zip(chapa, forcas), start=1):
            votos = int(validos * forca / soma)
            candidatos.append(
                {
                    "seq": str(indice),
                    "sqcand": f"9999000{indice:04d}",
                    "n": numero,
                    "nm": nome,
                    "nmt": f"{nome} (NOME COMPLETO ENSAIO)",
                    "cc": partido,
                    "nv": f"COLIGACAO ENSAIO {partido}",
                    "e": "n",
                    "st": "Nao eleito",
                    "vap": _fmt_int(votos),
                    "pvap": _fmt_pct(100.0 * votos / validos if validos else 0.0),
                }
            )

        candidatos.sort(key=lambda c: -int(c["vap"].replace(".", "")))
        if pct >= 100.0 and candidatos:
            candidatos[0]["e"] = "s"
            candidatos[0]["st"] = "Eleito"

        agora = time.localtime()
        return {
            "ele": "999999",
            "cdpleito": "999",
            "tpabr": "BR" if abrangencia == "br" else ("UF" if len(abrangencia) == 2 else "MU"),
            "cdabr": abrangencia.upper(),
            "nmabr": "BRASIL" if abrangencia == "br" else abrangencia.upper(),
            "carg": str(cargo),
            "f": "S",  # SIMULADO - nunca 'O'
            "dg": time.strftime("%d/%m/%Y", agora),
            "hg": time.strftime("%H:%M:%S", agora),
            "s": {"st": _fmt_int(secoes_totalizadas), "s": _fmt_int(secoes_total), "pst": _fmt_pct(pct)},
            "ea": _fmt_int(eleitorado),
            "c": _fmt_int(comparecimento),
            "a": _fmt_int(max(0, int(eleitorado * pct / 100.0) - comparecimento)),
            "vv": _fmt_int(validos),
            "vnom": _fmt_int(validos),
            "vb": _fmt_int(brancos),
            "vn": _fmt_int(nulos),
            "tvn": _fmt_int(comparecimento),
            "cand": candidatos,
        }


# Marcador de campo sem dado. Travessao, nao vazio: campo vazio no GC some e
# a cena parece quebrada; travessao mostra que o espaco existe e ainda nao
# chegou numero nenhum.
SEM_DADO = "—"


def boletim_em_branco(abrangencia: str, cargo: int, vagas: int = 5) -> dict[str, Any]:
    """Boletim com a ESTRUTURA do TSE e nenhum conteudo.

    Existe por um pedido direto: o pacote entregue nao pode levar nome de
    candidato inventado. Mas os arquivos precisam existir nos caminhos
    definitivos antes do dia, senao o GC so poderia ser amarrado depois que o
    dado real comecar a chegar - e amarrar cena com o ar aberto e o jeito mais
    caro de fazer isso.

    Entao os arquivos nascem com todos os campos presentes, zerados e com
    travessao no lugar dos nomes. Da para vincular tudo agora, e se algo assim
    for ao ar por engano ninguem le um resultado falso: le um placar vazio,
    que e visivelmente um sistema sem dado.

    A fase vai em branco de proposito. Nao e 'O' (seria mentira) nem 'S'
    (tambem seria: nao houve simulacao nenhuma) - e indefinida, que e o que
    realmente e, e o bastante para o selo aparecer.
    """
    return {
        "ele": "",
        "cdpleito": "",
        "tpabr": "BR" if abrangencia == "br" else ("UF" if len(abrangencia) == 2 else "MU"),
        "cdabr": abrangencia.upper(),
        "nmabr": "BRASIL" if abrangencia == "br" else abrangencia.upper(),
        "carg": str(cargo),
        "f": "",
        "dg": "",
        "hg": "",
        "s": {"st": "0", "s": "0", "pst": "0,00"},
        "ea": "0",
        "c": "0",
        "a": "0",
        "vv": "0",
        "vnom": "0",
        "vb": "0",
        "vn": "0",
        "tvn": "0",
        "cand": [
            {
                "seq": str(indice),
                "sqcand": "",
                "n": "",
                "nm": SEM_DADO,
                "nmt": SEM_DADO,
                "cc": SEM_DADO,
                "nv": "",
                "e": "n",
                "st": "",
                "vap": "0",
                "pvap": "0,00",
            }
            for indice in range(1, max(1, vagas) + 1)
        ],
    }
