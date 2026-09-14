"""Rodizio de pracas: um arquivo com N praticas em N registros.

Governador e senador sao disputados em 27 unidades da federacao, e a tarja
roda um punhado delas por bloco. Duas formas de resolver isso no GC:

  um arquivo por praca      o GC precisa trocar de fonte de dados a cada take
  UM arquivo com N registros o GC itera registros  <- e o que este exporter faz

A segunda e a que combina com rodizio: a cena tem uma fonte so, e o GC avanca
de registro em registro no ritmo que o operador definir. Quem manda no tempo do
ar continua sendo o GC, nao a automacao - trocar isso de lado tira do operador
o controle do que esta no video.

A GEOMETRIA e fixa, pelo mesmo motivo de sempre: a lista tem exatamente o
numero de pracas configuradas, na ordem configurada, do primeiro ao ultimo
boletim do dia. Praca cujo boletim ainda nao saiu entra como registro vazio com
'visivel' em "0" - nunca encolhe a lista e desloca o resto.
"""

from __future__ import annotations

import csv
import io
import json
from pathlib import Path
from xml.etree import ElementTree as ET

from ..modelos import Apuracao
from ..util.arquivos import escrever_texto
from .arquivo_xml import _indentar
from .base import Exporter

CAMPOS_PADRAO = [
    "ordem",
    "visivel",
    "praca",
    "praca_codigo",
    "cargo",
    "apuracao_pct",
    "apuracao_pct_num",
    "selo",
    "cand1_nome",
    "cand1_partido",
    "cand1_nome_partido",
    "cand1_percentual",
    "cand1_percentual_num",
    "cand1_votos",
    "cand1_cor",
    "cand1_barra_px",
    "cand1_eleito",
    "cand2_nome",
    "cand2_partido",
    "cand2_nome_partido",
    "cand2_percentual",
    "cand2_percentual_num",
    "cand2_votos",
    "cand2_cor",
    "cand2_barra_px",
    "cand2_eleito",
]

NUMERICOS = {"ordem", "apuracao_pct_num", "cand1_percentual_num", "cand2_percentual_num",
             "cand1_barra_px", "cand2_barra_px"}


class ExporterRodizio(Exporter):
    tipo = "rodizio"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.formato = str(self.opcoes.get("formato", "json")).lower()
        self.colunas = list(self.opcoes.get("campos") or CAMPOS_PADRAO)
        self.formato_nome_partido = str(self.opcoes.get("formato_nome_partido", "{nome} ({partido})"))
        self.vazio = str(self.opcoes.get("preencher_vazio", ""))
        self.cabecalho = bool(self.opcoes.get("cabecalho", True))
        delim = str(self.opcoes.get("delimitador", ";"))
        self.delimitador = "\t" if delim.lower() in ("tab", "\\t") else delim
        self.extensao = str(
            self.opcoes.get("extensao", {"xml": ".xml", "csv": ".csv"}.get(self.formato, ".json"))
        )

    # Um exporter de rodizio nao trabalha com uma apuracao isolada.
    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        raise NotImplementedError("exporter 'rodizio' recebe uma lista de pracas, nao um alvo isolado")

    # --- montagem dos registros ---

    def _registro_vazio(self, ordem: int, praca: str) -> dict[str, str]:
        registro = {campo: self.vazio for campo in self.colunas}
        registro["ordem"] = str(ordem)
        registro["visivel"] = "0"
        if "praca" in registro:
            registro["praca"] = self._txt(praca, "abrangencia")
        return registro

    def _registro(self, ordem: int, ap: Apuracao) -> dict[str, str]:
        resumo = self.campos_resumo(ap)
        dados: dict[str, str] = {
            "ordem": str(ordem),
            "visivel": "1",
            "praca": resumo["abrangencia"],
            "praca_codigo": resumo["abrangencia_codigo"],
            "cargo": resumo["cargo"],
            "apuracao_pct": resumo["apuracao_pct"],
            "apuracao_pct_num": resumo["apuracao_pct_num"],
            "selo": resumo["selo"],
        }
        for indice in (1, 2):
            cand = ap.candidatos[indice - 1] if len(ap.candidatos) >= indice else None
            campos = self.campos_candidato(cand, ap) if cand else {}
            for chave, valor in campos.items():
                dados[f"cand{indice}_{chave}"] = valor
            nome = campos.get("nome", "")
            partido = campos.get("partido", "")
            dados[f"cand{indice}_nome_partido"] = (
                self.formato_nome_partido.format(nome=nome, partido=partido) if partido else nome
            )
        return {campo: dados.get(campo, self.vazio) for campo in self.colunas}

    def montar(self, itens: list[tuple[int, str, Apuracao | None]]) -> list[dict[str, str]]:
        return [
            self._registro(ordem, ap) if ap else self._registro_vazio(ordem, praca)
            for ordem, praca, ap in itens
        ]

    # --- escrita ---

    def exportar_lista(self, itens: list[tuple[int, str, Apuracao | None]], nome: str) -> list[Path]:
        registros = self.montar(itens)
        destino = self.destino / f"{nome}{self.extensao}"
        if self.formato == "xml":
            texto = self._xml(registros, nome)
        elif self.formato == "csv":
            texto = self._csv(registros)
        else:
            texto = self._json(registros, nome)
        return [escrever_texto(destino, texto, encoding=self.encoding, nova_linha=self.nova_linha)]

    def _tipar(self, campo: str, valor: str):
        if campo not in NUMERICOS:
            return valor
        texto = str(valor).strip()
        if not texto:
            return None
        try:
            return int(texto) if "." not in texto else float(texto)
        except ValueError:
            return None

    def _json(self, registros: list[dict], nome: str) -> str:
        corpo = {
            "rodizio": nome,
            "total": len(registros),
            "com_dado": sum(1 for r in registros if r.get("visivel") == "1"),
            "pracas": [{c: self._tipar(c, r.get(c, self.vazio)) for c in self.colunas} for r in registros],
        }
        return json.dumps(corpo, ensure_ascii=False, indent=2)

    def _xml(self, registros: list[dict], nome: str) -> str:
        raiz = ET.Element("rodizio", {"nome": nome, "total": str(len(registros))})
        for registro in registros:
            no = ET.SubElement(raiz, "praca", {"ordem": registro.get("ordem", "")})
            for campo in self.colunas:
                ET.SubElement(no, campo).text = str(registro.get(campo, self.vazio))
        _indentar(raiz)
        return f'<?xml version="1.0" encoding="{self.encoding}"?>\n' + ET.tostring(raiz, encoding="unicode")

    def _csv(self, registros: list[dict]) -> str:
        buffer = io.StringIO()
        escritor = csv.DictWriter(
            buffer, fieldnames=self.colunas, delimiter=self.delimitador,
            lineterminator="\n", extrasaction="ignore", quoting=csv.QUOTE_MINIMAL,
        )
        if self.cabecalho:
            escritor.writeheader()
        for registro in registros:
            escritor.writerow(registro)
        return buffer.getvalue()
