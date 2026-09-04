"""CSV/TSV - o formato mais universal entre GCs.

Atende Ross XPression (DataLinq CSV), Chyron, planilhas de apoio da producao
e importadores caseiros. Dois layouts:

  layout: linhas  -> uma linha por candidato (placar/lista)
  layout: largo   -> uma unica linha com todos os campos (take unico)

Atencao ao encoding: varios GCs legados leem em cp1252/latin-1. Se o nome do
candidato sair com acento quebrado no ar, troque 'encoding' na config.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path

from ..modelos import Apuracao
from ..util.arquivos import escrever_texto
from .base import Exporter


class ExporterCSV(Exporter):
    tipo = "csv"

    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        delimitador = str(self.opcoes.get("delimitador", ","))
        if delimitador.lower() in ("tab", "\\t"):
            delimitador = "\t"
        layout = str(self.opcoes.get("layout", "linhas")).lower()
        cabecalho = bool(self.opcoes.get("cabecalho", True))
        extensao = str(self.opcoes.get("extensao", ".tsv" if delimitador == "\t" else ".csv"))
        incluir_resumo = bool(self.opcoes.get("incluir_resumo_nas_linhas", True))
        colunas_cfg = self.opcoes.get("colunas") or []

        escritos: list[Path] = []

        if layout == "largo":
            registro = self.achatado(ap)
            colunas = colunas_cfg or list(registro.keys())
            conteudo = self._render([{c: registro.get(c, "") for c in colunas}], colunas, delimitador, cabecalho)
            escritos.append(self._gravar(ap, nome_alvo, extensao, "", conteudo))
            return escritos

        resumo = self.campos_resumo(ap)
        linhas = []
        for linha in self.linhas(ap):
            registro = {**{f"ap_{k}": v for k, v in resumo.items()}, **linha} if incluir_resumo else dict(linha)
            linhas.append(registro)

        colunas = colunas_cfg or (list(linhas[0].keys()) if linhas else list(self.campos_resumo(ap).keys()))
        normalizadas = [{c: l.get(c, "") for c in colunas} for l in linhas]
        conteudo = self._render(normalizadas, colunas, delimitador, cabecalho)
        escritos.append(self._gravar(ap, nome_alvo, extensao, "", conteudo))

        # arquivo de resumo separado: muitos templates usam so o cabecalho
        if self.opcoes.get("arquivo_resumo", True):
            colunas_resumo = list(resumo.keys())
            conteudo_resumo = self._render([resumo], colunas_resumo, delimitador, cabecalho)
            escritos.append(self._gravar(ap, nome_alvo, extensao, "-resumo", conteudo_resumo))
        return escritos

    def _render(self, linhas: list[dict], colunas: list[str], delimitador: str, cabecalho: bool) -> str:
        buffer = io.StringIO()
        escritor = csv.DictWriter(
            buffer,
            fieldnames=colunas,
            delimiter=delimitador,
            lineterminator="\n",
            extrasaction="ignore",
            quoting=csv.QUOTE_MINIMAL,
        )
        if cabecalho:
            escritor.writeheader()
        for linha in linhas:
            escritor.writerow(linha)
        return buffer.getvalue()

    def _gravar(self, ap: Apuracao, nome_alvo: str, extensao: str, sufixo: str, conteudo: str) -> Path:
        destino = self.caminho_saida(ap, nome_alvo, extensao, sufixo)
        return escrever_texto(destino, conteudo, encoding=self.encoding, nova_linha=self.nova_linha)
