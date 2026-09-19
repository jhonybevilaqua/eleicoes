"""Telao: o sistema de exibicao, separado do gctse.

O que estes testes protegem:

* as travas continuam valendo aqui. O telao coleta por conta propria, entao
  repetir fase e regressao foi necessario - e e aqui que se prova que nao
  ficaram para tras: um simulado nao pode virar tela cheia com cara de
  resultado, e o numero no ar nao pode andar para tras.
* a selecao sai nos DOIS formatos. A exibicao le o .js (file:// bloqueia fetch
  e XHR); a mesa le o .json. Gravar so um deixa a mesa marcando uma tela
  enquanto o ar mostra outra.
* tela sem dado avisa, nao sai preta - preto parece cabo solto.
* o telao nao depende da configuracao do gctse para nada.
"""

import json
from datetime import datetime, timedelta
from xml.etree import ElementTree as ET

import pytest

from gctse.historico import Ponto
from gctse.malha_br import UFS
from gctse.modelos import Apuracao, Candidato
from telao.coleta import Coletor
from telao.config import Config, carregar
from telao.exibicao import Publicador, escrever_selecao, ler_selecao, ler_telas
from telao.telas import Dados, desenhar

BASE = {
    "tse": {"base_url": "https://exemplo", "ciclo": "ele2026", "pleito": "1", "eleicao": "1"},
    "coleta": {"fonte": "simulador", "simulador_progresso": 63.0, "historico": False},
    "seguranca": {"bloquear_nao_oficial": False},
    "apuracao": {"cargo": 1, "turno": 1},
    "aparencia": {"cores_partido": {"PART-A": "#2f97e8"}},
}


def _cfg(tmp_path, **extra) -> Config:
    from pathlib import Path

    bruto = json.loads(json.dumps(BASE))
    bruto["saida"] = {"destino": str(tmp_path)}
    for chave, valor in extra.items():
        if isinstance(valor, dict) and isinstance(bruto.get(chave), dict):
            bruto[chave].update(valor)
        else:
            bruto[chave] = valor
    return Config(bruto=bruto, caminho=Path("telao.yaml"))


def _ap(pct=63.0, fase="O", candidatos=3, hora=20) -> Apuracao:
    ap = Apuracao(
        cargo_codigo=1, cargo_nome="Presidente",
        abrangencia_tipo="BR", abrangencia_codigo="BR", abrangencia_nome="BRASIL",
        fase=fase, gerado_em=datetime(2026, 10, 4, hora, 41),
        secoes_totalizadas=int(472000 * pct / 100), secoes_total=472000, pct_secoes=pct,
        eleitorado_apto=156_000_000, comparecimento=135_000_000, abstencao=21_000_000,
        votos_validos=71_420_000, votos_brancos=1_047_000, votos_nulos=2_407_000,
        total_apurado=74_874_000,
    )
    ap.candidatos = [
        Candidato(posicao=i + 1, numero=str(10 + i), nome=f"CANDIDATO {i + 1}",
                  partido=f"PART-{chr(65 + i)}", votos=30_000_000 - i * 6_000_000,
                  percentual=47.8 - i * 9.0)
        for i in range(candidatos)
    ]
    return ap


def _estados(quantos=27, pct=63.0) -> dict[str, Apuracao]:
    saida = {}
    for indice, sigla in enumerate(UFS[:quantos]):
        ap = _ap(pct=pct)
        ap.abrangencia_tipo, ap.abrangencia_codigo, ap.abrangencia_nome = "UF", sigla, sigla
        ap.candidatos = [
            Candidato(posicao=1, numero="10", nome="A", partido=f"PART-{chr(65 + indice % 4)}",
                      votos=1000, percentual=51.0),
            Candidato(posicao=2, numero="20", nome="B", partido="PART-Z",
                      votos=900, percentual=49.0),
        ]
        saida[sigla] = ap
    return saida


