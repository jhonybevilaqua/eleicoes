"""Serie temporal, previsao de fechamento e marcos de virada.

O que estes testes protegem:

* linha corrompida (queda de energia no meio da gravacao) nao pode derrubar a
  leitura do dia inteiro - descarta a linha, mantem o resto.
* previsao so existe quando ha ritmo. Apuracao parada devolvendo um horario
  faria a coordenacao liberar equipe com base em nada.
* o marco de virada e detectado pelo NUMERO do candidato, nao pelo nome:
  grafia de nome muda entre boletins, numero nao.
"""

from datetime import datetime, timedelta

from gctse.historico import Historico, Ponto, projecao, velocidade, viradas
from gctse.modelos import Apuracao, Candidato


def _ap(pct, hora, votos=(600_000, 400_000)):
    ap = Apuracao(
        pct_secoes=pct,
        secoes_totalizadas=int(1_000 * pct / 100),
        secoes_total=1_000,
        votos_validos=sum(votos),
        gerado_em=datetime(2026, 10, 4, 20, hora),
    )
    ap.candidatos = [
        Candidato(numero="10", votos=votos[0], percentual=100 * votos[0] / sum(votos)),
        Candidato(numero="20", votos=votos[1], percentual=100 * votos[1] / sum(votos)),
    ]
    return ap


def _pontos(pares):
    """[(minuto, pct)] -> lista de Ponto."""
    base = datetime(2026, 10, 4, 19, 0)
    return [
        Ponto(instante=base + timedelta(minutes=m), pct=p,
              secoes_totalizadas=int(1_000 * p / 100), secoes_total=1_000,
              candidatos=[("10", 600, 60.0)])
        for m, p in pares
    ]


# --- gravacao e leitura ---


def test_grava_e_le_a_serie(tmp_path):
    hist = Historico(tmp_path / "h.jsonl")
    hist.registrar("presidente-br", _ap(10.0, 20))
    hist.registrar("presidente-br", _ap(35.0, 25))
    hist.registrar("governador-pr", _ap(40.0, 25))

    series = hist.series()
    assert [p.pct for p in series["presidente-br"]] == [10.0, 35.0]
    assert len(series["governador-pr"]) == 1


def test_a_serie_sai_em_ordem_cronologica_mesmo_gravada_fora_de_ordem(tmp_path):
    hist = Historico(tmp_path / "h.jsonl")
    hist.registrar("alvo", _ap(60.0, 40))
    hist.registrar("alvo", _ap(20.0, 20))
    assert [p.pct for p in hist.serie("alvo")] == [20.0, 60.0]


def test_linha_truncada_nao_derruba_o_arquivo(tmp_path):
    caminho = tmp_path / "h.jsonl"
    hist = Historico(caminho)
    hist.registrar("alvo", _ap(10.0, 20))
    with open(caminho, "a", encoding="utf-8") as fh:
        fh.write('{"t": "2026-10-04T20:25:00", "k": "alvo", "pct":\n')   # queda no meio
    hist.registrar("alvo", _ap(30.0, 30))

    assert [p.pct for p in hist.serie("alvo")] == [10.0, 30.0]


def test_historico_desligado_nao_escreve(tmp_path):
    caminho = tmp_path / "h.jsonl"
    assert Historico(caminho, ativo=False).registrar("alvo", _ap(10.0, 20)) is False
    assert not caminho.exists()


def test_arquivo_inexistente_devolve_serie_vazia(tmp_path):
    assert Historico(tmp_path / "nao-existe.jsonl").series() == {}


# --- ritmo e previsao ---


def test_velocidade_em_pontos_por_minuto():
    # 10 pontos percentuais a cada 10 minutos = 1 p.p./min
    assert round(velocidade(_pontos([(0, 0), (10, 10), (20, 20), (30, 30)])), 3) == 1.0


def test_previsao_de_fechamento_no_ritmo_atual():
    resultado = projecao(_pontos([(0, 0), (10, 10), (20, 20), (30, 30)]))
    assert resultado["minutos"] == 70          # faltam 70 pontos a 1 p.p./min
    assert resultado["previsao"] == "20:40"    # 19:30 + 70 min
    assert resultado["totalizada"] is False


def test_apuracao_parada_nao_inventa_horario():
    parado = projecao(_pontos([(0, 42), (10, 42), (20, 42), (30, 42)]))
    assert parado["previsao"] == ""
    assert parado["minutos"] is None


def test_apuracao_encerrada_marca_totalizada():
    fechado = projecao(_pontos([(0, 90), (10, 96), (20, 100)]))
    assert fechado["totalizada"] is True
    assert fechado["minutos"] == 0


def test_serie_vazia_nao_quebra():
    assert projecao([])["previsao"] == ""
    assert velocidade([]) == 0.0


def test_projecao_usa_o_ritmo_recente_nao_a_media_da_noite():
    """A noite comeca rapida e termina arrastada. Uma media do dia inteiro
    projetaria um fechamento cedo demais justamente quando o dado importa."""
    arranque = [(m, min(80, m * 4)) for m in range(0, 21, 2)]      # rapido
    cauda = [(m, 80 + (m - 20) * 0.2) for m in range(22, 60, 2)]   # arrastado
    resultado = projecao(_pontos(arranque + cauda))
    assert 0 < resultado["pontos_por_minuto"] < 1.0                # pegou a cauda


# --- viradas ---


def test_virada_e_detectada_pela_troca_do_primeiro_colocado():
    base = datetime(2026, 10, 4, 20, 0)
    serie = [
        Ponto(base, 20.0, 200, 1000, [("10", 600, 60.0), ("20", 400, 40.0)]),
        Ponto(base + timedelta(minutes=20), 50.0, 500, 1000, [("20", 700, 51.0), ("10", 670, 49.0)]),
        Ponto(base + timedelta(minutes=40), 80.0, 800, 1000, [("20", 900, 52.0), ("10", 830, 48.0)]),
    ]
    trocas = viradas(serie)
    assert len(trocas) == 1
    assert trocas[0]["assumiu"] == "20"
    assert trocas[0]["perdeu"] == "10"
    assert trocas[0]["hora"] == "20:20"


def test_sem_troca_de_lideranca_nao_ha_marco():
    assert viradas(_pontos([(0, 10), (10, 40), (20, 90)])) == []
