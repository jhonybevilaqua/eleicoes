"""Mapa do Brasil: as 27 UFs, o SVG e o dedupe.

O que estes testes protegem:

* o mapa tem SEMPRE 27 estados desenhados. Praca sem boletim sai cinza, nunca
  ausente - buraco no mapa parece erro de arte no ar.
* a cor do partido tem de ser a mesma o dia inteiro. Se a atribuicao de cor
  oscilar entre ciclos, o estado troca de cor sozinho no video.
* o conteudo do 'montar' nao pode carregar relogio de captura, senao o dedupe
  do pipeline reescreve o mapa a cada 20 segundos sem nada ter mudado.
* o SVG precisa ser XML bem formado - o GC nao avisa quando nao e.
"""

import json
from xml.etree import ElementTree as ET

from gctse.exporters import criar
from gctse.malha_br import CONTORNO, UFS
from gctse.tse.parser import analisar

TEXTO = {
    "caixa": "alta",
    "formatar_numeros": True,
    "cores_partido": {"PVL": "#2f97e8", "PDR": "#c0392b"},
    "cor_padrao": "#7d93b3",
}


def _boletim(uf, pct="63,00", lider=("Alfa", "PVL", "600.000", "60,00")):
    return {
        "carg": "1", "cdabr": uf.upper(), "nmabr": uf.upper(), "tpabr": "UF", "f": "O",
        "dg": "04/10/2026", "hg": "20:41:00",
        "s": {"st": "630", "s": "1.000", "pst": pct},
        "vv": "1.000.000", "vb": "20.000", "vn": "30.000", "tvn": "1.050.000",
        "ea": "1.400.000", "c": "1.050.000", "a": "350.000",
        "cand": [
            {"n": "11", "nm": lider[0], "cc": lider[1], "vap": lider[2], "pvap": lider[3]},
            {"n": "22", "nm": "Beta", "cc": "PDR", "vap": "400.000", "pvap": "40,00"},
        ],
    }


def _ap(uf, **kwargs):
    return analisar(_boletim(uf, **kwargs), abrangencia=uf, cargo=1)


def _itens(faltando=()):
    return [
        (ordem, uf, None if uf in faltando else _ap(uf.lower()))
        for ordem, uf in enumerate(UFS, start=1)
    ]


def _exporter(tmp_path, **opcoes):
    return criar("m", {"tipo": "mapa", "destino": str(tmp_path), **opcoes}, TEXTO, {})


def test_mapa_tem_sempre_os_27_estados(tmp_path):
    dados = _exporter(tmp_path).montar(_itens(faltando={"RR", "AP"}))
    assert len(dados["estados"]) == 27
    assert dados["pracas_com_dado"] == 25
    assert dados["estados"]["RR"]["visivel"] is False
    assert dados["estados"]["RR"]["cor"] == "#6b7688"     # cinza, nao ausente


def test_svg_desenha_os_27_contornos_e_e_xml_bem_formado(tmp_path):
    arquivos = _exporter(tmp_path, formatos=["svg"]).exportar_lista(_itens(), "mapa")
    raiz = ET.fromstring(arquivos[0].read_text(encoding="utf-8"))
    ids = {
        no.get("id")
        for no in raiz.iter("{http://www.w3.org/2000/svg}path")
        if no.get("id")
    }
    assert ids == {f"uf-{uf.lower()}" for uf in UFS}


def test_cor_vem_do_partido_do_lider(tmp_path):
    itens = _itens()
    itens[0] = (1, "AC", _ap("ac", lider=("Gama", "PDR", "700.000", "70,00")))
    estados = _exporter(tmp_path).montar(itens)["estados"]
    assert estados["AC"]["cor"] == "#c0392b"      # PDR
    assert estados["BA"]["cor"] == "#2f97e8"      # PVL


def test_partido_sem_cor_recebe_a_paleta_de_reserva_e_nao_muda_entre_ciclos(tmp_path):
    exporter = _exporter(tmp_path)
    itens = [
        (i, uf, _ap(uf.lower(), lider=("X", f"SEM{i % 3}", "600.000", "60,00")))
        for i, uf in enumerate(UFS, start=1)
    ]
    primeiro = exporter.montar(itens)["estados"]
    segundo = exporter.montar(itens)["estados"]
    assert {e["cor"] for e in primeiro.values()} != {"#7d93b3"}   # nao ficou monocromatico
    assert all(primeiro[uf]["cor"] == segundo[uf]["cor"] for uf in UFS)


def test_paleta_de_reserva_pode_ser_desligada(tmp_path):
    estados = _exporter(tmp_path, paleta_reserva=False).montar(
        [(1, uf, _ap(uf.lower(), lider=("X", "SEMCOR", "600.000", "60,00"))) for uf in UFS]
    )["estados"]
    assert {e["cor"] for e in estados.values()} == {"#7d93b3"}    # cor_padrao


