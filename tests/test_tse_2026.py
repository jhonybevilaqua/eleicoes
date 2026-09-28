"""Os codigos reais de 2026, e a defesa contra o bloqueio por 404.

O TSE publicou, para o 1o turno de 04/10/2026:

    pleito 3220
      6257  Eleicao Geral Federal ....... presidente, senador, dep. federal
      6259  Eleicoes Gerais Estaduais ... governador, dep. estadual/distrital
      6261  Eleicao Conselho Distrital

Dois fatos da documentacao do ambiente oficial moldam este arquivo:

1. UM PLEITO, VARIAS ELEICOES. Cada cargo so existe no arquivo da sua. Pedir
   governador com o codigo federal nao devolve dado velho nem erro claro:
   devolve 404.
2. "Multiplos erros 404 podem provocar o bloqueio temporario do endereco IP."
   E 404 e o estado normal durante horas - antes de as urnas fecharem nenhum
   arquivo existe. Insistir de forma ingenua, com 28 pracas a cada 20s, leva
   ao bloqueio justo quando o dado ia comecar a sair.
"""

from pathlib import Path

import pytest

from gctse.config import Config
from gctse.tse.compasso import Compasso
from gctse.tse.endpoints import Endpoints

PLEITO_2026 = {
    "base_url": "https://resultados.tse.jus.br/oficial",
    "ciclo": "ele2026",
    "pleito": "3220",
    "eleicoes": {"federal": "6257", "estadual": "6259"},
}


# --- um pleito, varias eleicoes -------------------------------------------

@pytest.mark.parametrize("cargo, esperado", [
    (1, "6257"),    # presidente
    (5, "6257"),    # senador
    (6, "6257"),    # deputado federal
    (3, "6259"),    # governador
    (7, "6259"),    # deputado estadual
    (8, "6259"),    # deputado distrital
])
def test_cada_cargo_usa_a_eleicao_em_que_e_apurado(cargo, esperado):
    assert Endpoints(PLEITO_2026).eleicao_do_cargo(cargo) == esperado


def test_url_de_2026_sai_no_formato_publicado_pelo_tse():
    endpoints = Endpoints(PLEITO_2026)
    assert endpoints.resultado("br", 1) == (
        "https://resultados.tse.jus.br/oficial/ele2026/3220"
        "/dados-simplificados/br/br-c0001-e006257-r.json"
    )
    # governador do Parana: mesma data, OUTRA eleicao
    assert endpoints.resultado("pr", 3) == (
        "https://resultados.tse.jus.br/oficial/ele2026/3220"
        "/dados-simplificados/pr/pr-c0003-e006259-r.json"
    )


def test_eleicao_solta_continua_valendo_para_quem_so_cobre_um_conjunto():
    """Config antiga, com um codigo so, nao pode parar de funcionar."""
    antiga = {**PLEITO_2026, "eleicoes": None, "eleicao": "6257"}
    assert Endpoints(antiga).eleicao_do_cargo(1) == "6257"
    assert Endpoints(antiga).eleicao_do_cargo(3) == "6257"


def test_cargo_pode_ser_apontado_um_a_um():
    """Escape para o caso de o TSE dividir os cargos de outro jeito."""
    ajustada = {**PLEITO_2026, "eleicao_por_cargo": {5: "6261"}}
    assert Endpoints(ajustada).eleicao_do_cargo(5) == "6261"
    assert Endpoints(ajustada).eleicao_do_cargo(1) == "6257"


def test_validacao_cobra_a_eleicao_de_CADA_cargo_configurado():
    """O caso que quebra de verdade: federal preenchida, estadual em branco.

    Antes a validacao olhava um 'tse.eleicao' generico e dava OK - e so o
    alvo de governador batia em 404, a noite inteira.
    """
    cfg = Config(
        bruto={
            "tse": {**PLEITO_2026, "eleicoes": {"federal": "6257", "estadual": "000"}},
            "coleta": {"fonte": "tse", "intervalo_segundos": 20},
            "exporters": {"j": {"tipo": "json"}},
            "alvos": [
                {"nome": "presidente", "abrangencia": "br", "cargo": 1, "exporters": ["j"]},
                {"nome": "governador", "abrangencia": "pr", "cargo": 3, "exporters": ["j"]},
            ],
        },
        caminho=Path("config.yaml"),
    )
    erros, pendencias = cfg.conferir()
    assert erros == []
    assert len(pendencias) == 1
    assert "cargo 3" in pendencias[0]          # aponta o cargo, nao 'tse.eleicao'


# --- nao apanhar do TSE por insistencia -----------------------------------

def test_o_404_espaca_as_tentativas_em_vez_de_insistir():
    compasso = Compasso(tolerancia=2, base_segundos=30, teto_segundos=300)
    agora = 0.0
    # os primeiros passam batido: a praca pode publicar no proximo ciclo
    assert compasso.registrar_404("br", agora) == 0
    assert compasso.registrar_404("br", agora) == 0
    assert compasso.pode_tentar("br", agora)
    # a partir dai, dobra
    assert compasso.registrar_404("br", agora) == 30
    assert not compasso.pode_tentar("br", agora)
    assert compasso.pode_tentar("br", agora + 31)
    assert compasso.registrar_404("br", agora) == 60
    assert compasso.registrar_404("br", agora) == 120


def test_a_espera_tem_teto():
    """Teto para que a praca que publicar tarde nao fique meia hora invisivel."""
    compasso = Compasso(tolerancia=0, base_segundos=30, teto_segundos=300)
    esperas = [compasso.registrar_404("br", 0.0) for _ in range(12)]
    assert max(esperas) == 300


def test_publicou_volta_ao_ritmo_normal_no_ciclo_seguinte():
    compasso = Compasso(tolerancia=0, base_segundos=30)
    compasso.registrar_404("br", 0.0)
    assert not compasso.pode_tentar("br", 0.0)
    compasso.registrar_ok("br")
    assert compasso.pode_tentar("br", 0.0)
    assert compasso.espera_de("br") == 0


def test_a_espera_e_por_praca_e_nao_atrasa_as_outras():
    """O Acre nao ter publicado nao pode atrasar a leitura de Sao Paulo."""
    compasso = Compasso(tolerancia=0, base_segundos=30)
    compasso.registrar_404("ac", 0.0)
    assert not compasso.pode_tentar("ac", 0.0)
    assert compasso.pode_tentar("sp", 0.0)
