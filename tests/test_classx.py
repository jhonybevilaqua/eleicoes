"""Geometria fixa do exporter ClassX LiveBoard.

O que estes testes protegem: a celula amarrada na cena do LiveBoard nao pode
mudar de lugar entre um boletim e outro. Se algum destes testes quebrar, e
sinal de que os vinculos da cena precisam ser refeitos.
"""

import csv

from gctse.exporters import criar
from gctse.exporters.classx import letra_coluna
from gctse.tse.parser import analisar

TEXTO = {"caixa": "alta", "formatar_numeros": True}

BASE = {
    "carg": "3", "cdabr": "PR", "nmabr": "PARANA", "tpabr": "UF", "f": "O",
    "dg": "04/10/2026", "hg": "19:05:00",
    "s": {"st": "5.000", "s": "10.000", "pst": "50,00"},
    "vv": "4.000.000",
}


def _boletim(*candidatos):
    return {**BASE, "cand": list(candidatos)}


TRES = _boletim(
    {"n": "11", "nm": "Candidata Alfa", "cc": "PART-A", "vap": "2.000.000", "pvap": "50,00"},
    {"n": "22", "nm": "Candidato Beta", "cc": "PART-B", "vap": "1.400.000", "pvap": "35,00"},
    {"n": "33", "nm": "Candidato Gama", "cc": "PART-C", "vap": "600.000", "pvap": "15,00"},
)


def _ler(caminho, delimitador=";"):
    with open(caminho, encoding="utf-8", newline="") as fh:
        return list(csv.reader(fh, delimiter=delimitador))


def _exportar(tmp_path, opcoes, boletim=TRES, alvo="governador-pr"):
    exporter = criar("lb", {"tipo": "classx", "destino": str(tmp_path), **opcoes}, TEXTO, {})
    ap = analisar(boletim, abrangencia="pr", cargo=3)
    return exporter, exporter.exportar(ap, alvo)


def test_letra_de_coluna():
    assert letra_coluna(0) == "A"
    assert letra_coluna(1) == "B"
    assert letra_coluna(25) == "Z"
    assert letra_coluna(26) == "AA"
    assert letra_coluna(27) == "AB"


# --- o ponto central: geometria nao muda ------------------------------------

def test_grade_tem_sempre_o_mesmo_numero_de_linhas(tmp_path):
    """Com 3 candidatos ou com 1, o arquivo tem o mesmo tamanho."""
    _, com_tres = _exportar(tmp_path / "a", {"layout": "grade", "slots": 6})
    um_so = _boletim({"n": "11", "nm": "Unica", "cc": "PA", "vap": "10", "pvap": "100,00"})
    _, com_um = _exportar(tmp_path / "b", {"layout": "grade", "slots": 6}, boletim=um_so)

    linhas_tres = _ler(com_tres[0])
    linhas_um = _ler(com_um[0])
    assert len(linhas_tres) == len(linhas_um) == 7   # 1 cabecalho + 6 slots
    assert len(linhas_tres[0]) == len(linhas_um[0])  # mesmas colunas


def test_excedente_de_candidatos_e_cortado(tmp_path):
    muitos = _boletim(*[
        {"n": str(10 + i), "nm": f"Cand {i}", "cc": "PA", "vap": str(100 - i), "pvap": "1,00"}
        for i in range(12)
    ])
    _, arquivos = _exportar(tmp_path, {"layout": "grade", "slots": 4}, boletim=muitos)
    assert len(_ler(arquivos[0])) == 5   # cabecalho + 4 slots


def test_slot_vazio_marca_visivel_zero(tmp_path):
    _, arquivos = _exportar(tmp_path, {"layout": "grade", "slots": 5})
    linhas = _ler(arquivos[0])
    colunas = linhas[0]
    idx_visivel = colunas.index("visivel")
    assert [linha[idx_visivel] for linha in linhas[1:]] == ["1", "1", "1", "0", "0"]


