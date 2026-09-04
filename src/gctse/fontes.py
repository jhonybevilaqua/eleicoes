"""Fontes de dado: TSE ao vivo, simulador ou arquivos locais.

A troca e feita em 'coleta.fonte' na config. Isso permite ensaiar a operacao
inteira (coleta -> normalizacao -> GC) sem tocar no TSE, e reproduzir um dia
de eleicao a partir de amostras gravadas para investigar um problema depois.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any, Protocol

from .simulador import Simulador
from .tse.cliente import ClienteTSE, Resposta
from .tse.endpoints import Endpoints

log = logging.getLogger("gctse.fonte")


class Fonte(Protocol):
    def obter(self, abrangencia: str, cargo: int, turno: int) -> Resposta: ...
    def fechar(self) -> None: ...


class FonteTSE:
    """Producao: le os arquivos publicados pelo TSE."""

    def __init__(self, cliente: ClienteTSE, endpoints: Endpoints, completo: bool = False):
        self.cliente = cliente
        self.endpoints = endpoints
        self.completo = completo

    def obter(self, abrangencia: str, cargo: int, turno: int) -> Resposta:
        url = self.endpoints.resultado(abrangencia, cargo, completo=self.completo)
        return self.cliente.buscar_json(url)

    def fechar(self) -> None:
        self.cliente.fechar()


class FonteSimulada:
    """Ensaio: gera boletins ficticios que evoluem no tempo."""

    def __init__(self, duracao_segundos: int = 900, progresso_fixo: float | None = None):
        self.simulador = Simulador(duracao_segundos=duracao_segundos, progresso_fixo=progresso_fixo)

    def obter(self, abrangencia: str, cargo: int, turno: int) -> Resposta:
        dados = self.simulador.gerar(abrangencia, cargo, turno)
        return Resposta(url=f"simulador://{abrangencia}/c{cargo}/t{turno}", dados=dados, status=200)

    def fechar(self) -> None:
        return None


class FonteArquivo:
    """Reproducao: le amostras gravadas em disco.

    Procura, na pasta indicada, por '<abrangencia>-c<cargo>.json' e, como
    alternativa, por qualquer arquivo cujo nome contenha os dois trechos.
    """

    def __init__(self, pasta: str | Path):
        self.pasta = Path(pasta)

    def obter(self, abrangencia: str, cargo: int, turno: int) -> Resposta:
        candidatos = [
            self.pasta / f"{abrangencia}-c{cargo:04d}.json",
            self.pasta / f"{abrangencia}-c{cargo}.json",
        ]
        arquivo = next((c for c in candidatos if c.exists()), None)
        if arquivo is None:
            correspondentes = sorted(self.pasta.glob(f"*{abrangencia}*c{cargo}*.json"))
            arquivo = correspondentes[0] if correspondentes else None
        if arquivo is None:
            return Resposta(url=str(self.pasta), dados=None, status=404, erro="amostra nao encontrada")
        try:
            dados: Any = json.loads(arquivo.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            return Resposta(url=str(arquivo), dados=None, erro=f"amostra ilegivel: {exc}")
        return Resposta(url=str(arquivo), dados=dados, status=200)

    def fechar(self) -> None:
        return None


def criar_fonte(cfg, cliente: ClienteTSE, endpoints: Endpoints) -> Fonte:
    tipo = str(cfg.coleta.get("fonte", "tse")).lower()
    if tipo == "simulador":
        duracao = int(cfg.coleta.get("simulador_duracao_segundos", 900))
        travado = cfg.coleta.get("simulador_progresso")
        log.warning("FONTE = SIMULADOR (dados ficticios, fase 'S'). Nao use no ar.")
        return FonteSimulada(duracao, float(travado) if travado is not None else None)
    if tipo == "arquivo":
        pasta = cfg.coleta.get("pasta_amostras", "dados/amostras")
        log.warning("FONTE = ARQUIVO (%s). Reproducao de amostras gravadas.", pasta)
        return FonteArquivo(pasta)
    return FonteTSE(cliente, endpoints, completo=bool(cfg.coleta.get("usar_dados_completos", False)))