def _dados(nacional=None, estados=None, serie=None) -> Dados:
    estados = _estados() if estados is None else estados
    totais = (
        (nacional.secoes_totalizadas, nacional.secoes_total) if nacional
        else (sum(a.secoes_totalizadas for a in estados.values()),
              sum(a.secoes_total for a in estados.values()))
    )
    return Dados(nacional=nacional, estados=estados, serie=serie or [], total_secoes=totais)


def _svg(caminho):
    raiz = ET.fromstring(caminho.read_text(encoding="utf-8"))
    assert raiz.get("viewBox") == "0 0 1920 1080"
    return raiz


# --- configuracao propria ---


def test_config_do_telao_nao_precisa_da_config_do_gctse(tmp_path):
    cfg = _cfg(tmp_path)
    assert cfg.validar() == []
    assert cfg.cargo == 1
    assert len(cfg.estados) == 27          # 'todos' resolve as 27 sozinho
    assert cfg.destino == tmp_path
    assert cfg.intervalo_tela >= 2


def test_listar_estados_reduz_a_coleta_sem_furar_o_mapa(tmp_path):
    cfg = _cfg(tmp_path, apuracao={"estados": ["pr", "sc", "rs", "xx"]})
    assert cfg.estados == ["PR", "SC", "RS"]      # 'xx' nao existe, cai fora


def test_cargo_fora_da_tabela_e_recusado(tmp_path):
    problemas = _cfg(tmp_path, apuracao={"cargo": 13}).validar()
    assert any("cargo 13" in p for p in problemas)


def test_tela_com_tipo_desconhecido_e_acusada(tmp_path):
    cfg = _cfg(tmp_path, telas=[{"id": "x", "tipo": "piramide"}])
    assert any("piramide" in p for p in cfg.validar())


def test_sem_telas_na_config_valem_as_seis_padrao(tmp_path):
    assert [t.tipo for t in _cfg(tmp_path).telas] == [
        "lideranca", "estados", "como-votou",
        "apuracao-nacional", "apuracao-estados", "placar",
    ]


# --- as telas ---


@pytest.mark.parametrize("tipo", [
    "lideranca", "estados", "como-votou", "apuracao-nacional", "apuracao-estados", "placar",
])
def test_cada_tela_sai_em_1920x1080(tmp_path, tipo):
    cfg = _cfg(tmp_path)
    tela = next(t for t in cfg.telas if t.tipo == tipo)
    svg = desenhar(cfg, tela, _dados(nacional=_ap()))
    raiz = ET.fromstring(svg)
    assert raiz.get("viewBox") == "0 0 1920 1080"


def test_tela_sem_dado_avisa_em_vez_de_sair_preta(tmp_path):
    cfg = _cfg(tmp_path)
    vazio = Dados(nacional=None, estados={}, serie=[], total_secoes=(0, 0))
    for tela in cfg.telas:
        svg = desenhar(cfg, tela, vazio)
        assert "aguardando boletim" in svg, tela.id


def test_estado_sem_boletim_fica_cinza_e_nao_some_do_mapa(tmp_path):
    cfg = _cfg(tmp_path)
    tela = next(t for t in cfg.telas if t.tipo == "estados")
    svg = desenhar(cfg, tela, _dados(nacional=_ap(), estados=_estados(quantos=20)))
    # as 27 UFs desenhadas, 7 delas aguardando
    assert svg.count("aguardando") == 7
    for sigla in UFS:
        assert f">{sigla}<" in svg


def test_cor_do_estado_vem_do_partido_do_lider(tmp_path):
    cfg = _cfg(tmp_path)          # PART-A esta em cores_partido
    tela = next(t for t in cfg.telas if t.tipo == "lideranca")
    svg = desenhar(cfg, tela, _dados(nacional=_ap()))
    assert "#2f97e8" in svg


def test_selo_de_fase_aparece_no_simulado_e_some_no_oficial(tmp_path):
    cfg = _cfg(tmp_path)
    tela = next(t for t in cfg.telas if t.tipo == "placar")
    assert "NÃO OFICIAL" in desenhar(cfg, tela, _dados(nacional=_ap(fase="S")))
    assert "NÃO OFICIAL" not in desenhar(cfg, tela, _dados(nacional=_ap(fase="O")))


