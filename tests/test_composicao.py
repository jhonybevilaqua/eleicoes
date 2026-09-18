"""Brancos, nulos e abstencao: percentuais e geometria pronta para o GC.

O que estes testes protegem:

* as DUAS BASES nao podem se misturar. Validos, brancos e nulos sao medidos
  sobre os votos apurados; abstencao, sobre o eleitorado apto. Trocar uma pela
  outra produz um grafico que nao fecha 100% - e ninguem percebe no ar.
* a barra empilhada tem de fechar EXATO no trilho. Um pixel de sobra vira uma
  fresta de fundo entre duas fatias, visivel em tela grande.
* a rosca tem de fechar a circunferencia, pelo mesmo motivo.
"""

import json

from gctse.exporters import criar
from gctse.modelos import Apuracao

TEXTO = {"caixa": "alta", "formatar_numeros": True}


def _ap(**extra) -> Apuracao:
    dados = {
        "eleitorado_apto": 1_000_000,
        "comparecimento": 800_000,
        "abstencao": 200_000,
        "votos_validos": 750_000,
        "votos_brancos": 20_000,
        "votos_nulos": 30_000,
        "total_apurado": 800_000,
        "pct_secoes": 50.0,
        "secoes_totalizadas": 500,
        "secoes_total": 1_000,
    }
    dados.update(extra)
    return Apuracao(**dados)


def _exporter(**opcoes):
    return criar("c", {"tipo": "json", **opcoes}, TEXTO, {})


# --- percentuais do modelo ---


def test_validos_brancos_e_nulos_fecham_cem_por_cento():
    ap = _ap()
    assert ap.pct_validos == 93.75
    assert ap.pct_brancos == 2.5
    assert ap.pct_nulos == 3.75
    assert ap.pct_validos + ap.pct_brancos + ap.pct_nulos == 100.0


def test_abstencao_sai_sobre_o_eleitorado_nao_sobre_os_votos():
    # 200.000 de 1.000.000 aptos = 20%. Sobre os votos apurados daria 25%, que
    # e a conta errada e a que um template desatento faria.
    assert _ap().pct_abstencao == 20.0


def test_brancos_mais_nulos_e_uma_conta_so_nao_a_soma_de_arredondados():
    ap = _ap(votos_brancos=1_047, votos_nulos=2_407, votos_validos=71_420, total_apurado=74_874)
    assert ap.pct_brancos_nulos == round(100.0 * 3_454 / 74_874, 2)


def test_sem_voto_apurado_nao_divide_por_zero():
    vazio = Apuracao()
    assert (vazio.pct_validos, vazio.pct_brancos, vazio.pct_abstencao) == (0.0, 0.0, 0.0)


def test_total_apurado_ausente_cai_na_soma_das_fatias():
    ap = _ap(total_apurado=0)
    assert ap.votos_apurados == 800_000
    assert ap.pct_validos == 93.75


# --- ritmo e reversibilidade ---


def test_votos_restantes_e_regra_de_tres_sobre_o_que_ja_saiu():
    # 800.000 votos com 50% apurado => faltam aproximadamente outros 800.000
    assert _ap().votos_restantes == 800_000


def test_apuracao_encerrada_nao_tem_voto_restante():
    assert _ap(pct_secoes=100.0).votos_restantes == 0


def test_reversivel_compara_a_diferenca_com_o_que_falta():
    from gctse.modelos import Candidato

    ap = _ap()
    ap.candidatos = [
        Candidato(numero="10", votos=400_000, percentual=53.3),
        Candidato(numero="20", votos=350_000, percentual=46.7),
    ]
    assert ap.diferenca_lider == 50_000
    assert ap.reversivel is True          # 50.000 cabem nos 800.000 que faltam

    # com 95% apurado sobram ~42.000 votos: a mesma vantagem deixa de caber
    quase_fechado = _ap(pct_secoes=95.0, secoes_totalizadas=950)
    quase_fechado.candidatos = ap.candidatos
    assert quase_fechado.votos_restantes < 50_000
    assert quase_fechado.reversivel is False
    assert quase_fechado.secoes_restantes == 50


# --- geometria entregue ao GC ---


def test_barra_empilhada_fecha_exato_no_trilho():
    campos = _exporter(composicao={"trilho_px": 900}).campos_resumo(_ap())
    larguras = [int(campos[f"comp_{f}_px"]) for f in ("validos", "brancos", "nulos")]
    assert sum(larguras) == 900
    # e cada fatia comeca onde a anterior terminou, sem fresta
    assert int(campos["comp_validos_x"]) == 0
    assert int(campos["comp_brancos_x"]) == larguras[0]
    assert int(campos["comp_nulos_x"]) == larguras[0] + larguras[1]


def test_rosca_fecha_a_circunferencia():
    campos = _exporter(composicao={"rosca_raio": 100}).campos_resumo(_ap())
    circunferencia = float(campos["rosca_circunferencia"])
    arcos = sum(float(campos[f"rosca_{f}_arco"]) for f in ("validos", "brancos", "nulos"))
    assert abs(arcos - circunferencia) < 0.05
    # o dash e o par "arco resto", pronto para o atributo do SVG
    arco, resto = campos["rosca_validos_dash"].split()
    assert abs(float(arco) + float(resto) - circunferencia) < 0.05
    assert campos["rosca_validos_offset"] == "-0.00" or campos["rosca_validos_offset"] == "0.00"


def test_base_eleitorado_inclui_abstencao_e_troca_o_denominador():
    campos = _exporter(
        composicao={"trilho_px": 1000, "base": "eleitorado"}
    ).campos_resumo(_ap())
    larguras = [int(campos[f"comp_{f}_px"]) for f in ("validos", "brancos", "nulos", "abstencao")]
    assert sum(larguras) == 1000
    # 200.000 de 1.000.000 aptos
    assert campos["comp_abstencao_pct"] == "20.00"
    assert campos["comp_base"] == "eleitorado"


def test_sem_configuracao_de_composicao_nenhum_campo_de_geometria_aparece():
    campos = _exporter().campos_resumo(_ap())
    assert not [c for c in campos if c.startswith(("comp_", "rosca_"))]
    # mas os percentuais continuam la: eles nao dependem de geometria
    assert campos["pct_brancos"] == "2,50%"


def test_classx_tipa_a_geometria_como_numero_e_o_dash_como_texto(tmp_path):
    exporter = criar(
        "lb",
        {
            "tipo": "classx",
            "formato": "json",
            "destino": str(tmp_path),
            "composicao": {"trilho_px": 600, "rosca_raio": 80},
            "campos_resumo": ["comp_nulos_px", "rosca_nulos_dash", "pct_nulos_num", "comp_base"],
        },
        TEXTO,
        {},
    )
    (arquivo,) = exporter.exportar(_ap(), "presidente-br")
    resumo = json.loads(arquivo.read_text(encoding="utf-8"))["resumo"]
    assert isinstance(resumo["comp_nulos_px"], int)
    assert isinstance(resumo["pct_nulos_num"], float)
    assert isinstance(resumo["rosca_nulos_dash"], str)   # "arco resto", nao um numero
    assert resumo["comp_base"] == "apurados"
