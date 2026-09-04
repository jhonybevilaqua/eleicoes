from gctse.simulador import Simulador
from gctse.tse.parser import analisar


def test_simulador_gera_boletim_analisavel():
    boletim = Simulador(duracao_segundos=1).gerar("br", 1)
    ap = analisar(boletim, abrangencia="br", cargo=1)
    assert ap.fase == "S"          # nunca oficial
    assert ap.oficial is False
    assert len(ap.candidatos) >= 3
    assert ap.candidatos[0].votos >= ap.candidatos[1].votos


def test_progresso_avanca_com_o_tempo():
    simulador = Simulador(duracao_segundos=10)
    inicial = simulador.progresso()
    simulador.inicio -= 5
    assert simulador.progresso() > inicial


def test_progresso_fixo_trava_a_apuracao():
    simulador = Simulador(duracao_segundos=900, progresso_fixo=63)
    assert simulador.progresso() == 63.0
    simulador.inicio -= 500
    assert simulador.progresso() == 63.0   # nao avanca com o tempo


def test_progresso_fixo_alimenta_o_boletim():
    boletim = Simulador(progresso_fixo=63).gerar("br", 1)
    ap = analisar(boletim, abrangencia="br", cargo=1)
    assert ap.pct_secoes == 63.0
    assert ap.candidatos[0].votos > 0          # placar cheio, nao zerado
    assert sum(c.votos for c in ap.candidatos) > 0


def test_progresso_fixo_limitado_a_faixa_valida():
    assert Simulador(progresso_fixo=250).progresso() == 100.0
    assert Simulador(progresso_fixo=-5).progresso() == 0.0
