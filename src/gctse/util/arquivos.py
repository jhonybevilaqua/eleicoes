"""Escrita atomica de arquivos.

Hot folders de GC leem o arquivo assim que ele aparece. Se escrevermos
direto no destino, o GC pode ler um arquivo pela metade e colocar no ar um
placar truncado. Por isso todo arquivo e escrito em .tmp no mesmo volume e
promovido com os.replace(), que e atomico no mesmo sistema de arquivos.
"""

from __future__ import annotations

import os
from pathlib import Path


def escrever_texto(destino: Path, conteudo: str, encoding: str = "utf-8", nova_linha: str = "\r\n") -> Path:
    destino = Path(destino)
    destino.parent.mkdir(parents=True, exist_ok=True)
    temporario = destino.with_name(destino.name + ".tmp")
    dados = conteudo.replace("\r\n", "\n").replace("\r", "\n").replace("\n", nova_linha)
    with open(temporario, "w", encoding=encoding, newline="", errors="replace") as fh:
        fh.write(dados)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(temporario, destino)
    return destino


def escrever_bytes(destino: Path, conteudo: bytes) -> Path:
    destino = Path(destino)
    destino.parent.mkdir(parents=True, exist_ok=True)
    temporario = destino.with_name(destino.name + ".tmp")
    with open(temporario, "wb") as fh:
        fh.write(conteudo)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(temporario, destino)
    return destino