def test_chave_valor_mantem_a_linha_de_cada_campo(tmp_path):
    """A linha de 'cand2_nome' e a mesma independentemente do conteudo."""
    _, com_tres = _exportar(tmp_path / "a", {"layout": "chave_valor", "slots": 6})
    um_so = _boletim({"n": "11", "nm": "Unica", "cc": "PA", "vap": "10", "pvap": "100,00"})
    _, com_um = _exportar(tmp_path / "b", {"layout": "chave_valor", "slots": 6}, boletim=um_so)

    chaves_tres = [linha[0] for linha in _ler(com_tres[0])]
    chaves_um = [linha[0] for linha in _ler(com_um[0])]
    assert chaves_tres == chaves_um


# --- ordenacao ---------------------------------------------------------------

def test_ordem_por_colocacao_segue_os_votos(tmp_path):
    _, arquivos = _exportar(tmp_path, {"layout": "grade", "slots": 3, "ordem": "colocacao"})
    linhas = _ler(arquivos[0])
    idx_nome = linhas[0].index("nome")
    assert [linha[idx_nome] for linha in linhas[1:]] == ["CANDIDATA ALFA", "CANDIDATO BETA", "CANDIDATO GAMA"]


def test_ordem_fixa_prende_o_candidato_na_linha(tmp_path):
    """Linha 1 e sempre o numero 33, mesmo ele estando em ultimo."""
    _, arquivos = _exportar(
        tmp_path, {"layout": "grade", "ordem": "fixa", "candidatos_fixos": ["33", "11", "99"]}
    )
    linhas = _ler(arquivos[0])
    idx_nome, idx_num = linhas[0].index("nome"), linhas[0].index("numero")
    assert [linha[idx_num] for linha in linhas[1:]] == ["33", "11", ""]
    assert [linha[idx_nome] for linha in linhas[1:]] == ["CANDIDATO GAMA", "CANDIDATA ALFA", ""]


def test_ordem_fixa_nao_se_altera_quando_o_placar_vira(tmp_path):
    virada = _boletim(
        {"n": "33", "nm": "Candidato Gama", "cc": "PART-C", "vap": "3.000.000", "pvap": "75,00"},
        {"n": "11", "nm": "Candidata Alfa", "cc": "PART-A", "vap": "1.000.000", "pvap": "25,00"},
    )
    opcoes = {"layout": "grade", "ordem": "fixa", "candidatos_fixos": ["11", "33"]}
    _, antes = _exportar(tmp_path / "a", opcoes)
    _, depois = _exportar(tmp_path / "b", opcoes, boletim=virada)

    idx = _ler(antes[0])[0].index("numero")
    assert [l[idx] for l in _ler(antes[0])[1:]] == [l[idx] for l in _ler(depois[0])[1:]] == ["11", "33"]


# --- formato de exibicao ------------------------------------------------------

def test_nome_partido_em_uma_celula(tmp_path):
    _, arquivos = _exportar(tmp_path, {"layout": "grade", "slots": 3})
    linhas = _ler(arquivos[0])
    idx = linhas[0].index("nome_partido")
    assert linhas[1][idx] == "CANDIDATA ALFA (PART-A)"


def test_formato_de_nome_partido_configuravel(tmp_path):
    _, arquivos = _exportar(
        tmp_path, {"layout": "grade", "slots": 1, "formato_nome_partido": "{nome} - {partido}"}
    )
    linhas = _ler(arquivos[0])
    assert linhas[1][linhas[0].index("nome_partido")] == "CANDIDATA ALFA - PART-A"


def test_delimitador_ponto_e_virgula_e_o_padrao(tmp_path):
    _, arquivos = _exportar(tmp_path, {"layout": "grade", "slots": 2})
    assert ";" in arquivos[0].read_text(encoding="utf-8").splitlines()[0]


# --- mapa de celulas ----------------------------------------------------------

