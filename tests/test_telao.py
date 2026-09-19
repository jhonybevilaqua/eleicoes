"""Telao: quadros de tela cheia, selecao e a tela de exibicao.

O que estes testes protegem:

* a selecao sai nos DOIS formatos. A tela de exibicao e aberta de file:// e
  so consegue ler o .js; a mesa le o .json. Gravar so um deixa a mesa
  marcando um quadro enquanto o ar mostra outro.
* quadro sem boletim nao pode sair preto. Preto no ar parece cabo solto e
  manda o operador procurar defeito no lugar errado.
* serie curta nao vira previsao. No inicio da noite o TSE publica em rajada,
  e uma regressao sobre poucos segundos devolve ritmo e horario sem sentido.
* nada de 'reload' na tela: recarregar a pagina pisca branco por um quadro.
"""

import json
from datetime import datetime, timedelta
from xml.etree import ElementTree as ET

import pytest

from gctse.historico import Ponto
from gctse.mesa import escrever_no_ar, ler_no_ar, ler_quadros
from gctse.modelos import Apuracao, Candidato
from gctse.telao import Quadro, Telao, ler_quadros as ler_config, problemas

TEXTO = {"caixa": "alta", "formatar_numeros": True, "cores_partido": {"PVL": "#2f97e8"}}


def _ap(pct=63.0, candidatos=2, fase="O") -> Apuracao:
    ap = Apuracao(
        cargo_codigo=1, cargo_nome="Presidente",
        abrangencia_tipo="BR", abrangencia_codigo="BR", abrangencia_nome="BRASIL",
        fase=fase, gerado_em=datetime(2026, 10, 4, 20, 41),
        secoes_totalizadas=int(472000 * pct / 100), secoes_total=472000, pct_secoes=pct,
        eleitorado_apto=156_000_000, comparecimento=135_000_000, abstencao=21_000_000,
        votos_validos=71_420_000, votos_brancos=1_047_000, votos_nulos=2_407_000,
        total_apurado=74_874_000,
    )
    siglas = ["PVL", "PDR", "PXY", "PQN"]
    ap.candidatos = [
        Candidato(posicao=i + 1, numero=str(10 + i), nome=f"CANDIDATO {i + 1}",
                  partido=siglas[i % len(siglas)], votos=30_000_000 - i * 5_000_000,
                  percentual=47.8 - i * 8.0)
        for i in range(candidatos)
    ]
    return ap


def _config(destino, **extra):
    base = {
        "ativo": True,
        "destino": str(destino),
        "quadros": [
            {"id": "presidente", "tipo": "placar", "alvo": "presidente-br", "titulo": "PRESIDENTE"},
            {"id": "composicao", "tipo": "composicao", "alvo": "presidente-br"},
            {"id": "contador", "tipo": "contador", "alvo": "presidente-br"},
            {"id": "ritmo", "tipo": "curva", "alvo": "presidente-br"},
            {"id": "mapa", "tipo": "mapa", "mapa": "mapa-presidente"},
        ],
    }
    base.update(extra)
    return base


def _pontos(pares):
    base = datetime(2026, 10, 4, 17, 30)
    return [
        Ponto(base + timedelta(minutes=m), p, int(472000 * p / 100), 472000, [("10", 100, 50.0)])
        for m, p in pares
    ]


def _svg_valido(caminho):
    raiz = ET.fromstring(caminho.read_text(encoding="utf-8"))
    assert raiz.get("viewBox") == "0 0 1920 1080"
    return raiz


# --- leitura da configuracao ---


def test_quadro_com_tipo_desconhecido_e_descartado_sem_derrubar_os_outros():
    quadros = ler_config({"quadros": [
        {"id": "bom", "tipo": "placar", "alvo": "a"},
        {"id": "ruim", "tipo": "piramide", "alvo": "a"},
    ]})
    assert [q.id for q in quadros] == ["bom"]


