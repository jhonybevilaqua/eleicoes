"""Descoberta dos codigos do pleito e inspecao de arquivos do TSE.

Os codigos de ciclo/pleito/eleicao de 2026 so ficam disponiveis quando o TSE
publica a configuracao do pleito. Estas funcoes leem essa configuracao e
ajudam a preencher a secao 'tse' do config.yaml sem adivinhacao.
"""

from __future__ import annotations

import logging
from typing import Any

from .cliente import ClienteTSE
from .endpoints import Endpoints

log = logging.getLogger("gctse.descoberta")

# Chaves ja usadas pelo TSE no ele-c.json, em ordem de preferencia.
_CH_ELEICOES = ["pl", "pleitos", "eleicoes", "e"]
_CH_CODIGO = ["cd", "cdpleito", "codigo", "id"]
_CH_NOME = ["nm", "nmpleito", "nome", "dsc"]
_CH_DATA = ["dt", "dtpleito", "data"]
_CH_TURNO = ["t", "turno", "nrturno"]


def _primeiro(origem: dict, chaves: list[str], padrao: Any = None) -> Any:
    for chave in chaves:
        if chave in origem and origem[chave] not in (None, ""):
            return origem[chave]
    return padrao


def listar_eleicoes(cliente: ClienteTSE, endpoints: Endpoints) -> list[dict[str, Any]]:
    """Le o ele-c.json e devolve os pleitos publicados, achatados."""
    url = endpoints.config_eleicoes()
    resposta = cliente.buscar_json(url)
    if not resposta.ok:
        log.error("nao foi possivel ler %s: %s", url, resposta.erro or resposta.status)
        return []

    dados = resposta.dados or {}
    bruto = _primeiro(dados, _CH_ELEICOES, [])
    if isinstance(bruto, dict):
        bruto = list(bruto.values())

    achatado: list[dict[str, Any]] = []

    def _absorver(item: Any) -> None:
        if not isinstance(item, dict):
            return
        codigo = _primeiro(item, _CH_CODIGO)
        if codigo is not None:
            achatado.append(
                {
                    "codigo": str(codigo),
                    "nome": str(_primeiro(item, _CH_NOME, "") or ""),
                    "data": str(_primeiro(item, _CH_DATA, "") or ""),
                    "turno": str(_primeiro(item, _CH_TURNO, "") or ""),
                    "bruto": item,
                }
            )
        for valor in item.values():  # pleitos costumam vir aninhados
            if isinstance(valor, list):
                for filho in valor:
                    _absorver(filho)

    for item in bruto if isinstance(bruto, list) else []:
        _absorver(item)
    return achatado


def inspecionar(cliente: ClienteTSE, url: str, limite: int = 40) -> dict[str, Any]:
    """Baixa um arquivo e resume suas chaves - usado para conferir o mapeamento."""
    resposta = cliente.buscar_json(url)
    if not resposta.ok:
        return {"url": url, "erro": resposta.erro or f"HTTP {resposta.status}"}

    dados = resposta.dados or {}
    resumo: dict[str, Any] = {"url": url, "chaves_raiz": {}, "amostra_candidato": {}}
    for chave, valor in list(dados.items())[:limite]:
        if isinstance(valor, list):
            resumo["chaves_raiz"][chave] = f"<lista com {len(valor)} itens>"
        elif isinstance(valor, dict):
            resumo["chaves_raiz"][chave] = {k: str(v)[:40] for k, v in list(valor.items())[:12]}
        else:
            resumo["chaves_raiz"][chave] = str(valor)[:60]

    for chave in ("cand", "candidatos", "cands"):
        lista = dados.get(chave)
        if isinstance(lista, list) and lista and isinstance(lista[0], dict):
            resumo["amostra_candidato"] = {k: str(v)[:60] for k, v in lista[0].items()}
            resumo["qtd_candidatos"] = len(lista)
            break
    return resumo