def test_apuracao_nacional_usa_o_boletim_nacional_quando_existe(tmp_path):
    cfg = _cfg(tmp_path)
    tela = next(t for t in cfg.telas if t.tipo == "apuracao-nacional")
    svg = desenhar(cfg, tela, _dados(nacional=_ap()))
    assert "297.360" in svg                     # 63% de 472.000
    assert "soma das praças" not in svg


def test_apuracao_nacional_soma_as_ufs_enquanto_o_nacional_nao_sai(tmp_path):
    """E rotulada como soma, para ninguem ler um parcial como total do TSE."""
    cfg = _cfg(tmp_path)
    tela = next(t for t in cfg.telas if t.tipo == "apuracao-nacional")
    svg = desenhar(cfg, tela, _dados(nacional=None))
    assert "soma das praças" in svg


# --- publicacao e selecao ---


def test_publicar_grava_uma_tela_por_svg(tmp_path):
    cfg = _cfg(tmp_path)
    Publicador(cfg).publicar(_dados(nacional=_ap()))
    for tela in cfg.telas:
        _svg(tmp_path / f"{tela.id}.svg")
    assert (tmp_path / "index.html").exists()


def test_tela_so_e_reescrita_quando_o_desenho_muda(tmp_path):
    cfg = _cfg(tmp_path)
    publicador = Publicador(cfg)
    dados = _dados(nacional=_ap())
    publicador.publicar(dados)
    antes = (tmp_path / "apuracao-nacional.svg").stat().st_mtime_ns

    publicador.publicar(dados)
    assert (tmp_path / "apuracao-nacional.svg").stat().st_mtime_ns == antes

    publicador.publicar(_dados(nacional=_ap(pct=88.0)))
    assert (tmp_path / "apuracao-nacional.svg").stat().st_mtime_ns != antes


def test_tela_com_defeito_nao_derruba_as_outras(tmp_path, monkeypatch):
    cfg = _cfg(tmp_path)

    def explodir(*_a, **_k):
        raise ValueError("defeito proposital")

    monkeypatch.setattr("telao.exibicao.desenhar", lambda c, t, d: (
        explodir() if t.tipo == "placar" else "<svg viewBox='0 0 1920 1080'/>"
    ))
    Publicador(cfg).publicar(_dados(nacional=_ap()))
    assert not (tmp_path / "placar.svg").exists()
    assert (tmp_path / "lideranca.svg").exists()


def test_selecao_sai_nos_dois_formatos(tmp_path):
    cfg = _cfg(tmp_path)
    Publicador(cfg).publicar(_dados(nacional=_ap()))
    escrever_selecao(tmp_path, "como-votou")

    assert ler_selecao(tmp_path) == "como-votou"
    assert json.loads((tmp_path / "no-ar.json").read_text(encoding="utf-8"))["tela"] == "como-votou"
    js = (tmp_path / "no-ar.js").read_text(encoding="utf-8")
    assert js.startswith("telaoNoAr({") and '"tela": "como-votou"' in js


def test_primeira_tela_entra_no_ar_sozinha(tmp_path):
    cfg = _cfg(tmp_path)
    Publicador(cfg).publicar(_dados(nacional=_ap()))
    assert ler_selecao(tmp_path) == "lideranca"
    assert [t["id"] for t in ler_telas(tmp_path)][0] == "lideranca"


def test_pagina_nao_recarrega_nem_usa_fetch(tmp_path):
    pagina = Publicador(_cfg(tmp_path)).pagina()
    assert pagina.count("<img") == 2           # dissolvencia, nao flash branco
    assert "location.reload" not in pagina
    assert "new XMLHttpRequest" not in pagina
    assert "fetch(" not in pagina
    assert 'ler("no-ar.js")' in pagina
    assert "var SELECAO = 1000;" in pagina     # mesa responde em 1s


