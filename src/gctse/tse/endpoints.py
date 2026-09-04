"""Montagem das URLs da Divulgacao de Resultados do TSE.

O padrao publicado pelo TSE nos ultimos pleitos e:

  {base}/{ciclo}/{pleito}/dados-simplificados/{dir}/{abr}-c{cargo:04}-e{eleicao:06}-r.json
  {base}/{ciclo}/{pleito}/dados/{dir}/{abr}-c{cargo:04}-e{eleicao:06}-r.json

  base    https://resultados.tse.jus.br/oficial
  ciclo   ele2026
  pleito  codigo do pleito/turno (ex.: 619)
  eleicao codigo da eleicao (ex.: 619)
  dir     'br' para nacional, sigla da UF para estadual/municipal
  abr     'br', 'pr' ou 'pr75353' (UF + codigo TSE do municipio)

Os codigos de ciclo/pleito/eleicao de 2026 so sao publicados pelo TSE proximo
ao pleito, por isso TODOS os trechos vem de config (tse.padroes.*) e podem ser
ajustados sem mexer no codigo. Use 'gctse descobrir' para le-los do proprio TSE.
"""

from __future__ import annotations

PADRAO_SIMPLIFICADO = (
    "{base_url}/{ciclo}/{pleito}/dados-simplificados/{dir}/{abr}-c{cargo:04d}-e{eleicao:06d}-r.json"
)
PADRAO_COMPLETO = "{base_url}/{ciclo}/{pleito}/dados/{dir}/{abr}-c{cargo:04d}-e{eleicao:06d}-r.json"
PADRAO_CONFIG_ELEICOES = "{base_url}/comum/config/ele-c.json"
PADRAO_MUNICIPIOS = "{base_url}/{ciclo}/{pleito}/config/{uf}/{uf}-e{eleicao:06d}-i.json"


def diretorio_abrangencia(abrangencia: str) -> str:
    """'br' -> 'br'; 'pr' -> 'pr'; 'pr75353' -> 'pr'."""
    abrangencia = abrangencia.strip().lower()
    return abrangencia[:2] if len(abrangencia) > 2 else abrangencia


def tipo_abrangencia(abrangencia: str) -> str:
    abrangencia = abrangencia.strip().lower()
    if abrangencia == "br":
        return "BR"
    return "UF" if len(abrangencia) == 2 else "MU"


def montar(padrao: str, **partes) -> str:
    """Aplica o padrao de URL convertendo cargo/eleicao para inteiro."""
    partes = dict(partes)
    for campo in ("cargo", "eleicao"):
        if campo in partes:
            partes[campo] = int(str(partes[campo]).lstrip("0") or 0)
    return padrao.format(**partes)


class Endpoints:
    """Fabrica de URLs a partir da secao 'tse' da config."""

    def __init__(self, cfg_tse: dict):
        self.base_url = str(cfg_tse.get("base_url", "https://resultados.tse.jus.br/oficial")).rstrip("/")
        self.ciclo = str(cfg_tse.get("ciclo", "ele2026"))
        self.pleito = str(cfg_tse.get("pleito", ""))
        self.eleicao = str(cfg_tse.get("eleicao", ""))
        padroes = cfg_tse.get("padroes") or {}
        self.p_simplificado = padroes.get("simplificado", PADRAO_SIMPLIFICADO)
        self.p_completo = padroes.get("completo", PADRAO_COMPLETO)
        self.p_config_eleicoes = padroes.get("config_eleicoes", PADRAO_CONFIG_ELEICOES)
        self.p_municipios = padroes.get("municipios", PADRAO_MUNICIPIOS)

    def _comuns(self) -> dict:
        return {
            "base_url": self.base_url,
            "ciclo": self.ciclo,
            "pleito": self.pleito,
            "eleicao": self.eleicao,
        }

    def resultado(self, abrangencia: str, cargo: int, completo: bool = False) -> str:
        padrao = self.p_completo if completo else self.p_simplificado
        return montar(
            padrao,
            **self._comuns(),
            dir=diretorio_abrangencia(abrangencia),
            abr=abrangencia.strip().lower(),
            cargo=cargo,
        )

    def config_eleicoes(self) -> str:
        return montar(self.p_config_eleicoes, **self._comuns())

    def municipios(self, uf: str) -> str:
        return montar(self.p_municipios, **self._comuns(), uf=uf.strip().lower())
