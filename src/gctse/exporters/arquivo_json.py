"""JSON - para GCs modernos, paginas de segunda tela e integracoes web."""

from __future__ import annotations

import json
from pathlib import Path

from ..modelos import Apuracao
from ..util.arquivos import escrever_texto
from .base import Exporter


class ExporterJSON(Exporter):
    tipo = "json"

    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        formato = str(self.opcoes.get("formato", "completo")).lower()
        if formato == "gc":
            # campos ja formatados (texto pronto para o ar)
            corpo = {"resumo": self.campos_resumo(ap), "candidatos": self.linhas(ap)}
        elif formato == "largo":
            corpo = self.achatado(ap)
        elif formato == "bruto":
            corpo = ap.bruto
        else:
            corpo = ap.como_dict()

        indentacao = self.opcoes.get("indentacao", 2)
        texto = json.dumps(corpo, ensure_ascii=bool(self.opcoes.get("ascii", False)), indent=indentacao)
        destino = self.caminho_saida(ap, nome_alvo, str(self.opcoes.get("extensao", ".json")))
        return [escrever_texto(destino, texto, encoding=self.encoding, nova_linha=self.nova_linha)]