# --- as travas, que a coleta propria obrigou a repetir ---


def test_boletim_nao_oficial_e_descartado(tmp_path):
    cfg = _cfg(tmp_path, coleta={"fonte": "tse"}, seguranca={"bloquear_nao_oficial": True})
    coletor = Coletor(cfg)
    coletor._obter = lambda praca: _resposta(fase="S")
    assert coletor._buscar("br").startswith("bloqueado")
    assert coletor.nacional is None
    coletor.fechar()


def test_boletim_mais_antigo_nao_substitui_o_que_esta_no_ar(tmp_path):
    cfg = _cfg(tmp_path, coleta={"fonte": "tse"})
    coletor = Coletor(cfg)

    coletor._obter = lambda praca: _resposta(hora="21:00:00", pct="70,00")
    assert coletor._buscar("br").startswith("ok")
    assert coletor.nacional.pct_secoes == 70.0

    coletor._obter = lambda praca: _resposta(hora="20:00:00", pct="40,00")
    assert coletor._buscar("br") == "regressao-descartada"
    assert coletor.nacional.pct_secoes == 70.0      # o ar nao andou para tras
    coletor.fechar()


def test_simulador_passa_pela_trava_de_fase_para_o_ensaio_funcionar(tmp_path):
    cfg = _cfg(tmp_path, seguranca={"bloquear_nao_oficial": True})
    coletor = Coletor(cfg)      # fonte: simulador
    assert coletor._buscar("br").startswith("ok")
    coletor.fechar()


def _resposta(fase="O", hora="20:41:00", pct="63,00"):
    from gctse.tse.cliente import Resposta

    return Resposta(
        url="x",
        status=200,
        dados={
            "carg": "1", "cdabr": "BR", "nmabr": "BRASIL", "tpabr": "BR", "f": fase,
            "dg": "04/10/2026", "hg": hora,
            "s": {"st": "297.360", "s": "472.000", "pst": pct},
            "vv": "71.420.000", "vb": "1.047.000", "vn": "2.407.000", "tvn": "74.874.000",
            "cand": [{"n": "10", "nm": "A", "cc": "PART-A", "vap": "30.000.000", "pvap": "47,80"}],
        },
    )


# --- monitor vertical 1080x1920 ---


def _cfg_vertical(tmp_path, **vertical) -> Config:
    base = {"ativo": True, "destino": str(tmp_path / "v"), "rodizio_segundos": 10}
    base.update(vertical)
    return _cfg(tmp_path, vertical=base)


@pytest.mark.parametrize(
    "tipo", ["urnas", "brancos-nulos", "comparecimento", "placar", "mapa", "estados"]
)
def test_cada_tela_vertical_sai_em_1080x1920(tmp_path, tipo):
    from telao.vertical import desenhar as desenhar_v

    raiz = ET.fromstring(desenhar_v(_cfg_vertical(tmp_path), tipo, _dados(nacional=_ap())))
    assert raiz.get("viewBox") == "0 0 1080 1920"


def test_tela_vertical_sem_dado_avisa(tmp_path):
    from telao.vertical import TIPOS as TIPOS_V, desenhar as desenhar_v

    vazio = Dados(nacional=None, estados={}, serie=[], total_secoes=(0, 0))
    for tipo in TIPOS_V:
        assert "AGUARDANDO BOLETIM" in desenhar_v(_cfg_vertical(tmp_path), tipo, vazio)


def test_numero_comprido_encolhe_para_nao_vazar_a_margem(tmp_path):
    """O eleitorado do Brasil tem 11 caracteres e vaza no corpo cheio.

    Vazar nao gera erro nenhum: o texto simplesmente sai da tela, e so
    aparece no ar.
    """
    from telao.vertical import LARGURA, MARGEM, corpo_que_cabe

    util = LARGURA - 2 * MARGEM
    assert corpo_que_cabe("297.360", 200) == 200                    # curto: corpo cheio
    comprido = corpo_que_cabe("156.454.011", 200)
    assert comprido < 200
    assert len("156.454.011") * comprido * 0.62 <= util + 0.01      # cabe na margem


