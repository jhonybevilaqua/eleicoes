"""Modo Simulado / Producao, e a estrutura em branco.

Os dois assuntos vivem no mesmo arquivo porque respondem a mesma pergunta:
o que aparece na tela quando o dado NAO veio do TSE.

  modo         decide se um boletim de teste pode subir, e se o selo aparece.
  em branco    e o que o pacote leva de fabrica - estrutura sem conteudo.

O que estes testes seguram, em ordem de gravidade:

1. producao nunca aceita fase 'S', escreva-se o que se escrever na config;
2. simulado sempre carimba, mesmo em boletim que venha marcado como oficial;
3. esquecer de escolher o modo cai em producao, nao em simulado;
4. a estrutura em branco nao inventa lider, numero nem nome.
"""

import os
from pathlib import Path

import pytest

from gctse.config import Config
from gctse.simulador import boletim_em_branco
from gctse.tse.parser import analisar


def _cfg(**bruto):
    return Config(bruto=bruto, caminho=Path("config.yaml"))


@pytest.fixture(autouse=True)
def _sem_variavel(monkeypatch):
    monkeypatch.delenv("GCTSE_MODO", raising=False)


# --- modo -----------------------------------------------------------------

def test_sem_modo_vale_producao():
    assert _cfg().modo == "producao"
    assert _cfg().simulado is False


@pytest.mark.parametrize("valor", [None, "", "  ", "PRODUCAO_ERRADO", "teste"])
def test_modo_em_branco_ou_desconhecido_cai_em_producao(valor):
    """O esquecimento tem de cair no lado seguro, nao no permissivo."""
    cfg = _cfg(modo=valor)
    assert cfg.modo == "producao"
    assert cfg.seguranca["bloquear_nao_oficial"] is True


def test_modo_desconhecido_vira_problema_na_validacao():
    erros, _ = _cfg(modo="teste", tse={"base_url": "x", "ciclo": "y"},
                    alvos=[], exporters={}).conferir()
    assert any("nao e um modo conhecido" in e for e in erros)


def test_variavel_de_ambiente_tem_prioridade_sobre_o_arquivo(monkeypatch):
    monkeypatch.setenv("GCTSE_MODO", "simulado")
    assert _cfg(modo="producao").modo == "simulado"


def test_producao_liga_a_trava_mesmo_com_a_config_contra():
    cfg = _cfg(modo="producao", seguranca={"bloquear_nao_oficial": False})
    assert cfg.seguranca["bloquear_nao_oficial"] is True


def test_simulado_desliga_a_trava_mesmo_com_a_config_contra():
    cfg = _cfg(modo="simulado", seguranca={"bloquear_nao_oficial": True})
    assert cfg.seguranca["bloquear_nao_oficial"] is False


def test_simulado_carimba_sempre():
    cfg = _cfg(modo="simulado")
    assert cfg.texto["selo_sempre"] is True
    assert "SIMULADO" in cfg.texto["selo_nao_oficial"]


def test_producao_nao_carimba_boletim_oficial():
    assert _cfg(modo="producao").texto.get("selo_sempre") is not True


def test_cada_modo_traz_os_proprios_codigos_do_tse():
    bruto = {
        "tse": {"base_url": "https://exemplo", "ciclo": "ele2026", "turno": 1},
        "modos": {
            "simulado": {"tse": {"pleito": "111", "eleicao": "111"}},
            "producao": {"tse": {"pleito": "999", "eleicao": "999"}},
        },
    }
    assert _cfg(modo="simulado", **bruto).tse["pleito"] == "111"
    assert _cfg(modo="producao", **bruto).tse["pleito"] == "999"
    # o que nao e do modo continua vindo da base
    assert _cfg(modo="simulado", **bruto).tse["ciclo"] == "ele2026"


def test_modos_vazio_no_yaml_nao_estoura():
    """'modos:' sem nada embaixo vira None no YAML, nao dicionario."""
    cfg = _cfg(modo="simulado", modos=None, tse={"pleito": "1"})
    assert cfg.tse["pleito"] == "1"
    assert cfg.simulado is True


def test_pleito_por_preencher_e_pendencia_nao_erro():
    """O pacote sai de fabrica com '000'. Isso nao pode reprovar o pacote."""
    erros, pendencias = _cfg(
        modo="producao",
        tse={"base_url": "x", "ciclo": "y"},
        modos={"producao": {"tse": {"pleito": "000", "eleicao": "000"}}},
        coleta={"fonte": "tse", "intervalo_segundos": 20},
        alvos=[{"nome": "a", "abrangencia": "br", "cargo": 1, "exporters": ["j"]}],
        exporters={"j": {"tipo": "json"}},
    ).conferir()
    assert erros == []
    assert len(pendencias) == 2
    assert all("000" in p for p in pendencias)


# --- estrutura em branco --------------------------------------------------

def test_em_branco_tem_a_estrutura_e_nenhum_dado():
    ap = analisar(boletim_em_branco("br", 1), abrangencia="br", cargo=1)
    assert len(ap.candidatos) == 5          # os espacos existem, para vincular
    assert ap.secoes_total == 0
    assert ap.votos_validos == 0
    assert ap.pct_secoes == 0.0
    assert all(c.votos == 0 for c in ap.candidatos)


def test_em_branco_nao_inventa_nome_nem_partido():
    ap = analisar(boletim_em_branco("br", 1), abrangencia="br", cargo=1)
    for cand in ap.candidatos:
        assert cand.nome == "—"
        assert cand.partido == "—"
        assert cand.numero == ""


def test_em_branco_nao_se_declara_oficial():
    """Fase indefinida, nao 'O' nem 'S': e o que realmente e, e traz o selo."""
    ap = analisar(boletim_em_branco("br", 1), abrangencia="br", cargo=1)
    assert ap.oficial is False
    assert ap.fase == ""


def test_em_branco_respeita_o_numero_de_vagas():
    ap = analisar(boletim_em_branco("pr", 5, vagas=2), abrangencia="pr", cargo=5)
    assert len(ap.candidatos) == 2
