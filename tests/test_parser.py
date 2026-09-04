from gctse.tse.parser import analisar

BOLETIM = {
    "ele": "619",
    "cdpleito": "619",
    "tpabr": "BR",
    "cdabr": "BR",
    "nmabr": "BRASIL",
    "carg": "1",
    "f": "O",
    "dg": "04/10/2026",
    "hg": "20:34:41",
    "s": {"st": "470.123", "s": "472.075", "pst": "99,59"},
    "vv": "118.000.000",
    "vb": "1.500.000",
    "vn": "3.200.000",
    "cand": [
        {"n": "20", "nm": "SEGUNDO COLOCADO", "cc": "PART-B", "vap": "50.000.000", "pvap": "42,37", "e": "n"},
        {"n": "10", "nm": "PRIMEIRO COLOCADO", "cc": "PART-A", "vap": "60.000.000", "pvap": "50,85", "e": "s"},
        {"n": "30", "nm": "TERCEIRO", "cc": "PART-C", "vap": "8.000.000", "pvap": "6,78", "e": "n"},
    ],
}


def test_resumo_normalizado():
    ap = analisar(BOLETIM, abrangencia="br", cargo=1)
    assert ap.cargo_nome == "Presidente"
    assert ap.abrangencia_tipo == "BR"
    assert ap.oficial is True
    assert ap.pct_secoes == 99.59
    assert ap.secoes_totalizadas == 470123
    assert ap.votos_validos == 118000000
    assert ap.gerado_em is not None
    assert ap.gerado_em.hour == 20 and ap.gerado_em.minute == 34


def test_candidatos_ordenados_por_votos():
    ap = analisar(BOLETIM, abrangencia="br", cargo=1)
    assert [c.nome for c in ap.candidatos] == ["PRIMEIRO COLOCADO", "SEGUNDO COLOCADO", "TERCEIRO"]
    assert [c.posicao for c in ap.candidatos] == [1, 2, 3]
    assert ap.candidatos[0].eleito is True
    assert ap.diferenca_lider == 10000000


def test_limite_de_candidatos():
    ap = analisar(BOLETIM, abrangencia="br", cargo=1, limite_candidatos=2)
    assert len(ap.candidatos) == 2


def test_fase_simulada_nao_e_oficial():
    ap = analisar({**BOLETIM, "f": "S"}, abrangencia="br", cargo=1)
    assert ap.oficial is False
    assert ap.fase_nome == "Simulado"


def test_percentual_calculado_quando_ausente():
    boletim = {**BOLETIM, "cand": [{"n": "10", "nm": "X", "vap": "59.000.000"}]}
    ap = analisar(boletim, abrangencia="br", cargo=1)
    assert ap.candidatos[0].percentual == 50.0


def test_percentual_de_secoes_calculado_quando_ausente():
    boletim = {**BOLETIM, "s": {"st": "100", "s": "400"}}
    ap = analisar(boletim, abrangencia="br", cargo=1)
    assert ap.pct_secoes == 25.0


def test_mapeamento_customizado_tem_prioridade():
    boletim = {**BOLETIM, "cand": [{"n": "10", "nomeUrna": "NOME NOVO", "vap": "10"}]}
    ap = analisar(boletim, abrangencia="br", cargo=1, mapeamento={"candidato": {"nome": ["nomeUrna"]}})
    assert ap.candidatos[0].nome == "NOME NOVO"


def test_impressao_muda_com_os_votos():
    ap1 = analisar(BOLETIM, abrangencia="br", cargo=1)
    outro = {**BOLETIM, "cand": [dict(BOLETIM["cand"][0], vap="51.000.000"), *BOLETIM["cand"][1:]]}
    ap2 = analisar(outro, abrangencia="br", cargo=1)
    assert ap1.impressao() != ap2.impressao()
    assert ap1.impressao() == analisar(BOLETIM, abrangencia="br", cargo=1).impressao()
