"""Testes das guardas de seguranca do pipeline, com fonte controlada."""

import json

from gctse.config import Config
from gctse.pipeline import Pipeline
from gctse.tse.cliente import Resposta

BOLETIM = {
    "carg": "1", "cdabr": "BR", "nmabr": "BRASIL", "tpabr": "BR", "f": "O",
    "dg": "04/10/2026", "hg": "20:00:00",
    "s": {"st": "1.000", "s": "2.000", "pst": "50,00"},
    "vv": "1.000.000",
    "cand": [{"n": "10", "nm": "ALFA", "cc": "PA", "vap": "600.000", "pvap": "60,00"}],
}


class FonteFixa:
    def __init__(self, resposta):
        self.resposta = resposta
        self.chamadas = 0

    def obter(self, abrangencia, cargo, turno):
        self.chamadas += 1
        return self.resposta

    def fechar(self):
        pass


def _config(tmp_path, **sobrepor):
    bruto = {
        "tse": {"base_url": "https://exemplo", "ciclo": "ele2026", "pleito": "1", "eleicao": "1"},
        "coleta": {
            "fonte": "tse",
            "intervalo_segundos": 20,
            "arquivo_estado": str(tmp_path / "estado.json"),
            "arquivo_saude": str(tmp_path / "saude.json"),
        },
        "seguranca": {},
        "texto": {"caixa": "alta"},
        "saida": {"destino": str(tmp_path / "saida")},
        "exporters": {"j": {"tipo": "json", "formato": "gc", "destino": str(tmp_path / "saida")}},
        "alvos": [{"nome": "presidente-br", "abrangencia": "br", "cargo": 1, "exporters": ["j"]}],
    }
    # 'raiz' mexe no nivel de cima (modo, modos); o resto sao secoes
    bruto.update(sobrepor.pop("raiz", {}))
    for secao, valores in sobrepor.items():
        bruto.setdefault(secao, {}).update(valores)
    return Config(bruto=bruto, caminho=tmp_path / "config.yaml")


def _pipeline(tmp_path, resposta, **sobrepor):
    pipeline = Pipeline(_config(tmp_path, **sobrepor))
    pipeline.fonte = FonteFixa(resposta)
    return pipeline


def test_config_valida(tmp_path):
    assert _config(tmp_path).validar() == []


def test_publica_boletim_oficial(tmp_path):
    pipeline = _pipeline(tmp_path, Resposta(url="x", dados=BOLETIM, status=200))
    resultado = pipeline.rodar_uma_vez()
    assert resultado["presidente-br"].startswith("publicado")
    corpo = json.loads((tmp_path / "saida" / "presidente-br.json").read_text(encoding="utf-8"))
    assert corpo["candidatos"][0]["nome"] == "ALFA"
    pipeline.fechar()


def test_nao_reescreve_quando_nada_muda(tmp_path):
    pipeline = _pipeline(tmp_path, Resposta(url="x", dados=BOLETIM, status=200))
    assert pipeline.rodar_uma_vez()["presidente-br"].startswith("publicado")
    assert pipeline.rodar_uma_vez()["presidente-br"] == "sem-mudanca"
    pipeline.fechar()


def test_bloqueia_fase_nao_oficial(tmp_path):
    pipeline = _pipeline(tmp_path, Resposta(url="x", dados={**BOLETIM, "f": "S"}, status=200))
    assert pipeline.rodar_uma_vez()["presidente-br"].startswith("bloqueado")
    assert not (tmp_path / "saida" / "presidente-br.json").exists()
    pipeline.fechar()


def test_config_nao_derruba_a_trava_de_fase(tmp_path):
    """Quem decide e o modo, nao o arquivo.

    Antes esta linha na config liberava fase 'S'. Nao libera mais: em producao
    nao existe valor em arquivo que faca um simulado do TSE ir ao ar como
    resultado - nem editado a mao no meio da noite.
    """
    pipeline = _pipeline(
        tmp_path, Resposta(url="x", dados={**BOLETIM, "f": "S"}, status=200),
        seguranca={"bloquear_nao_oficial": False},
    )
    assert pipeline.rodar_uma_vez()["presidente-br"].startswith("bloqueado")
    pipeline.fechar()


def test_modo_simulado_aceita_fase_simulada(tmp_path):
    pipeline = _pipeline(
        tmp_path, Resposta(url="x", dados={**BOLETIM, "f": "S"}, status=200),
        raiz={"modo": "simulado"},
    )
    assert pipeline.rodar_uma_vez()["presidente-br"].startswith("publicado")
    pipeline.fechar()


def test_modo_simulado_carimba_ate_boletim_oficial(tmp_path):
    """O selo nos dias de teste e do DIA, nao do campo que veio no arquivo.

    Este foi o buraco real: boletim de teste publicado em fase 'O' saia com a
    tarja limpa, com cara de resultado, no meio de um ensaio.
    """
    pipeline = _pipeline(
        tmp_path, Resposta(url="x", dados=BOLETIM, status=200),
        raiz={"modo": "simulado"},
    )
    assert pipeline.rodar_uma_vez()["presidente-br"].startswith("publicado")
    corpo = json.loads((tmp_path / "saida" / "presidente-br.json").read_text(encoding="utf-8"))
    assert corpo["resumo"]["selo"] == "SIMULADO - TESTE, NAO E RESULTADO"
    pipeline.fechar()


def test_descarta_boletim_mais_antigo(tmp_path):
    pipeline = _pipeline(tmp_path, Resposta(url="x", dados=BOLETIM, status=200))
    pipeline.rodar_uma_vez()
    antigo = {**BOLETIM, "hg": "19:00:00", "cand": [{"n": "10", "nm": "ALFA", "vap": "1"}]}
    pipeline.fonte = FonteFixa(Resposta(url="x", dados=antigo, status=200))
    assert pipeline.rodar_uma_vez()["presidente-br"] == "regressao-descartada"
    pipeline.fechar()


def test_respeita_percentual_minimo(tmp_path):
    pipeline = _pipeline(tmp_path, Resposta(url="x", dados=BOLETIM, status=200),
                         seguranca={"pct_minimo_para_publicar": 80})
    assert pipeline.rodar_uma_vez()["presidente-br"].startswith("aguardando")
    pipeline.fechar()


def test_resposta_304_nao_republica(tmp_path):
    pipeline = _pipeline(tmp_path, Resposta(url="x", dados=None, status=304, inalterado=True))
    assert pipeline.rodar_uma_vez()["presidente-br"] == "sem-mudanca"
    pipeline.fechar()


def test_falha_de_rede_nao_derruba_o_ciclo(tmp_path):
    pipeline = _pipeline(tmp_path, Resposta(url="x", dados=None, erro="timeout"))
    assert pipeline.rodar_uma_vez()["presidente-br"].startswith("falha")
    assert (tmp_path / "saude.json").exists()
    pipeline.fechar()


def test_arquivo_de_saude_registra_situacao(tmp_path):
    pipeline = _pipeline(tmp_path, Resposta(url="x", dados=BOLETIM, status=200))
    pipeline.rodar_uma_vez()
    saude = json.loads((tmp_path / "saude.json").read_text(encoding="utf-8"))
    assert saude["ciclos"] == 1
    assert saude["alvos"]["presidente-br"].startswith("publicado")
    pipeline.fechar()
