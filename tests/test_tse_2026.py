"""Os codigos reais de 2026, e a defesa contra o bloqueio por 404.

O TSE publicou, para o 1o turno de 04/10/2026:

    pleito 3220
      6257  Eleicao Geral Federal ....... presidente, senador, dep. federal
      6259  Eleicoes Gerais Estaduais ... governador, dep. estadual/distrital
      6261  Eleicao Conselho Distrital

Dois fatos da documentacao do ambiente oficial moldam este arquivo:

1. UM PLEITO, VARIAS ELEICOES. Cada cargo so existe no arquivo da sua. Pedir
   governador com o codigo federal nao devolve dado velho nem erro claro:
   devolve 404.
2. "Multiplos erros 404 podem provocar o bloqueio temporario do endereco IP."
   E 404 e o estado normal durante horas - antes de as urnas fecharem nenhum
   arquivo existe. Insistir de forma ingenua, com 28 pracas a cada 20s, leva
   ao bloqueio justo quando o dado ia comecar a sair.
"""

from pathlib import Path

import pytest

from telao.config import Config
from telao.tse.compasso import Compasso
from telao.tse.endpoints import Endpoints

PLEITO_2026 = {
    "base_url": "https://resultados.tse.jus.br/oficial",
    "ciclo": "ele2026",
    "pleito": "3220",
    "eleicoes": {"federal": "6257", "estadual": "6259"},
}


# --- um pleito, varias eleicoes -------------------------------------------

@pytest.mark.parametrize("cargo, esperado", [
    (1, "6257"),    # presidente
    (5, "6257"),    # senador
    (6, "6257"),    # deputado federal
    (3, "6259"),    # governador
    (7, "6259"),    # deputado estadual
    (8, "6259"),    # deputado distrital
])
def test_cada_cargo_usa_a_eleicao_em_que_e_apurado(cargo, esperado):
    assert Endpoints(PLEITO_2026).eleicao_do_cargo(cargo) == esperado


def test_url_de_2026_sai_no_formato_publicado_pelo_tse():
    endpoints = Endpoints(PLEITO_2026)
    assert endpoints.resultado("br", 1) == (
        "https://resultados.tse.jus.br/oficial/ele2026/3220"
        "/dados-simplificados/br/br-c0001-e006257-r.json"
    )
    # governador do Parana: mesma data, OUTRA eleicao
    assert endpoints.resultado("pr", 3) == (
        "https://resultados.tse.jus.br/oficial/ele2026/3220"
        "/dados-simplificados/pr/pr-c0003-e006259-r.json"
    )


def test_eleicao_solta_continua_valendo_para_quem_so_cobre_um_conjunto():
    """Config antiga, com um codigo so, nao pode parar de funcionar."""
    antiga = {**PLEITO_2026, "eleicoes": None, "eleicao": "6257"}
    assert Endpoints(antiga).eleicao_do_cargo(1) == "6257"
    assert Endpoints(antiga).eleicao_do_cargo(3) == "6257"


def test_cargo_pode_ser_apontado_um_a_um():
    """Escape para o caso de o TSE dividir os cargos de outro jeito."""
    ajustada = {**PLEITO_2026, "eleicao_por_cargo": {5: "6261"}}
    assert Endpoints(ajustada).eleicao_do_cargo(5) == "6261"
    assert Endpoints(ajustada).eleicao_do_cargo(1) == "6257"


def test_validacao_cobra_a_eleicao_DO_CARGO_que_o_telao_mostra():
    """Federal preenchida, estadual em branco, e o telao mostrando governador.

    Antes a validacao olhava um 'tse.eleicao' generico e dava OK - e a tela
    passava a noite pedindo uma URL que sempre devolve 404.
    """
    cfg = Config(
        bruto={
            "tse": {**PLEITO_2026, "eleicoes": {"federal": "6257", "estadual": "000"}},
            "apuracao": {"cargo": 3},        # governador
            "saida": {"destino": "telao"},
        },
        caminho=Path("telao.yaml"),
    )
    erros, pendencias = cfg.conferir()
    assert erros == []
    assert len(pendencias) == 1
    assert "cargo 3" in pendencias[0]

    # com o cargo federal, a mesma config nao tem pendencia nenhuma
    cfg.bruto["apuracao"]["cargo"] = 1
    assert cfg.conferir() == ([], [])


# --- nao apanhar do TSE por insistencia -----------------------------------

def test_o_404_espaca_as_tentativas_em_vez_de_insistir():
    compasso = Compasso(tolerancia=2, base_segundos=30, teto_segundos=300)
    agora = 0.0
    # os primeiros passam batido: a praca pode publicar no proximo ciclo
    assert compasso.registrar_404("br", agora) == 0
    assert compasso.registrar_404("br", agora) == 0
    assert compasso.pode_tentar("br", agora)
    # a partir dai, dobra
    assert compasso.registrar_404("br", agora) == 30
    assert not compasso.pode_tentar("br", agora)
    assert compasso.pode_tentar("br", agora + 31)
    assert compasso.registrar_404("br", agora) == 60
    assert compasso.registrar_404("br", agora) == 120


