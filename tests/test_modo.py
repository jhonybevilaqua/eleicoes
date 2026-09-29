"""Modo Simulado / Producao, e a estrutura em branco.

Os dois assuntos respondem a mesma pergunta: o que aparece na tela quando o
dado NAO veio do TSE.

  modo         decide se um boletim de teste pode subir, e se o selo aparece.
  em branco    e o que o pacote leva de fabrica - estrutura sem conteudo.

O que estes testes seguram, em ordem de gravidade:

1. producao nunca aceita fase 'S', escreva-se o que se escrever na config;
2. simulado sempre carimba, mesmo em boletim que venha marcado como oficial;
3. esquecer de escolher o modo cai em producao, nao em simulado;
4. a estrutura em branco nao inventa lider, numero nem nome;
5. erro de configuracao para o atalho, em vez de reinicia-lo para sempre.
"""

import os
from pathlib import Path

import pytest

from telao.config import Config
from telao.simulador import boletim_em_branco
from telao.tse.parser import analisar

BASE = {
    "tse": {
        "base_url": "https://resultados.tse.jus.br/oficial",
        "ciclo": "ele2026",
        "pleito": "3220",
        "eleicoes": {"federal": "6257", "estadual": "6259"},
        "turno": 1,
    },
    "apuracao": {"cargo": 1},
    "saida": {"destino": "telao"},
}


def _cfg(**extra):
    bruto = {k: (dict(v) if isinstance(v, dict) else v) for k, v in BASE.items()}
    bruto.update(extra)
    return Config(bruto=bruto, caminho=Path("telao.yaml"))


@pytest.fixture(autouse=True)
def _sem_variavel(monkeypatch):
    monkeypatch.delenv("TELAO_MODO", raising=False)


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
    erros, _ = _cfg(modo="teste").conferir()
    assert any("nao e um modo conhecido" in e for e in erros)


def test_variavel_de_ambiente_tem_prioridade_sobre_o_arquivo(monkeypatch):
    monkeypatch.setenv("TELAO_MODO", "simulado")
    assert _cfg(modo="producao").modo == "simulado"


def test_producao_liga_a_trava_mesmo_com_a_config_contra():
    cfg = _cfg(modo="producao", seguranca={"bloquear_nao_oficial": False})
    assert cfg.seguranca["bloquear_nao_oficial"] is True


def test_simulado_desliga_a_trava_mesmo_com_a_config_contra():
    cfg = _cfg(modo="simulado", seguranca={"bloquear_nao_oficial": True})
    assert cfg.seguranca["bloquear_nao_oficial"] is False


def test_simulado_carimba_sempre():
    cfg = _cfg(modo="simulado")
    assert "SIMULADO" in cfg.selo_do_modo
    assert "SIMULADO" in cfg.aparencia["selo_nao_oficial"]


def test_simulado_nao_deixa_a_aparencia_apagar_o_selo():
    """Um 'selo_nao_oficial' vazio na aparencia nao vale mais que o modo."""
    cfg = _cfg(modo="simulado", aparencia={"selo_nao_oficial": ""})
    assert cfg.aparencia["selo_nao_oficial"]


def test_producao_nao_impoe_selo():
    assert _cfg(modo="producao").selo_do_modo == ""


def test_modo_pode_sobrepor_os_codigos_do_tse():
    """Se um ano o TSE separar o teste em pleito proprio."""
    cfg = _cfg(modo="simulado", modos={"simulado": {"tse": {"pleito": "111"}}})
    assert cfg.tse["pleito"] == "111"
    assert cfg.tse["ciclo"] == "ele2026"      # o resto vem da base


def test_modos_vazio_no_yaml_nao_estoura():
    """'modos:' sem nada embaixo vira None no YAML, nao dicionario."""
    cfg = _cfg(modo="simulado", modos=None)
    assert cfg.tse["pleito"] == "3220"
    assert cfg.simulado is True


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


# --- o atalho nao pode reiniciar para sempre ------------------------------

def test_config_por_preencher_sai_com_codigo_proprio(tmp_path):
    """Codigo 2 e o que faz o .bat PARAR em vez de reiniciar a cada 10s.

    Veio de um print da operacao: a janela repetindo a mesma mensagem de
    pleito em '000' de dez em dez segundos. Reiniciar cobre queda de rede;
    nao cobre configuracao, que nao se conserta sozinha.
    """
    import subprocess
    import sys
    import textwrap

    config = tmp_path / "telao.yaml"
    config.write_text(textwrap.dedent("""
        modo: producao
        tse: {base_url: "https://exemplo", ciclo: ele2026, pleito: "000", turno: 1}
        apuracao: {cargo: 1}
        saida: {destino: "telao"}
    """), encoding="utf-8")

    fim = subprocess.run(
        [sys.executable, "-m", "telao", "-c", str(config), "rodar"],
        capture_output=True, text=True, cwd=tmp_path,
        env={**os.environ, "PYTHONPATH": str(Path(__file__).resolve().parents[1] / "src")},
    )
    assert fim.returncode == 2, fim.stdout + fim.stderr
    assert "NAO DA PARA SUBIR" in fim.stdout
    assert "descobrir" in fim.stdout


def test_atalhos_param_no_codigo_de_configuracao():
    """Os .bat tem de tratar o codigo 2 - senao a correcao nao chega."""
    raiz = Path(__file__).resolve().parents[1] / "empacotamento"
    for nome in ("TELAO-SIMULADO.bat", "TELAO-PRODUCAO.bat"):
        texto = (raiz / nome).read_text(encoding="utf-8")
        assert "EQU 2 goto configuracao" in texto, nome
        assert ":configuracao" in texto, nome
        # Espera longa, nao os 10s do reinicio comum: a mensagem tem de ficar
        # legivel na tela.
        assert "timeout /t 60" in texto, nome
        # E nao pode PARAR: o atalho pode ter subido minimizado, e ai ficaria
        # travado mesmo depois de alguem corrigir o arquivo.
        assert "pause" not in texto.split(":configuracao")[1], nome
