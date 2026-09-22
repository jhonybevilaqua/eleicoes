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


# --- o que a revisao pegou ------------------------------------------------

def test_simulado_separa_estado_e_historico():
    """A curva dos tres dias de teste nao pode entrar na serie do dia 4."""
    base = {"coleta": {"arquivo_estado": "dados/estado.json",
                       "arquivo_historico": "dados/estado/historico.jsonl"}}
    producao = _cfg(modo="producao", **base).coleta
    simulado = _cfg(modo="simulado", **base).coleta
    # Comparado como Path: no Windows a separacao vem com barra invertida, e
    # o que importa aqui e o caminho, nao como ele foi escrito.
    assert Path(producao["arquivo_historico"]) == Path("dados/estado/historico.jsonl")
    assert Path(simulado["arquivo_historico"]) == Path("dados/estado/historico-simulado.jsonl")
    assert simulado["arquivo_estado"] != producao["arquivo_estado"]


def test_exporter_nao_consegue_apagar_o_selo_do_modo():
    """Um bloco 'texto:' de tarja nao negocia com o selo de simulado.

    'config.operacao.yaml' ja traz um exporter com bloco proprio (o rodizio,
    que encurta o limite de nome). Herdar dali um selo vazio poria a tarja
    limpa no ar num dia de teste.
    """
    from gctse.exporters import criar

    cfg = _cfg(modo="simulado")
    exporter = criar(
        "r",
        {"tipo": "json", "formato": "gc", "destino": ".",
         "texto": {"selo_nao_oficial": "", "selo_sempre": False, "limites": {"nome": 14}}},
        cfg.texto,
        {},
    )
    assert exporter.cfg_texto["selo_sempre"] is True
    assert "SIMULADO" in exporter.cfg_texto["selo_nao_oficial"]
    assert exporter.cfg_texto["limites"]["nome"] == 14   # o resto do bloco vale


def test_painel_avisa_o_modo_simulado_mesmo_lendo_o_tse():
    """Nos dias de teste a fonte E o TSE e os numeros sao plausiveis.

    Sem a faixa, o painel do coordenador fica identico ao da noite da eleicao
    e quem passa na frente do monitor nao tem como saber que e ensaio.
    """
    from gctse.painel import renderizar

    import tempfile

    with tempfile.TemporaryDirectory() as pasta:
        alvo = Path(pasta) / "painel.html"
        for modo, esperado in (("simulado", True), ("producao", False)):
            renderizar(
                caminho=alvo, fonte="tse", modo=modo, ciclos=1, intervalo=20,
                resultados={}, apuracoes={}, rodizios={},
            )
            corpo = alvo.read_text(encoding="utf-8")
            assert ("MODO SIMULADO" in corpo) is esperado
            assert f"modo <b>{modo.upper()}" in corpo


def test_selo_sem_texto_configurado_nao_estoura():
    """Config com 'selo_sempre' e sem texto de selo nao pode derrubar a subida."""
    from gctse.exporters import criar

    exporter = criar("j", {"tipo": "json", "formato": "gc", "destino": "."},
                     {"selo_sempre": True}, {})
    assert exporter.cfg_texto["selo_nao_oficial"] == "SIMULADO"


def test_bloco_do_modo_nao_derruba_o_desvio_do_comando():
    """'modos.simulado.coleta' nao pode trazer o ensaio de volta ao ar.

    A camada 'forcado' existe exatamente para isso: quem escreveu um desvio
    de coleta por modo na config nao imaginava que ele venceria o desvio que
    o proprio comando acabou de impor.
    """
    cfg = _cfg(
        modo="simulado",
        coleta={"arquivo_historico": "dados/estado/historico.jsonl"},
        modos={"simulado": {"coleta": {"arquivo_historico": "dados/estado/producao.jsonl"}}},
    )
    assert Path(cfg.coleta["arquivo_historico"]) == Path("dados/estado/producao-simulado.jsonl")
    cfg.forcar("coleta", arquivo_historico="ENSAIO/descartavel.jsonl")
    assert cfg.coleta["arquivo_historico"] == "ENSAIO/descartavel.jsonl"


def test_comando_pode_remover_o_arquivo_de_saude():
    """Um ensaio nao sobrescreve o que diz se a coleta de verdade esta viva."""
    cfg = _cfg(coleta={"arquivo_saude": "dados/saude.json"})
    assert "arquivo_saude" in cfg.coleta
    cfg.forcado["coleta_remover"] = ("arquivo_saude",)
    assert "arquivo_saude" not in cfg.coleta


def test_painel_poe_a_fonte_na_frente_do_modo():
    """Ensaio em modo simulado e ensaio, nao 'dados de teste do TSE'."""
    from gctse.painel import renderizar
    import tempfile

    with tempfile.TemporaryDirectory() as pasta:
        alvo = Path(pasta) / "painel.html"
        renderizar(caminho=alvo, fonte="simulador", modo="simulado", ciclos=1,
                   intervalo=20, resultados={}, apuracoes={}, rodizios={})
        corpo = alvo.read_text(encoding="utf-8")
        assert "FONTE DE ENSAIO" in corpo
        assert "MODO SIMULADO —" not in corpo
