"""Push HTTP - entrega o placar direto na API do GC, num broker ou no
Power Automate / Teams.

Nao grava arquivo: faz POST (ou PUT) do JSON. Falha de entrega e registrada e
nao interrompe o ciclo - o proximo boletim tenta de novo, e o GC segue no ar
com o ultimo dado bom.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

import requests

from ..modelos import Apuracao
from .base import Exporter

log = logging.getLogger("gctse.exporter.http")


class ExporterHTTP(Exporter):
    tipo = "http"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.url = str(self.opcoes.get("url", "")).strip()
        self.metodo = str(self.opcoes.get("metodo", "POST")).upper()
        self.timeout = float(self.opcoes.get("timeout", 5))
        self.cabecalhos = {"Content-Type": "application/json; charset=utf-8"}
        self.cabecalhos.update(self.opcoes.get("cabecalhos") or {})
        self.sessao = requests.Session()

    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        if not self.url:
            log.error("exporter '%s': url nao configurada", self.nome)
            return []

        formato = str(self.opcoes.get("formato", "gc")).lower()
        if formato == "largo":
            corpo = self.achatado(ap)
        elif formato == "completo":
            corpo = ap.como_dict()
        else:
            corpo = {"alvo": nome_alvo, "resumo": self.campos_resumo(ap), "candidatos": self.linhas(ap)}

        try:
            resposta = self.sessao.request(
                self.metodo,
                self.url,
                data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
                headers=self.cabecalhos,
                timeout=self.timeout,
            )
            if not resposta.ok:
                log.error("exporter '%s': %s respondeu HTTP %s", self.nome, self.url, resposta.status_code)
            else:
                log.debug("exporter '%s': entregue em %s (%s)", self.nome, self.url, resposta.status_code)
        except requests.RequestException as exc:
            log.error("exporter '%s': falha ao entregar em %s: %s", self.nome, self.url, exc)
        return []
