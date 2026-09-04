"""Conversao de numeros no formato pt-BR usado pelo TSE.

O TSE publica numeros como texto: votos com separador de milhar por ponto
("12.345.678") e percentuais com virgula decimal ("49,10"). Converter isso
com int()/float() direto quebra; todas as leituras passam por aqui.
"""

from __future__ import annotations

import re

_SO_DIGITOS = re.compile(r"[^\d\-]")


def para_int(valor, padrao: int = 0) -> int:
    """'12.345.678' -> 12345678. Vazio/invalido -> padrao."""
    if valor is None:
        return padrao
    if isinstance(valor, bool):
        return padrao
    if isinstance(valor, int):
        return valor
    if isinstance(valor, float):
        return int(valor)
    texto = _SO_DIGITOS.sub("", str(valor))
    if texto in ("", "-"):
        return padrao
    try:
        return int(texto)
    except ValueError:
        return padrao


def para_float(valor, padrao: float = 0.0) -> float:
    """'49,10' -> 49.1 ; '1.234,56' -> 1234.56. Vazio/invalido -> padrao."""
    if valor is None:
        return padrao
    if isinstance(valor, bool):
        return padrao
    if isinstance(valor, (int, float)):
        return float(valor)
    texto = str(valor).strip()
    if not texto:
        return padrao
    texto = texto.replace("%", "").replace(" ", "")
    if "," in texto:
        # formato pt-BR: ponto e milhar, virgula e decimal
        texto = texto.replace(".", "").replace(",", ".")
    try:
        return float(texto)
    except ValueError:
        return padrao


def formatar_int(valor: int, separador: str = ".") -> str:
    """12345678 -> '12.345.678' (para exibicao no GC)."""
    return f"{int(valor):,}".replace(",", "\x00").replace("\x00", separador)


def formatar_pct(valor: float, casas: int = 2, sufixo: str = "%") -> str:
    """49.1 -> '49,10%' (para exibicao no GC)."""
    texto = f"{float(valor):.{casas}f}".replace(".", ",")
    return f"{texto}{sufixo}"
