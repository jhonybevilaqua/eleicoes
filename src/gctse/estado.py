"""Estado persistente entre ciclos e entre reinicios.

Guarda, por alvo, a ultima impressao digital publicada e o instante de geracao
no TSE. Serve para dois controles que evitam erro no ar:

1. Deduplicacao - se o boletim nao mudou, nao reescreve o arquivo do GC
   (o hot folder nao "pisca" e o operador nao ve take falso de atualizacao).
2. Anti-regressao - a CDN do TSE pode servir uma copia antiga de um no
   diferente. Se chegar um boletim com data/hora de geracao ANTERIOR a que ja
   publicamos, ele e descartado: o placar nunca anda para tras no ar.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any

from .util.arquivos import escrever_texto

log = logging.getLogger("gctse.estado")


class Estado:
    def __init__(self, caminho: str | Path):
        self.caminho = Path(caminho)
        self.dados: dict[str, dict[str, Any]] = {}
        self.carregar()

    def carregar(self) -> None:
        if not self.caminho.exists():
            return
        try:
            self.dados = json.loads(self.caminho.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            log.warning("estado ilegivel em %s (%s); comecando do zero", self.caminho, exc)
            self.dados = {}

    def salvar(self) -> None:
        try:
            escrever_texto(self.caminho, json.dumps(self.dados, ensure_ascii=False, indent=2), nova_linha="\n")
        except OSError as exc:
            log.error("nao foi possivel gravar o estado em %s: %s", self.caminho, exc)

    # --- consultas ---

    def impressao(self, chave: str) -> str:
        return str(self.dados.get(chave, {}).get("impressao", ""))

    def gerado_em(self, chave: str) -> datetime | None:
        texto = self.dados.get(chave, {}).get("gerado_em")
        if not texto:
            return None
        try:
            return datetime.fromisoformat(texto)
        except ValueError:
            return None

    def mudou(self, chave: str, impressao: str) -> bool:
        return self.impressao(chave) != impressao

    def regrediu(self, chave: str, gerado_em: datetime | None) -> bool:
        anterior = self.gerado_em(chave)
        if anterior is None or gerado_em is None:
            return False
        return gerado_em < anterior

    # --- atualizacao ---

    def registrar(self, chave: str, impressao: str, gerado_em: datetime | None, extra: dict | None = None) -> None:
        registro = {
            "impressao": impressao,
            "gerado_em": gerado_em.isoformat() if gerado_em else "",
            "atualizado_em": datetime.now().isoformat(timespec="seconds"),
        }
        if extra:
            registro.update(extra)
        self.dados[chave] = registro
