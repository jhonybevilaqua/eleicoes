"""XML - formato aceito por praticamente todo GC com data linkage.

Perfis (opcao 'perfil'):

  generico  <apuracao><resumo/><candidatos><candidato/></candidatos></apuracao>
  tabular   <records><record><field name="..">valor</field></record></records>
            (Chyron Lyric/PRIME e importadores genericos)
  atributos <data><row nome=".." votos=".."/></data>
            (Viz Pilot data feed e leitores por atributo)

Todos os valores sao escapados pelo ElementTree - nome com "&" nao quebra o XML.
"""

from __future__ import annotations

from pathlib import Path
from xml.etree import ElementTree as ET

from ..modelos import Apuracao
from ..util.arquivos import escrever_texto
from .base import Exporter


def _indentar(elemento: ET.Element, nivel: int = 0) -> None:
    espaco = "\n" + "  " * nivel
    if len(elemento):
        if not (elemento.text or "").strip():
            elemento.text = espaco + "  "
        for filho in elemento:
            _indentar(filho, nivel + 1)
        if not (elemento.tail or "").strip():
            elemento.tail = espaco
        if not (elemento[-1].tail or "").strip():
            elemento[-1].tail = espaco
    elif nivel and not (elemento.tail or "").strip():
        elemento.tail = espaco


class ExporterXML(Exporter):
    tipo = "xml"

    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        perfil = str(self.opcoes.get("perfil", "generico")).lower()
        resumo = self.campos_resumo(ap)
        linhas = self.linhas(ap)

        if perfil == "tabular":
            raiz = self._tabular(resumo, linhas)
        elif perfil == "atributos":
            raiz = self._atributos(resumo, linhas)
        else:
            raiz = self._generico(resumo, linhas)

        _indentar(raiz)
        declaracao = f'<?xml version="1.0" encoding="{self.encoding}"?>\n'
        texto = declaracao + ET.tostring(raiz, encoding="unicode")
        destino = self.caminho_saida(ap, nome_alvo, str(self.opcoes.get("extensao", ".xml")))
        return [escrever_texto(destino, texto, encoding=self.encoding, nova_linha=self.nova_linha)]

    def _generico(self, resumo: dict, linhas: list[dict]) -> ET.Element:
        raiz = ET.Element(str(self.opcoes.get("raiz", "apuracao")))
        no_resumo = ET.SubElement(raiz, "resumo")
        for chave, valor in resumo.items():
            ET.SubElement(no_resumo, chave).text = valor
        no_cands = ET.SubElement(raiz, "candidatos")
        for linha in linhas:
            no = ET.SubElement(no_cands, "candidato", {"posicao": linha["posicao"]})
            for chave, valor in linha.items():
                ET.SubElement(no, chave).text = valor
        return raiz

    def _tabular(self, resumo: dict, linhas: list[dict]) -> ET.Element:
        raiz = ET.Element(str(self.opcoes.get("raiz", "records")))
        for linha in linhas:
            registro = ET.SubElement(raiz, str(self.opcoes.get("registro", "record")))
            combinada = {**{f"ap_{k}": v for k, v in resumo.items()}, **linha}
            for chave, valor in combinada.items():
                campo = ET.SubElement(registro, "field", {"name": chave})
                campo.text = valor
        return raiz

    def _atributos(self, resumo: dict, linhas: list[dict]) -> ET.Element:
        raiz = ET.Element(str(self.opcoes.get("raiz", "data")), {k: v for k, v in resumo.items()})
        for linha in linhas:
            ET.SubElement(raiz, str(self.opcoes.get("registro", "row")), linha)
        return raiz
