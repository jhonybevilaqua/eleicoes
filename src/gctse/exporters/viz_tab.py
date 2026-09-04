"""Viz Trio - arquivo de tab fields.

O Trio importa listas em texto delimitado por TAB, uma linha por take e um
campo por coluna, na ordem em que os campos aparecem na pagina. A ordem das
colunas vem de 'campos' na config - ela precisa casar com a ordem dos tab
fields da pagina do Trio.
"""

from __future__ import annotations

from pathlib import Path

from ..modelos import Apuracao
from ..util.arquivos import escrever_texto
from .base import Exporter

CAMPOS_PADRAO = ["posicao", "nome", "partido", "votos", "percentual"]


class ExporterVizTab(Exporter):
    tipo = "viz_tab"

    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        campos = list(self.opcoes.get("campos") or CAMPOS_PADRAO)
        incluir_cabecalho = bool(self.opcoes.get("cabecalho", False))
        resumo = self.campos_resumo(ap)

        linhas: list[str] = []
        if incluir_cabecalho:
            linhas.append("\t".join(campos))
        for linha in self.linhas(ap):
            fonte = {**{f"ap_{k}": v for k, v in resumo.items()}, **linha}
            # TAB dentro do valor quebraria a coluna; ja e removido em limpar()
            linhas.append("\t".join(str(fonte.get(campo, "")) for campo in campos))

        destino = self.caminho_saida(ap, nome_alvo, str(self.opcoes.get("extensao", ".txt")))
        return [
            escrever_texto(destino, "\n".join(linhas) + "\n", encoding=self.encoding, nova_linha=self.nova_linha)
        ]