def test_mapa_chave_valor_aponta_a_coluna_b(tmp_path):
    exporter, arquivos = _exportar(
        tmp_path, {"layout": "chave_valor", "slots": 2, "campos_resumo": ["cargo", "apuracao_pct"],
                   "campos_candidato": ["nome", "percentual"]}
    )
    mapa = {item["campo"]: item["celula"] for item in exporter.mapa_celulas()}
    assert mapa["cargo"] == "B2"
    assert mapa["apuracao_pct"] == "B3"
    assert mapa["cand1_nome"] == "B4"
    assert mapa["cand1_percentual"] == "B5"
    assert mapa["cand2_nome"] == "B6"

    linhas = _ler(arquivos[0])
    assert linhas[3] == ["cand1_nome", "CANDIDATA ALFA"]        # B4
    assert linhas[5] == ["cand2_nome", "CANDIDATO BETA"]        # B6


def test_mapa_da_grade_bate_com_o_arquivo(tmp_path):
    exporter, arquivos = _exportar(
        tmp_path, {"layout": "grade", "slots": 3, "campos_candidato": ["nome", "partido", "percentual"]}
    )
    mapa = [i for i in exporter.mapa_celulas() if i["arquivo"] == "principal"]
    celulas = {(i["celula"]) for i in mapa}
    assert {"A2", "B2", "C2", "A4", "C4"} <= celulas

    linhas = _ler(arquivos[0])
    assert linhas[1][0] == "CANDIDATA ALFA"     # A2
    assert linhas[3][2] == "15,00%"             # C4


def test_mapa_do_layout_largo(tmp_path):
    exporter, arquivos = _exportar(
        tmp_path, {"layout": "largo", "slots": 2, "campos_resumo": ["cargo"],
                   "campos_candidato": ["nome", "percentual"]}
    )
    mapa = {i["campo"]: i["celula"] for i in exporter.mapa_celulas()}
    assert mapa["cargo"] == "A2"
    assert mapa["cand1_nome"] == "B2"
    assert mapa["cand2_percentual"] == "E2"

    linhas = _ler(arquivos[0])
    assert linhas[1][0] == "GOVERNADOR"
    assert linhas[1][1] == "CANDIDATA ALFA"


def test_mapa_descreve_o_significado_da_linha(tmp_path):
    exporter, _ = _exportar(tmp_path / "a", {"layout": "grade", "slots": 2})
    assert "colocado" in exporter.mapa_celulas()[0]["origem"]

    fixo, _ = _exportar(tmp_path / "b", {"layout": "grade", "ordem": "fixa", "candidatos_fixos": ["22"]})
    assert "numero 22" in fixo.mapa_celulas()[0]["origem"]


# --- JSON e XML: vinculo por nome, sem celula --------------------------------

def test_json_mantem_a_geometria_dos_slots(tmp_path):
    import json as _json

    _, arquivos = _exportar(tmp_path / "a", {"formato": "json", "slots": 6})
    corpo = _json.loads(arquivos[0].read_text(encoding="utf-8"))
    assert len(corpo["candidatos"]) == 6
    assert [c["posicao"] for c in corpo["candidatos"]] == [1, 2, 3, 4, 5, 6]
    assert corpo["candidatos"][0]["nome"] == "CANDIDATA ALFA"
    assert corpo["candidatos"][5]["visivel"] == "0"
    assert corpo["candidatos"][5]["nome"] == ""


def test_json_entrega_numero_de_verdade_para_o_sort(tmp_path):
    import json as _json

    _, arquivos = _exportar(tmp_path, {"formato": "json", "slots": 3})
    corpo = _json.loads(arquivos[0].read_text(encoding="utf-8"))
    primeiro = corpo["candidatos"][0]
    assert primeiro["votos"] == "2.000.000"          # formatado, para o ar
    assert primeiro["votos_num"] == 2000000          # numero, para ordenar
    assert primeiro["percentual_num"] == 50.0
    assert corpo["resumo"]["apuracao_pct_num"] == 50.0


def test_json_slot_vazio_tem_numerico_nulo(tmp_path):
    import json as _json

    _, arquivos = _exportar(tmp_path, {"formato": "json", "slots": 4})
    corpo = _json.loads(arquivos[0].read_text(encoding="utf-8"))
    assert corpo["candidatos"][3]["votos_num"] is None


