import csv
import json
from xml.etree import ElementTree as ET

from gctse.exporters import criar
from gctse.tse.parser import analisar

BOLETIM = {
    "carg": "3", "cdabr": "PR", "nmabr": "PARANA", "tpabr": "UF", "f": "O",
    "dg": "04/10/2026", "hg": "19:05:00",
    "s": {"st": "5.000", "s": "10.000", "pst": "50,00"},
    "vv": "4.000.000",
    "cand": [
        {"n": "11", "nm": "Candidata Alfa", "cc": "PART-A", "vap": "2.400.000", "pvap": "60,00", "e": "n"},
        {"n": "22", "nm": "Candidato Beta", "cc": "PART-B", "vap": "1.600.000", "pvap": "40,00", "e": "n"},
    ],
}

TEXTO = {"caixa": "alta", "formatar_numeros": True, "limites": {"nome": 20}}


def _apuracao():
    return analisar(BOLETIM, abrangencia="pr", cargo=3)


def test_csv_em_linhas(tmp_path):
    exporter = criar("teste", {"tipo": "csv", "destino": str(tmp_path), "nome_arquivo": "{alvo}"}, TEXTO, {})
    escritos = exporter.exportar(_apuracao(), "governador-pr")
    principal = next(p for p in escritos if p.name == "governador-pr.csv")
    linhas = list(csv.DictReader(principal.read_text(encoding="utf-8").splitlines()))
    assert len(linhas) == 2
    assert linhas[0]["nome"] == "CANDIDATA ALFA"
    assert linhas[0]["votos"] == "2.400.000"
    assert linhas[0]["percentual"] == "60,00%"
    assert linhas[0]["ap_apuracao_pct"] == "50,00%"
    assert (tmp_path / "governador-pr-resumo.csv").exists()


def test_csv_largo_tem_uma_linha_com_todos_os_campos(tmp_path):
    exporter = criar(
        "teste", {"tipo": "csv", "layout": "largo", "destino": str(tmp_path), "nome_arquivo": "{alvo}"}, TEXTO, {}
    )
    exporter.exportar(_apuracao(), "gov")
    linhas = list(csv.DictReader((tmp_path / "gov.csv").read_text(encoding="utf-8").splitlines()))
    assert len(linhas) == 1
    assert linhas[0]["cand1_nome"] == "CANDIDATA ALFA"
    assert linhas[0]["cand2_nome"] == "CANDIDATO BETA"


def test_xml_generico(tmp_path):
    exporter = criar("teste", {"tipo": "xml", "destino": str(tmp_path), "nome_arquivo": "{alvo}"}, TEXTO, {})
    (arquivo,) = exporter.exportar(_apuracao(), "gov")
    raiz = ET.fromstring(arquivo.read_text(encoding="utf-8"))
    assert raiz.tag == "apuracao"
    assert raiz.find("resumo/cargo").text == "GOVERNADOR"
    nomes = [c.find("nome").text for c in raiz.findall("candidatos/candidato")]
    assert nomes == ["CANDIDATA ALFA", "CANDIDATO BETA"]


def test_xml_tabular(tmp_path):
    exporter = criar("teste", {"tipo": "xml", "perfil": "tabular", "destino": str(tmp_path)}, TEXTO, {})
    (arquivo,) = exporter.exportar(_apuracao(), "gov")
    raiz = ET.fromstring(arquivo.read_text(encoding="utf-8"))
    assert raiz.tag == "records"
    campos = {f.get("name"): f.text for f in raiz.find("record").findall("field")}
    assert campos["nome"] == "CANDIDATA ALFA"
    assert campos["ap_cargo"] == "GOVERNADOR"


def test_xml_escapa_caractere_especial(tmp_path):
    boletim = {**BOLETIM, "cand": [{"n": "11", "nm": "ALFA & BETA", "vap": "10"}]}
    ap = analisar(boletim, abrangencia="pr", cargo=3)
    exporter = criar("teste", {"tipo": "xml", "destino": str(tmp_path)}, TEXTO, {})
    (arquivo,) = exporter.exportar(ap, "gov")
    assert "&amp;" in arquivo.read_text(encoding="utf-8")
    raiz = ET.fromstring(arquivo.read_text(encoding="utf-8"))
    assert raiz.find("candidatos/candidato/nome").text == "ALFA & BETA"