def test_id_repetido_fica_so_com_o_primeiro():
    quadros = ler_config({"quadros": [
        {"id": "x", "tipo": "placar", "alvo": "a", "titulo": "primeiro"},
        {"id": "x", "tipo": "contador", "alvo": "a", "titulo": "segundo"},
    ]})
    assert [q.titulo for q in quadros] == ["primeiro"]


def test_validacao_aponta_quadro_apontando_para_o_nada():
    achados = problemas(
        {"quadros": [
            {"id": "a", "tipo": "placar", "alvo": "nao-existe"},
            {"id": "b", "tipo": "mapa", "mapa": "nao-existe"},
            {"id": "c", "tipo": "contador"},
        ]},
        nomes_alvo={"presidente-br"},
        nomes_mapa={"mapa-presidente"},
    )
    assert len(achados) == 3
    assert any("nao-existe" in a and "alvo" in a for a in achados)
    assert any("sem 'alvo:'" in a for a in achados)


# --- publicacao ---


def test_cada_quadro_vira_um_svg_de_1920x1080(tmp_path):
    telao = Telao(_config(tmp_path), TEXTO)
    telao.publicar({"presidente-br": _ap()}, {"mapa-presidente": "<svg/>"},
                   {"presidente-br": _pontos([(0, 0), (30, 40), (60, 70)])})

    for nome in ("presidente", "composicao", "contador", "ritmo"):
        _svg_valido(tmp_path / f"{nome}.svg")
    assert (tmp_path / "mapa.svg").read_text(encoding="utf-8") == "<svg/>"


def test_quadro_sem_boletim_avisa_em_vez_de_sair_preto(tmp_path):
    telao = Telao(_config(tmp_path), TEXTO)
    telao.publicar({}, {}, {})
    corpo = (tmp_path / "presidente.svg").read_text(encoding="utf-8")
    assert "aguardando boletim" in corpo
    _svg_valido(tmp_path / "presidente.svg")


def test_serie_curta_nao_vira_previsao(tmp_path):
    """No inicio da noite o TSE publica em rajada; regressao sobre segundos
    devolveria '699 p.p./min' e um horario que o proprio relogio desmente."""
    telao = Telao(_config(tmp_path), TEXTO)
    base = datetime(2026, 10, 4, 17, 30)
    rajada = [
        Ponto(base + timedelta(seconds=s), p, 100, 472000, [])
        for s, p in ((0, 1.0), (4, 6.0), (9, 14.0))
    ]
    telao.publicar({"presidente-br": _ap()}, {}, {"presidente-br": rajada})
    assert "reunindo boletins" in (tmp_path / "ritmo.svg").read_text(encoding="utf-8")


def test_serie_longa_desenha_a_curva_e_a_previsao(tmp_path):
    telao = Telao(_config(tmp_path), TEXTO)
    serie = _pontos([(m, min(100.0, m * 1.2)) for m in range(0, 61, 6)])
    telao.publicar({"presidente-br": _ap()}, {}, {"presidente-br": serie})
    corpo = (tmp_path / "ritmo.svg").read_text(encoding="utf-8")
    assert "polyline" in corpo
    assert "PREVISÃO" in corpo


def test_quadro_so_e_reescrito_quando_muda(tmp_path):
    telao = Telao(_config(tmp_path), TEXTO)
    ap = _ap()
    telao.publicar({"presidente-br": ap}, {}, {})
    antes = (tmp_path / "contador.svg").stat().st_mtime_ns

    telao.publicar({"presidente-br": ap}, {}, {})
    assert (tmp_path / "contador.svg").stat().st_mtime_ns == antes

    telao.publicar({"presidente-br": _ap(pct=88.0)}, {}, {})
    assert (tmp_path / "contador.svg").stat().st_mtime_ns != antes


def test_quadro_com_defeito_nao_derruba_os_outros(tmp_path, monkeypatch):
    telao = Telao(_config(tmp_path), TEXTO)

    def explodir(*_a, **_k):
        raise ValueError("defeito proposital")

    monkeypatch.setattr("gctse.telao.desenhar_contador", explodir)
    telao.publicar({"presidente-br": _ap()}, {}, {})

    assert not (tmp_path / "contador.svg").exists()
    assert (tmp_path / "presidente.svg").exists()      # os outros seguiram


