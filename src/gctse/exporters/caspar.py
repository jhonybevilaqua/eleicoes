"""CasparCG - templateData XML e JSON de dados.

O CasparCG recebe dados de template no formato:

  <templateData>
    <componentData id="f0"><data id="text" value="LULA"/></componentData>
  </templateData>

Este exporter gera esse XML (mapeando os campos do placar para f0, f1, ... ou
para nomes definidos em 'mapa_campos') e, opcionalmente, um JSON com os mesmos
dados para templates HTML que leem via fetch.
"""

from __future__ import annotations

from pathlib import Path
from xml.etree import ElementTree as ET

import json

from ..modelos import Apuracao
from ..util.arquivos import escrever_texto
from .base import Exporter


class ExporterCasparCG(Exporter):
    tipo = "casparcg"

    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        plano = self.achatado(ap)
        mapa = self.opcoes.get("mapa_campos") or {}
        if mapa:
            # mapa_campos: { "f0": "cand1_nome", "f1": "cand1_votos", ... }
            campos = {destino: plano.get(origem, "") for destino, origem in mapa.items()}
        elif self.opcoes.get("numerar_campos", False):
            campos = {f"f{i}": valor for i, valor in enumerate(plano.values())}
        else:
            campos = plano

        escritos: list[Path] = []

        raiz = ET.Element("templateData")
        for chave, valor in campos.items():
            componente = ET.SubElement(raiz, "componentData", {"id": chave})
            ET.SubElement(componente, "data", {"id": "text", "value": valor})
        texto = '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(raiz, encoding="unicode")
        escritos.append(
            escrever_texto(
                self.caminho_saida(ap, nome_alvo, ".xml"), texto, encoding=self.encoding, nova_linha=self.nova_linha
            )
        )

        if self.opcoes.get("gerar_json", True):
            escritos.append(
                escrever_texto(
                    self.caminho_saida(ap, nome_alvo, ".json"),
                    json.dumps(campos, ensure_ascii=False, indent=2),
                    encoding=self.encoding,
                    nova_linha=self.nova_linha,
                )
            )
        return escritos
