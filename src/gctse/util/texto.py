"""Normalizacao de texto para exibicao no gerador de caracteres.

GCs variam muito: alguns nao renderizam acentos vindos de fonte externa,
outros estouram o layout com nomes longos, e quase todos tem limite de
caracteres por campo. As funcoes aqui sao aplicadas conforme a config.
"""

from __future__ import annotations

import re
import unicodedata

_ESPACOS = re.compile(r"\s+")


def limpar(texto) -> str:
    """Colapsa espacos e remove caracteres de controle."""
    if texto is None:
        return ""
    texto = str(texto).replace("\r", " ").replace("\n", " ").replace("\t", " ")
    texto = "".join(c for c in texto if unicodedata.category(c)[0] != "C")
    return _ESPACOS.sub(" ", texto).strip()


def sem_acento(texto: str) -> str:
    """'JOSE DA SILVA JUNIOR' sem diacriticos, para GCs legados."""
    decomposto = unicodedata.normalize("NFD", texto)
    return "".join(c for c in decomposto if unicodedata.category(c) != "Mn")


def truncar(texto: str, limite: int, reticencia: str = "") -> str:
    """Corta no limite de caracteres sem quebrar no meio da palavra."""
    if limite <= 0 or len(texto) <= limite:
        return texto
    alvo = limite - len(reticencia)
    if alvo <= 0:
        return texto[:limite]
    corte = texto[:alvo]
    if " " in corte:
        corte = corte[: corte.rindex(" ")]
    return corte.rstrip() + reticencia


def aplicar_caixa(texto: str, caixa: str) -> str:
    """caixa: 'alta' | 'baixa' | 'titulo' | 'original'."""
    if caixa == "alta":
        return texto.upper()
    if caixa == "baixa":
        return texto.lower()
    if caixa == "titulo":
        return " ".join(p.capitalize() if len(p) > 2 else p.lower() for p in texto.split())
    return texto


def normalizar(
    texto,
    *,
    caixa: str = "original",
    remover_acentos: bool = False,
    limite: int = 0,
    reticencia: str = "",
) -> str:
    """Pipeline completo de saneamento aplicado a cada campo de texto."""
    resultado = limpar(texto)
    if remover_acentos:
        resultado = sem_acento(resultado)
    resultado = aplicar_caixa(resultado, caixa)
    return truncar(resultado, limite, reticencia)


def slug(texto: str) -> str:
    """Nome seguro para arquivo: 'BR - Presidente' -> 'br-presidente'."""
    base = sem_acento(limpar(texto)).lower()
    base = re.sub(r"[^a-z0-9]+", "-", base)
    return base.strip("-") or "sem-nome"
