from gctse.util.texto import normalizar, slug, truncar


def test_truncar_nao_quebra_palavra():
    assert truncar("MARIA APARECIDA DE SOUZA", 14) == "MARIA"
    assert truncar("MARIA", 14) == "MARIA"


def test_normalizar_aplica_caixa_e_limite():
    assert normalizar("  josé   da silva  ", caixa="alta", limite=10) == "JOSÉ DA"


def test_normalizar_remove_acentos_quando_pedido():
    assert normalizar("José Antônio", caixa="alta", remover_acentos=True) == "JOSE ANTONIO"


def test_normalizar_remove_quebras_e_tabs():
    assert normalizar("linha1\nlinha2\tfim") == "linha1 linha2 fim"


def test_slug_para_nome_de_arquivo():
    assert slug("BR - Presidente") == "br-presidente"
    assert slug("São Paulo") == "sao-paulo"