def test_modo_apuracao_pinta_pelo_percentual(tmp_path):
    itens = [(1, "AC", _ap("ac", pct="10,00")), (2, "BA", _ap("ba", pct="90,00"))]
    estados = _exporter(tmp_path, modo="apuracao").montar(itens)["estados"]
    assert estados["AC"]["cor"] != estados["BA"]["cor"]
    assert estados["RR"]["cor"] == "#6b7688"     # sem dado continua cinza


def test_montar_nao_carrega_relogio_de_captura(tmp_path):
    """Se carregasse, o dedupe do pipeline reescreveria o mapa a cada ciclo."""
    exporter = _exporter(tmp_path)
    itens = _itens()
    primeiro = json.dumps(exporter.montar(itens), sort_keys=True, ensure_ascii=False)
    segundo = json.dumps(exporter.montar(itens), sort_keys=True, ensure_ascii=False)
    assert primeiro == segundo
    assert "hora_atualizacao" not in primeiro
    assert json.loads(primeiro)["hora_geracao"] == "20:41"


def test_composicao_soma_as_pracas_com_boletim(tmp_path):
    dados = _exporter(tmp_path).montar(_itens(faltando={"RR"}))
    comp = dados["composicao"]
    assert comp["pracas"] == 26
    assert comp["brancos"] == 26 * 20_000
    assert comp["nulos"] == 26 * 30_000
    assert comp["pct_brancos"] == round(100.0 * 20_000 / 1_050_000, 2)


def test_apelido_por_extenso_ainda_encontra_o_estado(tmp_path):
    """A praca apelidada de 'PARANA' na config nao pode sumir do mapa."""
    ap = analisar(
        {**_boletim("pr"), "nmabr": "PARANA", "cdabr": "PR"}, abrangencia="pr", cargo=1
    )
    estados = _exporter(tmp_path).montar([(1, "PARANA", ap)])["estados"]
    assert estados["PR"]["visivel"] is True


def test_alvo_nacional_vai_para_o_bloco_nacional_sem_pintar_estado(tmp_path):
    nacional = analisar(
        {**_boletim("br"), "tpabr": "BR", "cdabr": "BR", "nmabr": "BRASIL"},
        abrangencia="br", cargo=1,
    )
    dados = _exporter(tmp_path).montar([(1, "BR", nacional), (2, "PR", _ap("pr"))])
    assert dados["nacional"]["abrangencia"] == "BRASIL"
    assert dados["pracas_com_dado"] == 1     # so o PR pinta estado


def test_exporter_de_mapa_recusa_alvo_isolado(tmp_path):
    import pytest

    with pytest.raises(NotImplementedError):
        _exporter(tmp_path).exportar(_ap("pr"), "presidente-pr")


def test_tela_sai_junto_e_aponta_para_o_svg_do_mesmo_grupo(tmp_path):
    exporter = _exporter(tmp_path, formatos=["svg", "tela"], tela_intervalo_segundos=7)
    escritos = exporter.exportar_lista(_itens(), "urnas-presidente")
    pagina = next(p for p in escritos if p.suffix == ".html")
    corpo = pagina.read_text(encoding="utf-8")

    assert '"urnas-presidente.svg"' in corpo      # o par certo, nao outro mapa
    assert "7 * 1000" in corpo                    # intervalo configurado
    # duas camadas: a troca e dissolvencia, nunca um reload que pisca branco
    assert corpo.count("<img") == 2
    assert "location.reload" not in corpo
    # falha na leitura nao pode limpar a tela
    assert "onerror" in corpo


def test_sem_tela_na_lista_de_formatos_nenhum_html_e_gravado(tmp_path):
    escritos = _exporter(tmp_path, formatos=["svg"]).exportar_lista(_itens(), "mapa")
    assert [p.suffix for p in escritos] == [".svg"]


def test_malha_cobre_as_27_unidades_da_federacao():
    assert len(CONTORNO) == 27
    assert "DF" in CONTORNO and "PR" in CONTORNO


def test_estado_com_zero_voto_apurado_fica_cinza(tmp_path):
    """Boletim publicado e ninguem com voto ainda: nao ha lider.

    Acontece de verdade nos primeiros minutos da noite. Pintar o primeiro da
    lista daria a cor de um partido que nao ganhou nada naquela praca - uma
    lideranca inventada pelo desenho, no ar, antes de existir um unico voto.
    """
    zerado = {
        **_boletim("ac"),
        "s": {"st": "0", "s": "1.000", "pst": "0,00"},
        "vv": "0", "vb": "0", "vn": "0", "tvn": "0",
        "cand": [
            {"n": "11", "nm": "Alfa", "cc": "PVL", "vap": "0", "pvap": "0,00"},
            {"n": "22", "nm": "Beta", "cc": "PDR", "vap": "0", "pvap": "0,00"},
        ],
    }
    itens = _itens()
    itens[0] = (1, "AC", analisar(zerado, abrangencia="ac", cargo=1))
    estados = _exporter(tmp_path).montar(itens)["estados"]
    assert estados["AC"]["lider"] is None
    assert estados["AC"]["cor"] == "#6b7688"
