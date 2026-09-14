"""Rodizio de pracas: um arquivo, N registros, geometria fixa.

O que estes testes protegem: a lista nao pode encolher quando uma praca ainda
nao publicou boletim - isso deslocaria todo o resto do rodizio no ar.
"""

import json

from gctse.config import Config
from gctse.exporters import criar
from gctse.pipeline import Pipeline
from gctse.tse.cliente import Resposta
from gctse.tse.parser import analisar

TEXTO = {"caixa": "alta", "formatar_numeros": True}


def _boletim(uf, nome_uf, pct, c1, c2=None):
    cands = [{"n": "11", "nm": c1[0], "cc": c1[1], "vap": c1[2], "pvap": c1[3]}]
    if c2:
        cands.append({"n": "22", "nm": c2[0], "cc": c2[1], "vap": c2[2], "pvap": c2[3]})
    return {"carg": "3", "cdabr": uf.upper(), "nmabr": nome_uf, "tpabr": "UF", "f": "O",
            "dg": "04/10/2026", "hg": "20:00:00",
            "s": {"st": "500", "s": "1.000", "pst": pct}, "vv": "1.000.000", "cand": cands}


def _ap(uf, nome_uf, pct="50,00"):
    return analisar(_boletim(uf, nome_uf, pct, ("Alfa", "PVL", "600.000", "60,00"),
                             ("Beta", "PDR", "400.000", "40,00")),
                    abrangencia=uf, cargo=3)


def _exporter(tmp_path, **opcoes):
    return criar("r", {"tipo": "rodizio", "destino": str(tmp_path), **opcoes}, TEXTO, {})


def test_lista_tem_sempre_o_tamanho_configurado(tmp_path):
    exporter = _exporter(tmp_path, formato="json")
    itens = [(1, "PARANÁ", _ap("pr", "PARANA")), (2, "SÃO PAULO", None), (3, "BAHIA", _ap("ba", "BAHIA"))]
    (arquivo,) = exporter.exportar_lista(itens, "governadores")
    corpo = json.loads(arquivo.read_text(encoding="utf-8"))
    assert corpo["total"] == 3 and corpo["com_dado"] == 2
    assert len(corpo["pracas"]) == 3


def test_praca_sem_boletim_fica_invisivel_mas_ocupa_lugar(tmp_path):
    exporter = _exporter(tmp_path, formato="json")
    itens = [(1, "PARANÁ", None), (2, "BAHIA", _ap("ba", "BAHIA"))]
    (arquivo,) = exporter.exportar_lista(itens, "gov")
    pracas = json.loads(arquivo.read_text(encoding="utf-8"))["pracas"]
    assert pracas[0]["visivel"] == "0"
    assert pracas[0]["praca"] == "PARANÁ"        # o nome vem da config
    assert pracas[0]["cand1_nome"] == ""
    assert pracas[1]["visivel"] == "1"
    assert pracas[1]["ordem"] == 2               # a ordem nao escorrega


def test_ordem_da_config_e_a_ordem_do_ar(tmp_path):
    exporter = _exporter(tmp_path, formato="json")
    itens = [(1, "BAHIA", _ap("ba", "BAHIA")), (2, "ACRE", _ap("ac", "ACRE")),
             (3, "PARANÁ", _ap("pr", "PARANA"))]
    (arquivo,) = exporter.exportar_lista(itens, "gov")
    pracas = json.loads(arquivo.read_text(encoding="utf-8"))["pracas"]
    assert [p["praca"] for p in pracas] == ["BAHIA", "ACRE", "PARANA"]


def test_registro_traz_os_dois_primeiros(tmp_path):
    exporter = _exporter(tmp_path, formato="json", barra={"trilho_px": 500})
    (arquivo,) = exporter.exportar_lista([(1, "PARANÁ", _ap("pr", "PARANA"))], "gov")
    p = json.loads(arquivo.read_text(encoding="utf-8"))["pracas"][0]
    assert p["cand1_nome_partido"] == "ALFA (PVL)"
    assert p["cand1_percentual"] == "60,00%"
    assert p["cand1_barra_px"] == 300
    assert p["cand2_nome_partido"] == "BETA (PDR)"
    assert p["apuracao_pct"] == "50,00%"