def test_telao_desligado_nao_escreve_nada(tmp_path):
    Telao(_config(tmp_path, ativo=False), TEXTO).publicar({"presidente-br": _ap()}, {}, {})
    assert not list(tmp_path.iterdir())


# --- selecao ---


def test_selecao_sai_nos_dois_formatos(tmp_path):
    """A tela le o .js (file:// bloqueia fetch e XHR); a mesa le o .json."""
    telao = Telao(_config(tmp_path), TEXTO)
    telao.publicar({"presidente-br": _ap()}, {}, {})
    telao.selecionar("composicao")

    assert json.loads((tmp_path / "no-ar.json").read_text(encoding="utf-8"))["quadro"] == "composicao"
    js = (tmp_path / "no-ar.js").read_text(encoding="utf-8")
    assert js.startswith("gctseNoAr({")
    assert '"quadro": "composicao"' in js


def test_mesa_e_telao_gravam_a_mesma_coisa(tmp_path):
    telao = Telao(_config(tmp_path), TEXTO)
    telao.publicar({"presidente-br": _ap()}, {}, {})

    escrever_no_ar(tmp_path, "ritmo")
    assert ler_no_ar(tmp_path) == "ritmo"
    assert telao.no_ar() == "ritmo"
    assert '"quadro": "ritmo"' in (tmp_path / "no-ar.js").read_text(encoding="utf-8")


def test_primeiro_quadro_entra_no_ar_sozinho(tmp_path):
    telao = Telao(_config(tmp_path), TEXTO)
    telao.publicar({"presidente-br": _ap()}, {}, {})
    assert telao.no_ar() == "presidente"


def test_lista_de_quadros_sai_para_a_mesa(tmp_path):
    telao = Telao(_config(tmp_path), TEXTO)
    telao.publicar({"presidente-br": _ap()}, {}, {})
    quadros = ler_quadros(tmp_path)
    assert [q["id"] for q in quadros] == ["presidente", "composicao", "contador", "ritmo", "mapa"]
    assert (tmp_path / "quadros.js").read_text(encoding="utf-8").startswith("gctseQuadros({")


def test_mesa_em_pasta_vazia_nao_quebra(tmp_path):
    assert ler_quadros(tmp_path) == []
    assert ler_no_ar(tmp_path) == ""


# --- tela de exibicao ---


def test_tela_nao_recarrega_a_pagina_e_usa_duas_camadas(tmp_path):
    pagina = Telao(_config(tmp_path), TEXTO).pagina()
    assert pagina.count("<img") == 2          # dissolvencia, nao flash branco
    assert "location.reload" not in pagina
    assert "onerror" in pagina                # falha mantem o quadro no ar


def test_tela_le_a_selecao_por_script_nao_por_fetch(tmp_path):
    """file:// bloqueia fetch e XMLHttpRequest, inclusive para o vizinho."""
    pagina = Telao(_config(tmp_path), TEXTO).pagina()
    # o uso, nao a mencao: o comentario da pagina explica justamente por que
    # esses dois nao servem aqui
    assert "new XMLHttpRequest" not in pagina
    assert "fetch(" not in pagina
    assert 'ler("no-ar.js")' in pagina
    assert "gctseNoAr" in pagina


def test_tela_responde_a_mesa_mais_rapido_do_que_redesenha(tmp_path):
    """Quem clica na mesa espera o quadro entrar agora; o SVG so muda quando
    chega boletim novo. Dois relogios, nao um."""
    pagina = Telao(_config(tmp_path, intervalo_segundos=20), TEXTO).pagina()
    assert "var SELECAO = 1000;" in pagina
    assert "var DESENHO = 20 * 1000;" in pagina


@pytest.mark.parametrize("tecla", ['e.key >= "1"', "ArrowRight", "ArrowLeft", '"r"', '"m"'])
def test_tela_aceita_o_teclado_do_pc_de_exibicao(tmp_path, tecla):
    assert tecla in Telao(_config(tmp_path), TEXTO).pagina()
