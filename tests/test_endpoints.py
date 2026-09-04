from gctse.tse.endpoints import Endpoints, diretorio_abrangencia, tipo_abrangencia

CFG = {"base_url": "https://resultados.tse.jus.br/oficial", "ciclo": "ele2026", "pleito": "619", "eleicao": "619"}


def test_diretorio_e_tipo_por_abrangencia():
    assert diretorio_abrangencia("br") == "br"
    assert diretorio_abrangencia("pr") == "pr"
    assert diretorio_abrangencia("pr75353") == "pr"
    assert tipo_abrangencia("br") == "BR"
    assert tipo_abrangencia("sp") == "UF"
    assert tipo_abrangencia("sp71072") == "MU"


def test_url_nacional():
    url = Endpoints(CFG).resultado("br", 1)
    assert url == (
        "https://resultados.tse.jus.br/oficial/ele2026/619/dados-simplificados/br/br-c0001-e000619-r.json"
    )


def test_url_municipal_usa_uf_no_diretorio():
    url = Endpoints(CFG).resultado("pr75353", 11)
    assert "/dados-simplificados/pr/pr75353-c0011-e000619-r.json" in url


def test_url_dados_completos():
    assert "/dados/br/" in Endpoints(CFG).resultado("br", 3, completo=True)