def test_praca_com_um_candidato_so_nao_quebra(tmp_path):
    um = analisar(_boletim("pr", "PARANA", "50,00", ("Unico", "PVL", "100", "100,00")),
                  abrangencia="pr", cargo=3)
    exporter = _exporter(tmp_path, formato="json")
    (arquivo,) = exporter.exportar_lista([(1, "PARANÁ", um)], "gov")
    p = json.loads(arquivo.read_text(encoding="utf-8"))["pracas"][0]
    assert p["cand1_nome"] == "UNICO" and p["cand2_nome"] == ""


def test_csv_e_xml_saem_com_os_mesmos_registros(tmp_path):
    import csv as _csv
    from xml.etree import ElementTree as ET

    itens = [(1, "PARANÁ", _ap("pr", "PARANA")), (2, "BAHIA", None)]

    (c,) = _exporter(tmp_path / "c", formato="csv").exportar_lista(itens, "gov")
    linhas = list(_csv.DictReader(c.read_text(encoding="utf-8").splitlines(), delimiter=";"))
    assert len(linhas) == 2 and linhas[0]["praca"] == "PARANA" and linhas[1]["visivel"] == "0"

    (x,) = _exporter(tmp_path / "x", formato="xml").exportar_lista(itens, "gov")
    raiz = ET.fromstring(x.read_text(encoding="utf-8"))
    assert len(raiz.findall("praca")) == 2
    assert raiz.find("praca/cand1_nome").text == "ALFA"


# --- integracao com o pipeline ---

BOLETIM_PR = _boletim("pr", "PARANA", "50,00", ("Alfa", "PVL", "600.000", "60,00"),
                      ("Beta", "PDR", "400.000", "40,00"))


class FonteFixa:
    def __init__(self, resposta):
        self.resposta = resposta

    def obter(self, abrangencia, cargo, turno):
        return self.resposta

    def fechar(self):
        pass


def _config(tmp_path):
    return Config(bruto={
        "tse": {"base_url": "https://x", "ciclo": "ele2026", "pleito": "1", "eleicao": "1"},
        "coleta": {"fonte": "tse", "intervalo_segundos": 20,
                   "arquivo_estado": str(tmp_path / "estado.json")},
        "texto": TEXTO,
        "saida": {"destino": str(tmp_path / "saida")},
        "exporters": {
            "rod": {"tipo": "rodizio", "formato": "json", "destino": str(tmp_path / "saida")},
        },
        "alvos": [
            {"nome": "gov-pr", "abrangencia": "pr", "cargo": 3,
             "apelido_abrangencia": "PARANÁ", "exporters": []},
            {"nome": "gov-ba", "abrangencia": "ba", "cargo": 3,
             "apelido_abrangencia": "BAHIA", "exporters": []},
        ],
        "rodizios": {"governadores": {"exporter": "rod", "alvos": ["gov-ba", "gov-pr"]}},
    }, caminho=tmp_path / "c.yaml")


def test_config_com_rodizio_e_valida(tmp_path):
    assert _config(tmp_path).validar() == []


def test_rodizio_inexistente_e_apontado(tmp_path):
    cfg = _config(tmp_path)
    cfg.bruto["rodizios"]["governadores"]["alvos"] = ["gov-xx"]
    assert any("gov-xx" in p for p in cfg.validar())


def test_pipeline_escreve_o_arquivo_do_rodizio(tmp_path):
    pipeline = Pipeline(_config(tmp_path))
    pipeline.fonte = FonteFixa(Resposta(url="x", dados=BOLETIM_PR, status=200))
    pipeline.rodar_uma_vez()
    corpo = json.loads((tmp_path / "saida" / "governadores.json").read_text(encoding="utf-8"))
    assert corpo["total"] == 2
    assert [p["praca"] for p in corpo["pracas"]] == ["BAHIA", "PARANÁ"]   # ordem da config
    pipeline.fechar()


def test_rodizio_nao_reescreve_quando_nada_muda(tmp_path):
    pipeline = Pipeline(_config(tmp_path))
    pipeline.fonte = FonteFixa(Resposta(url="x", dados=BOLETIM_PR, status=200))
    pipeline.rodar_uma_vez()
    arquivo = tmp_path / "saida" / "governadores.json"
    marca = arquivo.stat().st_mtime_ns
    pipeline.rodar_uma_vez()
    assert arquivo.stat().st_mtime_ns == marca
    pipeline.fechar()
