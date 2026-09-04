from gctse.util.numeros import formatar_int, formatar_pct, para_float, para_int


def test_inteiro_com_separador_de_milhar_do_tse():
    assert para_int("12.345.678") == 12345678
    assert para_int("0") == 0
    assert para_int("") == 0
    assert para_int(None) == 0
    assert para_int(4210) == 4210


def test_percentual_com_virgula_decimal():
    assert para_float("49,10") == 49.1
    assert para_float("1.234,56") == 1234.56
    assert para_float("100") == 100.0
    assert para_float("") == 0.0
    assert para_float("--") == 0.0


def test_formatacao_para_exibicao():
    assert formatar_int(12345678) == "12.345.678"
    assert formatar_pct(49.1) == "49,10%"
    assert formatar_pct(7.5, casas=1, sufixo="") == "7,5"
