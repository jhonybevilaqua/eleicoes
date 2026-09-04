"""Exporters: convertem a Apuracao normalizada no formato lido pelo GC.

Registro por tipo. Para suportar um GC novo, escreva um modulo aqui e
registre o tipo - o nucleo de coleta nao muda.
"""

from __future__ import annotations

from typing import Type

from .base import Exporter
from .arquivo_csv import ExporterCSV
from .arquivo_json import ExporterJSON
from .arquivo_xml import ExporterXML
from .caspar import ExporterCasparCG
from .classx import ExporterClassX
from .http_push import ExporterHTTP
from .viz_tab import ExporterVizTab

REGISTRO: dict[str, Type[Exporter]] = {
    "csv": ExporterCSV,
    "json": ExporterJSON,
    "xml": ExporterXML,
    "casparcg": ExporterCasparCG,
    "classx": ExporterClassX,
    "http": ExporterHTTP,
    "viz_tab": ExporterVizTab,
}


class ExporterDesconhecido(Exception):
    pass


def criar(nome: str, opcoes: dict, cfg_texto: dict, cfg_saida: dict) -> Exporter:
    tipo = str(opcoes.get("tipo", "")).strip().lower()
    if tipo not in REGISTRO:
        raise ExporterDesconhecido(
            f"exporter '{nome}': tipo '{tipo}' desconhecido. Tipos validos: {', '.join(sorted(REGISTRO))}"
        )
    return REGISTRO[tipo](nome=nome, opcoes=opcoes, cfg_texto=cfg_texto, cfg_saida=cfg_saida)


__all__ = ["Exporter", "REGISTRO", "criar", "ExporterDesconhecido"]