def test_json_formato_gc(tmp_path):
    exporter = criar("teste", {"tipo": "json", "formato": "gc", "destino": str(tmp_path)}, TEXTO, {})
    (arquivo,) = exporter.exportar(_apuracao(), "gov")
    corpo = json.loads(arquivo.read_text(encoding="utf-8"))
    assert corpo["resumo"]["cargo"] == "GOVERNADOR"
    assert corpo["candidatos"][0]["nome"] == "CANDIDATA ALFA"


def test_casparcg_gera_templatedata(tmp_path):
    exporter = criar(
        "teste",
        {"tipo": "casparcg", "destino": str(tmp_path), "mapa_campos": {"f0": "cand1_nome", "f1": "cand1_percentual"}},
        TEXTO,
        {},
    )
    escritos = exporter.exportar(_apuracao(), "gov")
    xml = next(p for p in escritos if p.suffix == ".xml")
    raiz = ET.fromstring(xml.read_text(encoding="utf-8"))
    assert raiz.tag == "templateData"
    valores = {c.get("id"): c.find("data").get("value") for c in raiz.findall("componentData")}
    assert valores == {"f0": "CANDIDATA ALFA", "f1": "60,00%"}


def test_viz_tab_respeita_ordem_dos_campos(tmp_path):
    exporter = criar(
        "teste", {"tipo": "viz_tab", "destino": str(tmp_path), "campos": ["nome", "partido", "percentual"]}, TEXTO, {}
    )
    (arquivo,) = exporter.exportar(_apuracao(), "gov")
    primeira = arquivo.read_text(encoding="utf-8").splitlines()[0]
    assert primeira.split("\t") == ["CANDIDATA ALFA", "PART-A", "60,00%"]


def test_selo_marca_boletim_nao_oficial(tmp_path):
    ap = analisar({**BOLETIM, "f": "S"}, abrangencia="pr", cargo=3)
    exporter = criar("teste", {"tipo": "json", "formato": "gc", "destino": str(tmp_path)}, {**TEXTO, "selo_nao_oficial": "SIMULADO"}, {})
    (arquivo,) = exporter.exportar(ap, "gov")
    corpo = json.loads(arquivo.read_text(encoding="utf-8"))
    assert corpo["resumo"]["selo"] == "SIMULADO"
    assert corpo["resumo"]["oficial"] == "0"


def test_encoding_legado_nao_quebra_a_gravacao(tmp_path):
    boletim = {**BOLETIM, "cand": [{"n": "11", "nm": "JOÃO CONCEIÇÃO", "vap": "10"}]}
    ap = analisar(boletim, abrangencia="pr", cargo=3)
    exporter = criar("teste", {"tipo": "csv", "destino": str(tmp_path), "encoding": "cp1252"}, TEXTO, {})
    escritos = exporter.exportar(ap, "gov")
    conteudo = escritos[0].read_text(encoding="cp1252")
    assert "JOÃO CONCEIÇÃO" in conteudo


# --- campos de arte: foto e cor --------------------------------------------

def test_foto_montada_pelo_numero_do_candidato(tmp_path):
    texto = {**TEXTO, "padrao_foto": "fotos/{numero}.png"}
    exporter = criar("t", {"tipo": "json", "formato": "gc", "destino": str(tmp_path)}, texto, {})
    (arquivo,) = exporter.exportar(_apuracao(), "gov")
    corpo = json.loads(arquivo.read_text(encoding="utf-8"))
    assert corpo["candidatos"][0]["foto"] == "fotos/11.png"
    assert corpo["candidatos"][1]["foto"] == "fotos/22.png"


def test_foto_vazia_quando_nao_configurada(tmp_path):
    exporter = criar("t", {"tipo": "json", "formato": "gc", "destino": str(tmp_path)}, TEXTO, {})
    (arquivo,) = exporter.exportar(_apuracao(), "gov")
    assert json.loads(arquivo.read_text(encoding="utf-8"))["candidatos"][0]["foto"] == ""


def test_cor_por_partido_com_fallback(tmp_path):
    texto = {**TEXTO, "cores_partido": {"PART-A": "#0a5ec2"}, "cor_padrao": "#8a8a8a"}
    exporter = criar("t", {"tipo": "json", "formato": "gc", "destino": str(tmp_path)}, texto, {})
    (arquivo,) = exporter.exportar(_apuracao(), "gov")
    corpo = json.loads(arquivo.read_text(encoding="utf-8"))
    assert corpo["candidatos"][0]["cor"] == "#0a5ec2"    # mapeado
    assert corpo["candidatos"][1]["cor"] == "#8a8a8a"    # fallback
