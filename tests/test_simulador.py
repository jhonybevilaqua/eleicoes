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