def test_json_inclui_mapa_achatado(tmp_path):
    import json as _json

    _, arquivos = _exportar(tmp_path, {"formato": "json", "slots": 2})
    corpo = _json.loads(arquivos[0].read_text(encoding="utf-8"))
    assert corpo["plano"]["cand1_nome"] == "CANDIDATA ALFA"
    assert corpo["plano"]["cand2_nome"] == "CANDIDATO BETA"
    assert corpo["plano"]["cargo"] == "GOVERNADOR"


def test_json_sem_plano_quando_desligado(tmp_path):
    import json as _json

    _, arquivos = _exportar(tmp_path, {"formato": "json", "slots": 2, "incluir_plano": False})
    assert "plano" not in _json.loads(arquivos[0].read_text(encoding="utf-8"))


def test_xml_repete_o_elemento_candidato(tmp_path):
    from xml.etree import ElementTree as ET

    _, arquivos = _exportar(tmp_path, {"formato": "xml", "slots": 5})
    raiz = ET.fromstring(arquivos[0].read_text(encoding="utf-8"))
    candidatos = raiz.findall("candidatos/candidato")
    assert len(candidatos) == 5
    assert candidatos[0].find("nome").text == "CANDIDATA ALFA"
    assert candidatos[0].get("posicao") == "1"
    assert raiz.find("resumo/cargo").text == "GOVERNADOR"


def test_xml_escapa_caractere_especial(tmp_path):
    from xml.etree import ElementTree as ET

    boletim = _boletim({"n": "11", "nm": "Alfa & Beta", "cc": "PA", "vap": "10", "pvap": "100,00"})
    _, arquivos = _exportar(tmp_path, {"formato": "xml", "slots": 1}, boletim=boletim)
    raiz = ET.fromstring(arquivos[0].read_text(encoding="utf-8"))
    assert raiz.find("candidatos/candidato/nome").text == "ALFA & BETA"


def test_extensao_segue_o_formato(tmp_path):
    for formato, extensao in (("csv", ".csv"), ("json", ".json"), ("xml", ".xml")):
        _, arquivos = _exportar(tmp_path / formato, {"formato": formato, "slots": 2})
        assert arquivos[0].suffix == extensao


def test_mapa_json_usa_caminho_de_chave(tmp_path):
    exporter, _ = _exportar(
        tmp_path, {"formato": "json", "slots": 2, "campos_resumo": ["cargo"], "campos_candidato": ["nome"]}
    )
    mapa = {item["campo"]: item["celula"] for item in exporter.mapa_celulas()}
    assert mapa["cargo"] in ("resumo.cargo", "plano.cargo")
    assert mapa["cand1_nome"] == "plano.cand1_nome"
    caminhos = [i["celula"] for i in exporter.mapa_celulas()]
    assert "candidatos[0].nome" in caminhos
    assert "candidatos[1].nome" in caminhos


def test_mapa_xml_usa_xpath(tmp_path):
    exporter, _ = _exportar(
        tmp_path, {"formato": "xml", "slots": 2, "campos_resumo": ["cargo"], "campos_candidato": ["nome"],
                   "incluir_plano": False}
    )
    caminhos = [i["celula"] for i in exporter.mapa_celulas()]
    assert "/dados/resumo/cargo" in caminhos
    assert "/dados/candidatos/candidato[1]/nome" in caminhos
    assert "/dados/candidatos/candidato[2]/nome" in caminhos


def test_ordem_fixa_vale_tambem_em_json(tmp_path):
    import json as _json

    _, arquivos = _exportar(
        tmp_path, {"formato": "json", "ordem": "fixa", "candidatos_fixos": ["33", "11"]}
    )
    corpo = _json.loads(arquivos[0].read_text(encoding="utf-8"))
    assert [c["numero"] for c in corpo["candidatos"]] == ["33", "11"]


def test_campos_numericos_no_csv_saem_sem_formatacao(tmp_path):
    """No CSV o Sort do LiveBoard precisa de uma coluna crua para 'As number'."""
    _, arquivos = _exportar(tmp_path, {"layout": "grade", "slots": 2})
    linhas = _ler(arquivos[0])
    idx = linhas[0].index("votos_num")
    assert linhas[1][idx] == "2000000"
    assert linhas[0].index("percentual_num") >= 0