def test_titulo_comprido_tambem_encolhe(tmp_path):
    from telao.vertical import MolduraV

    partes = MolduraV(_cfg_vertical(tmp_path)).cabecalho("COMO CADA ESTADO VOTOU")
    tamanho = float(partes[1].split('font-size="')[1].split('"')[0])
    assert tamanho < 64

    curto = MolduraV(_cfg_vertical(tmp_path)).cabecalho("URNAS APURADAS")
    assert float(curto[1].split('font-size="')[1].split('"')[0]) == 64


def test_publicador_vertical_grava_o_giro_todo(tmp_path):
    from telao.vertical import PublicadorVertical

    cfg = _cfg_vertical(tmp_path)
    publicador = PublicadorVertical(cfg)
    publicador.publicar(_dados(nacional=_ap()))

    pasta = tmp_path / "v"
    for tipo in publicador.tipos:
        raiz = ET.fromstring((pasta / f"{tipo}.svg").read_text(encoding="utf-8"))
        assert raiz.get("viewBox") == "0 0 1080 1920"
    assert (pasta / "index.html").exists()
    assert (pasta / "telas.js").read_text(encoding="utf-8").startswith("telaoVertical({")


def test_vertical_desligado_nao_escreve_nada(tmp_path):
    from telao.vertical import PublicadorVertical

    cfg = _cfg_vertical(tmp_path, ativo=False)
    assert PublicadorVertical(cfg).publicar(_dados(nacional=_ap())) == []
    assert not (tmp_path / "v").exists()


def test_tela_vertical_desconhecida_cai_fora_sem_derrubar_as_outras(tmp_path):
    from telao.vertical import telas_configuradas

    cfg = _cfg_vertical(tmp_path, telas=["urnas", "piramide", "placar"])
    assert telas_configuradas(cfg) == ["urnas", "placar"]
    assert any("piramide" in p for p in cfg.validar())


def test_pagina_do_monitor_gira_sozinha_sem_mesa(tmp_path):
    """O monitor de cena nao tem ninguem operando: ele gira, e so."""
    from telao.vertical import PublicadorVertical

    pagina = PublicadorVertical(_cfg_vertical(tmp_path, rodizio_segundos=10)).pagina()
    assert "var RODIZIO = 10;" in pagina
    assert pagina.count("<img") == 2          # dissolvencia, nao flash branco
    assert "location.reload" not in pagina
    assert "new XMLHttpRequest" not in pagina
    assert "telaoNoAr" not in pagina          # nao ha selecao para obedecer


def test_rodizio_curto_demais_e_recusado(tmp_path):
    problemas = _cfg_vertical(tmp_path, rodizio_segundos=1).validar()
    assert any("rodizio_segundos" in p for p in problemas)


def test_lista_de_telas_vazia_desliga_o_switcher_e_deixa_so_o_monitor(tmp_path):
    """'telas: []' e uma escolha valida - quem so quer o monitor de cena.

    Antes, a lista vazia caia nas seis telas padrao e o switcher recebia
    arquivos que ninguem pediu.
    """
    from telao.vertical import PublicadorVertical

    cfg = _cfg(
        tmp_path,
        telas=[],
        vertical={"ativo": True, "destino": str(tmp_path / "v"), "rodizio_segundos": 10},
    )
    assert cfg.telas == []
    assert cfg.validar() == []                      # e configuracao valida

    assert Publicador(cfg).publicar(_dados(nacional=_ap())) == []
    assert not (tmp_path / "index.html").exists()

    assert PublicadorVertical(cfg).publicar(_dados(nacional=_ap()))
    assert (tmp_path / "v" / "urnas.svg").exists()


def test_sem_tela_nenhuma_e_sem_monitor_a_config_e_recusada(tmp_path):
    problemas = _cfg(tmp_path, telas=[]).validar()
    assert any("nao produziria nada" in p for p in problemas)
