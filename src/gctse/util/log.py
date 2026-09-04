"""Configuracao de log: console + arquivo rotativo por dia de operacao."""

from __future__ import annotations

import logging
import sys
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path

FORMATO = "%(asctime)s %(levelname)-7s [%(name)s] %(message)s"


def configurar(nivel: str = "INFO", arquivo: str | None = None) -> None:
    raiz = logging.getLogger()
    raiz.handlers.clear()
    raiz.setLevel(getattr(logging, str(nivel).upper(), logging.INFO))

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(logging.Formatter(FORMATO, datefmt="%H:%M:%S"))
    raiz.addHandler(console)

    if arquivo:
        caminho = Path(arquivo)
        caminho.parent.mkdir(parents=True, exist_ok=True)
        rotativo = TimedRotatingFileHandler(caminho, when="midnight", backupCount=14, encoding="utf-8")
        rotativo.setFormatter(logging.Formatter(FORMATO))
        raiz.addHandler(rotativo)

    logging.getLogger("urllib3").setLevel(logging.WARNING)