def test_a_espera_tem_teto():
    """Teto para que a praca que publicar tarde nao fique meia hora invisivel."""
    compasso = Compasso(tolerancia=0, base_segundos=30, teto_segundos=300)
    esperas = [compasso.registrar_404("br", 0.0) for _ in range(12)]
    assert max(esperas) == 300


def test_publicou_volta_ao_ritmo_normal_no_ciclo_seguinte():
    compasso = Compasso(tolerancia=0, base_segundos=30)
    compasso.registrar_404("br", 0.0)
    assert not compasso.pode_tentar("br", 0.0)
    compasso.registrar_ok("br")
    assert compasso.pode_tentar("br", 0.0)
    assert compasso.espera_de("br") == 0


def test_a_espera_e_por_praca_e_nao_atrasa_as_outras():
    """O Acre nao ter publicado nao pode atrasar a leitura de Sao Paulo."""
    compasso = Compasso(tolerancia=0, base_segundos=30)
    compasso.registrar_404("ac", 0.0)
    assert not compasso.pode_tentar("ac", 0.0)
    assert compasso.pode_tentar("sp", 0.0)


# --- as pontas soltas da migracao ----------------------------------------

def test_espera_nao_estoura_em_arquivo_que_nunca_publica():
    """2**n cresce sem limite; tres dias de 404 davam OverflowError.

    Pior do que o erro: ele estourava DEPOIS de contar o 404 e antes de
    regravar o prazo, deixando o prazo velho em pe - a praca voltava ao
    ritmo sem freio, o oposto do que este codigo existe para fazer.
    """
    compasso = Compasso(tolerancia=0, base_segundos=30, teto_segundos=300)
    esperas = [compasso.registrar_404("br", 0.0) for _ in range(2000)]
    assert esperas[0] == 30            # a rampa comeca na base
    assert esperas[-1] == 300          # e termina no teto, sem estourar
    assert max(esperas) == 300
    assert not compasso.pode_tentar("br", 0.0)


def test_config_de_municipios_usa_a_eleicao_estadual():
    """Ficava com a eleicao legada, vazia, e montava '...-e000000-i.json'."""
    assert "e006259" in Endpoints(PLEITO_2026).municipios("pr")


def test_fonte_desconhecida_fala_com_o_tse_e_mantem_o_freio():
    """Fonte escrita errada nao pode virar 'sem freio'.

    O coletor so trata como local o que reconhece; qualquer outra coisa fala
    com o TSE de verdade, e ai o espacamento por 404 tem de valer.
    """
    from telao.coleta import Coletor

    cfg = Config(
        bruto={"tse": PLEITO_2026, "apuracao": {"cargo": 1},
               "saida": {"destino": "telao"},
               "coleta": {"fonte": "tsee", "historico": False}},
        caminho=Path("telao.yaml"),
    )
    coletor = Coletor(cfg)
    try:
        assert coletor.local is None       # nao reconheceu: vai ao TSE
        assert coletor.compasso is not None
    finally:
        coletor.fechar()


# --- o pacote tem de sair pronto -----------------------------------------

def _config_entregue(nome: str):
    import yaml

    caminho = Path(__file__).resolve().parents[1] / "config" / nome
    return yaml.safe_load(caminho.read_text(encoding="utf-8")), caminho


def test_config_entregue_nao_tem_nada_para_preencher(monkeypatch):
    """A config que vai no pacote sobe sem ninguem editar uma linha.

    Pedido direto do operador: 'nao quero eu ter que preencher o arquivo'.
    Os codigos do TSE sao conhecidos, entao deixar '000' esperando edicao era
    trabalho meu empurrado para a noite de quem opera.
    """
    nome = "telao.yaml"
    bruto, caminho = _config_entregue(nome)
    texto = caminho.read_text(encoding="utf-8")
    # '000' so pode aparecer em comentario, nunca como valor
    for linha in texto.splitlines():
        sem_comentario = linha.split("#", 1)[0]
        assert '"000"' not in sem_comentario, f"{nome}: {linha.strip()}"

    for modo in ("simulado", "producao"):
        monkeypatch.setenv("TELAO_MODO", modo)
        cfg = Config(bruto=bruto, caminho=caminho)
        erros, pendencias = cfg.conferir()
        assert erros == [], f"{nome} / {modo}: {erros}"
        assert pendencias == [], f"{nome} / {modo}: {pendencias}"


def test_os_dois_modos_apontam_para_o_mesmo_arquivo_do_tse(monkeypatch):
    """Simulado e producao leem o MESMO caminho - muda a fase, nao a URL.

    E o desenho que faz o teste provar a operacao de verdade: se o simulado
    lesse outro lugar, terca nao diria nada sobre domingo.
    """
    nome = "telao.yaml"
    bruto, caminho = _config_entregue(nome)
    urls = set()
    for modo in ("simulado", "producao"):
        monkeypatch.setenv("TELAO_MODO", modo)
        cfg = Config(bruto=bruto, caminho=caminho)
        urls.add(Endpoints(cfg.tse).resultado("br", 1))
    assert len(urls) == 1, urls
    assert "e006257" in urls.pop()
