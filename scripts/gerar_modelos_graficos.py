"""Monta graficos/modelos.html a partir do template e da malha do Brasil.

O demonstrativo NAO e desenhado a mao duas vezes: a geometria dos estados vem
do mesmo modulo que a automacao usa no ar, e os numeros de cada quadro saem do
MESMO exporter que grava o arquivo do GC. Assim o que a arte ve na pagina e o
que vai chegar na cena - se o calculo mudar, a pagina muda junto, em vez de
virar um desenho antigo que ninguem lembra de atualizar.

    python scripts/gerar_modelos_graficos.py

Roda offline, sem rede e sem dado do TSE.
"""

from __future__ import annotations

import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "src"))

from gctse.exporters import criar  # noqa: E402
from gctse.malha_br import CENTRO, CONTORNO, LEGENDA_EXTERNA  # noqa: E402
from gctse.modelos import Apuracao, Candidato  # noqa: E402

TEMPLATE = RAIZ / "graficos" / "modelos.template.html"
DESTINO = RAIZ / "graficos" / "modelos.html"

# --- posicao do mapa dentro do palco 16:9, em % do palco ---
MAPA_ESQ, MAPA_TOPO, MAPA_ALT = 4.5, 17.5, 72.0
MAPA_LARG = MAPA_ALT * (9 / 16) * (613 / 639)   # mantem a proporcao da malha

CORES_DEMO = {"PVL": "#2f97e8", "PDR": "#c0392b", "PXY": "#27ae60", "PQN": "#e8974a"}

# Lider ficticio por estado. Distribuicao inventada, so para a arte ver o mapa
# com mais de uma cor e conferir contraste de vizinhos.
LIDERES = {
    "AC": "PDR", "AL": "PDR", "AM": "PVL", "AP": "PVL", "BA": "PVL", "CE": "PVL",
    "DF": "PXY", "ES": "PQN", "GO": "PXY", "MA": "PVL", "MG": "PVL", "MS": "PXY",
    "MT": "PXY", "PA": "PVL", "PB": "PDR", "PE": "PDR", "PI": "PVL", "PR": "PXY",
    "RJ": "PQN", "RN": "PDR", "RO": "PXY", "RR": "PQN", "RS": "PQN", "SC": "PQN",
    "SE": "PDR", "SP": "PVL", "TO": "PXY",
}
# Percentual de urnas por estado, para o mapa de apuracao nao sair chapado.
URNAS = {
    "AC": 94, "AL": 71, "AM": 58, "AP": 88, "BA": 62, "CE": 74, "DF": 97, "ES": 83,
    "GO": 79, "MA": 47, "MG": 66, "MS": 91, "MT": 85, "PA": 41, "PB": 77, "PE": 69,
    "PI": 55, "PR": 81, "RJ": 59, "RN": 73, "RO": 87, "RR": 99, "RS": 64, "SC": 86,
    "SE": 76, "SP": 57, "TO": 92,
}

CINZA = "#6b7688"
ESCALA = "#2f97e8"


def int_br(valor: float) -> str:
    """12345 -> '12.345'. So o numero: replace na linha inteira estragaria CSS."""
    return f"{round(valor):,}".replace(",", ".")


def px(valor: float) -> str:
    """Medida em pixels do projeto 1920, convertida para a unidade do palco."""
    return f"calc({valor:g} * var(--u))"


def mistura(cor_a: str, cor_b: str, fracao: float) -> str:
    partes = lambda c: tuple(int(c.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))  # noqa: E731
    a, b = partes(cor_a), partes(cor_b)
    return "#" + "".join(f"{round(x + (y - x) * fracao):02x}" for x, y in zip(a, b))


def contraste(cor: str) -> str:
    r, g, b = (int(cor.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return "#10192b" if 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6 else "#ffffff"


# --------------------------------------------------------------------------
# Boletim ficticio - os numeros de toda a pagina saem daqui
# --------------------------------------------------------------------------

def boletim() -> Apuracao:
    ap = Apuracao(
        cargo_codigo=1,
        cargo_nome="Presidente",
        abrangencia_tipo="BR",
        abrangencia_codigo="BR",
        abrangencia_nome="BRASIL",
        fase="S",
        secoes_totalizadas=297_351,
        secoes_total=471_987,
        pct_secoes=62.99,
        eleitorado_apto=156_454_011,
        comparecimento=135_674_000,
        abstencao=20_780_011,
        votos_validos=71_420_000,
        votos_brancos=1_047_000,
        votos_nulos=2_407_531,
        total_apurado=74_874_531,
    )
    ap.candidatos = [
        Candidato(posicao=1, numero="12", nome="JOANA FIGUEIREDO", partido="PVL",
                  votos=34_153_000, percentual=47.82),
        Candidato(posicao=2, numero="27", nome="RICARDO ALMEIDA", partido="PDR",
                  votos=29_389_000, percentual=41.15),
        Candidato(posicao=3, numero="45", nome="HELENA COSTA", partido="PXY",
                  votos=5_141_000, percentual=7.20),
        Candidato(posicao=4, numero="33", nome="MARCOS TAVARES", partido="PQN",
                  votos=2_737_000, percentual=3.83),
    ]
    return ap


def campos_do_exporter(ap: Apuracao) -> dict[str, str]:
    """Os campos exatamente como o exporter os grava para o GC."""
    exportador = criar(
        "demo",
        {"tipo": "json", "composicao": {"trilho_px": 900, "rosca_raio": 120}},
        {"caixa": "alta", "formatar_numeros": True, "cores_partido": CORES_DEMO},
        {},
    )
    return exportador.campos_resumo(ap)


# --------------------------------------------------------------------------
# Pecas de desenho
# --------------------------------------------------------------------------

def defs_paths() -> str:
    return "\n".join(
        f'<path id="p-{sigla.lower()}" d="{CONTORNO[sigla]}"/>' for sigla in sorted(CONTORNO)
    )


def ponto(sigla: str) -> tuple[float, float]:
    """Centro do estado em % do palco."""
    cx, cy = CENTRO[sigla]
    return MAPA_ESQ + cx / 613 * MAPA_LARG, MAPA_TOPO + cy / 639 * MAPA_ALT


def mapa(cores: dict[str, str], rotulo) -> str:
    usos = "\n".join(
        f'<use class="uf" href="#p-{s.lower()}" fill="{cores[s]}"/>' for s in sorted(CONTORNO)
    )
    partes = [
        f'<svg class="mapa" viewBox="0 0 613 639" preserveAspectRatio="xMidYMid meet">{usos}</svg>'
    ]

    # rotulo dentro do desenho, so onde cabe
    for sigla in sorted(CONTORNO):
        if sigla in LEGENDA_EXTERNA:
            continue
        x, y = ponto(sigla)
        cor = contraste(cores[sigla])
        segunda = rotulo(sigla)
        partes.append(
            f'<div class="rot" style="left:{x:.2f}%;top:{y:.2f}%;color:{cor};'
            f'font-size:{px(26)}">{sigla}'
            + (f'<em style="font-size:{px(21)}">{segunda}</em>' if segunda else "")
            + "</div>"
        )

    # estados pequenos: rotulo na margem, com linha de chamada
    pequenos = sorted(LEGENDA_EXTERNA, key=lambda s: ponto(s)[1])
    coluna = MAPA_ESQ + MAPA_LARG + 1.4
    for indice, sigla in enumerate(pequenos):
        ox, oy = ponto(sigla)
        destino = max(oy, 24.0 + indice * 4.2)
        partes.append(
            f'<svg class="chamada" style="position:absolute;inset:0;width:100%;height:100%;'
            f'pointer-events:none" viewBox="0 0 100 100" preserveAspectRatio="none">'
            f'<line x1="{ox:.2f}" y1="{oy:.2f}" x2="{coluna - 0.7:.2f}" y2="{destino:.2f}" '
            f'stroke="#56637a" stroke-width="0.12" vector-effect="non-scaling-stroke"/></svg>'
        )
        partes.append(
            f'<div style="position:absolute;left:{coluna:.2f}%;top:{destino:.2f}%;'
            f'transform:translateY(-50%);display:flex;align-items:center;gap:{px(10)};'
            f'font-size:{px(24)};font-weight:600">'
            f'<u style="text-decoration:none;background:{cores[sigla]};width:{px(18)};'
            f'height:{px(24)};display:block"></u>{sigla}'
            f'<span style="color:#9fb0c9;font-weight:500">{rotulo(sigla) or ""}</span></div>'
        )
    return "\n".join(partes)


def guias() -> str:
    return ('<div class="guia"><i class="acao"></i><i class="titulo"></i>'
            '<b class="lba">ÁREA SEGURA</b><b class="lbt">ÁREA DE TÍTULO</b></div>')


def cabecalho_tela(titulo: str, sub: str, selo: str = "PARCIAL — NÃO OFICIAL") -> str:
    bloco = (
        f'<div class="titulo-tela" style="font-size:{px(46)}">{titulo}</div>'
        f'<div class="sub-tela" style="font-size:{px(28)}">{sub}</div>'
    )
    if selo:
        bloco += (
            f'<div class="selo" style="font-size:{px(26)};height:{px(48)};padding:0 {px(22)}">'
            f"{selo}</div>"
        )
    return bloco


def creditos() -> str:
    return (f'<div class="credito" style="font-size:{px(18)}">'
            f"Malha: @svg-maps/brazil (Victor Cazanave), CC BY 4.0</div>")


def tabela(titulo_col: str, linhas: list[tuple[str, str]]) -> str:
    corpo = "".join(
        f"<tr><td><code>{campo}</code></td><td>{texto}</td></tr>" for campo, texto in linhas
    )
    return (f'<table class="campos"><thead><tr><th>{titulo_col}</th><th>Alimenta</th></tr>'
            f"</thead><tbody>{corpo}</tbody></table>")


def modelo(codigo: str, titulo: str, museu: str, palco: str, campos: str, classe: str = "") -> str:
    return f"""
  <section class="modelo">
    <div class="mhead"><span class="codigo">{codigo}</span><h3 class="mtitulo">{titulo}</h3></div>
    <p class="museo">{museu}</p>
    <div class="palco {classe}">{palco}{guias()}</div>
    {campos}
  </section>"""


# --------------------------------------------------------------------------
# Os quadros
# --------------------------------------------------------------------------

def g1_mapa_partido(campos: dict) -> str:
    cores = {s: CORES_DEMO[LIDERES[s]] for s in CONTORNO}
    contagem: dict[str, int] = {}
    for sigla in CONTORNO:
        contagem[LIDERES[sigla]] = contagem.get(LIDERES[sigla], 0) + 1

    linhas = "".join(
        f'<div class="linha" style="font-size:{px(32)}">'
        f'<u class="sw-cor" style="background:{CORES_DEMO[p]};width:{px(34)};height:{px(34)};'
        f'display:block"></u><b>{p}</b><span>{n}</span></div>'
        for p, n in sorted(contagem.items(), key=lambda kv: (-kv[1], kv[0]))
    )

    painel = (
        f'<div class="painel"><h3 style="font-size:{px(26)}">Estados por partido</h3>{linhas}'
        f'<div style="margin-top:{px(34)};color:#9fb0c9;font-size:{px(26)}">'
        f'{campos["apuracao_pct"]} das urnas totalizadas</div></div>'
    )
    palco = (
        cabecalho_tela("PRESIDENTE — LIDERANÇA POR ESTADO",
                       "27 de 27 estados com boletim publicado | boletim das 20:41")
        + mapa(cores, lambda s: f"{URNAS[s]}%") + painel + creditos()
    )
    campos_tab = tabela("Campo do mapa-presidente.json", [
        ("estados.SP.cor", "cor do estado — vem do partido do líder, via <code>texto.cores_partido</code>"),
        ("estados.SP.lider.partido", "sigla no rótulo, quando <code>rotulo: sigla_lider</code>"),
        ("estados.SP.lider.nome", "nome do líder na dica e na tarja de detalhe do estado"),
        ("estados.SP.apuracao_pct", "percentual sob a sigla"),
        ("estados.SP.visivel", "estado sem boletim: cinza, sigla legível, nunca buraco"),
        ("pracas_com_dado / pracas_total", "linha de apoio do título"),
        ("selo", "tarja vermelha de fase; vazia quando o boletim é oficial"),
        ("hora_geracao", "hora do boletim no TSE — não é a hora do relógio da emissora"),
    ])
    return modelo(
        "G1", "Mapa — liderança por partido",
        "O quadro clássico de noite de eleição: o desenho político do país em uma imagem. "
        "Cada estado recebe a cor do partido de quem lidera ali. O painel conta quantos estados "
        "cada partido lidera, ordenado do maior para o menor.",
        palco, campos_tab,
    )


def g2_mapa_urnas(campos: dict) -> str:
    cores = {s: mistura(CINZA, ESCALA, URNAS[s] / 100) for s in CONTORNO}
    escala = "".join(
        f'<i style="flex:1;height:100%;background:{mistura(CINZA, ESCALA, i / 10)}"></i>'
        for i in range(11)
    )
    atrasados = sorted(CONTORNO, key=lambda s: URNAS[s])[:8]
    linhas = "".join(
        f'<div class="linha" style="font-size:{px(30)}"><b style="margin-left:0">{s}</b>'
        f'<i>{URNAS[s]},00%</i>'
        f"<span>{int_br(471987 / 27 * (100 - URNAS[s]) / 100)}</span></div>"
        for s in atrasados
    )
    painel = (
        f'<div class="painel"><h3 style="font-size:{px(26)}">Urnas totalizadas</h3>'
        f'<div class="barra-emp" style="height:{px(34)}">{escala}</div>'
        f'<div style="display:flex;justify-content:space-between;color:#9fb0c9;'
        f'font-size:{px(24)};margin-top:{px(10)}"><span>0%</span><span>100%</span></div>'
        f'<h3 style="font-size:{px(26)};margin-top:{px(44)}">Urnas que faltam</h3>{linhas}</div>'
    )
    palco = (
        cabecalho_tela("URNAS TOTALIZADAS POR ESTADO",
                       f'{campos["secoes_totalizadas"]} de {campos["secoes_total"]} urnas '
                       f'totalizadas | {campos["apuracao_pct"]}')
        + mapa(cores, lambda s: f"{URNAS[s]}%") + painel + creditos()
    )
    campos_tab = tabela("Campo do urnas-presidente.json", [
        ("estados.SP.apuracao_pct", "intensidade da cor — 0% cinza, 100% cor cheia"),
        ("estados.SP.secoes_totalizadas", "numerador do contador"),
        ("estados.SP.secoes_total", "denominador; a diferença é a coluna “urnas que faltam”"),
        ("secoes_totalizadas / secoes_total", "contador nacional, na linha de apoio"),
        ("apuracao_pct", "percentual nacional"),
    ])
    return modelo(
        "G2", "Mapa — urnas totalizadas",
        "O mesmo desenho, outra pergunta: quanto já apurou onde. O mapa enche ao vivo, do cinza ao "
        "cheio, e o painel lista as praças mais atrasadas com quantas urnas ainda faltam — que é a "
        "informação que a coordenação usa para decidir escala e intervalo.",
        palco, campos_tab,
    )


def g3_rosca(campos: dict) -> str:
    raio, circ = 120.0, float(campos["rosca_circunferencia"])
    cores = {"validos": "#4c6180", "brancos": "#d8dee9", "nulos": "#e8974a"}
    aneis = "".join(
        f'<circle cx="160" cy="160" r="{raio}" fill="none" stroke="{cores[f]}" stroke-width="56" '
        f'stroke-dasharray="{campos[f"rosca_{f}_dash"]}" '
        f'stroke-dashoffset="{campos[f"rosca_{f}_offset"]}" transform="rotate(-90 160 160)"/>'
        for f in ("validos", "brancos", "nulos")
    )
    rosca = (
        f'<svg viewBox="0 0 320 320" style="position:absolute;left:8%;top:22%;height:62%">{aneis}'
        f'<text x="160" y="150" text-anchor="middle" fill="#fff" font-size="44" font-weight="700">'
        f'{campos["pct_brancos_nulos"]}</text>'
        f'<text x="160" y="186" text-anchor="middle" fill="#9fb0c9" font-size="22">'
        f"BRANCOS + NULOS</text></svg>"
    )

    def linha(rotulo: str, chave: str, cor: str, valor: str) -> str:
        return (
            f'<div class="linha" style="font-size:{px(32)}">'
            f'<u class="sw-cor" style="background:{cor};width:{px(26)};height:{px(26)};'
            f'display:block"></u><b>{rotulo}</b>'
            f'<i style="margin-left:auto;width:{px(170)};text-align:right">{campos[chave]}</i>'
            f'<span style="width:{px(260)};text-align:right">{valor}</span></div>'
        )

    painel = (
        f'<div class="painel" style="top:24%"><h3 style="font-size:{px(26)}">Composição do voto</h3>'
        + linha("Válidos", "pct_validos", cores["validos"], campos["votos_validos"])
        + linha("Brancos", "pct_brancos", cores["brancos"], campos["votos_brancos"])
        + linha("Nulos", "pct_nulos", cores["nulos"], campos["votos_nulos"])
        + f'<div style="height:1px;background:#2a3547;margin:{px(22)} 0"></div>'
        + linha("Abstenção", "pct_abstencao", "#6b7688", campos["abstencao"])
        + f'<div style="color:#7d8aa0;font-size:{px(21)};margin-top:{px(16)}">'
        f"Válidos, brancos e nulos sobre os votos apurados. Abstenção sobre o eleitorado apto.</div>"
        f"</div>"
    )
    palco = (
        cabecalho_tela("COMO O BRASIL VOTOU",
                       f'{campos["apuracao_pct"]} das urnas totalizadas | boletim das 20:41')
        + rosca + painel + creditos().replace("Malha: @svg-maps/brazil (Victor Cazanave), CC BY 4.0",
                                              "Fonte: TSE — boletim de urnas totalizadas")
    )
    campos_tab = tabela("Campo do resumo", [
        ("pct_validos / pct_brancos / pct_nulos", "os três números, já em percentual — o GC não divide nada"),
        ("pct_brancos_nulos", "o número grande no miolo da rosca"),
        ("pct_abstencao", "sobre o eleitorado apto; fora da rosca, de propósito"),
        ("votos_validos / votos_brancos / votos_nulos", "os absolutos, já formatados em pt-BR"),
        ("rosca_validos_dash", "<code>stroke-dasharray</code> pronto do anel: “arco resto”"),
        ("rosca_validos_offset", "<code>stroke-dashoffset</code> — onde o anel começa"),
        ("rosca_brancos_graus / rosca_brancos_giro", "o mesmo em graus, para CG que só gira objeto"),
        ("rosca_circunferencia", "conferência: a soma dos arcos fecha exatamente aqui"),
    ])
    return modelo(
        "G3", "Composição do voto — rosca",
        "Brancos e nulos somados costumam superar o terceiro colocado, e em anos de desgaste "
        "político viram matéria por si. A rosca chega desenhada: a automação entrega o "
        "<code>stroke-dasharray</code> e o <code>stroke-dashoffset</code> de cada anel, porque "
        "aritmética de circunferência é justamente o que nenhum gerador de caracteres faz bem.",
        palco, campos_tab,
    )


def g4_tarja_brancos(campos: dict) -> str:
    cores = {"validos": "#4c6180", "brancos": "#d8dee9", "nulos": "#e8974a"}
    fatias = "".join(
        f'<i style="width:{campos[f"comp_{f}_pct"]}%;background:{cores[f]}"></i>'
        for f in ("validos", "brancos", "nulos")
    )
    legenda = "".join(
        f'<span><u style="background:{cores[f]};width:{px(18)};height:{px(18)}"></u>'
        f'{r} <b style="margin-left:{px(8)}">{campos[f"pct_{f}"]}</b></span>'
        for f, r in (("validos", "Válidos"), ("brancos", "Brancos"), ("nulos", "Nulos"))
    )
    tarja = (
        f'<div style="position:absolute;left:0;right:0;bottom:{px(70)};'
        f'background:linear-gradient(100deg,#061436 0%,#0b2450 60%,#0e2f66 100%);'
        f'padding:{px(26)} {px(90)} {px(30)}">'
        f'<div style="display:flex;align-items:baseline;gap:{px(18)};margin-bottom:{px(18)}">'
        f'<span style="font-size:{px(34)};font-weight:700;letter-spacing:.02em">'
        f"COMPOSIÇÃO DO VOTO</span>"
        f'<span style="font-size:{px(24)};color:#9fb0c9">PRESIDENTE · BRASIL</span>'
        f'<span style="margin-left:auto;font-size:{px(24)};color:#9fb0c9">'
        f'{campos["apuracao_pct"]} DAS URNAS</span></div>'
        f'<div class="barra-emp" style="height:{px(38)}">{fatias}</div>'
        f'<div class="legenda" style="font-size:{px(24)}">{legenda}'
        f'<span style="margin-left:auto">ABSTENÇÃO <b style="margin-left:{px(8)}">'
        f'{campos["pct_abstencao"]}</b></span></div></div>'
    )
    campos_tab = tabela("Campo do resumo", [
        ("comp_validos_px / comp_brancos_px / comp_nulos_px",
         "largura de cada fatia em pixels, já somando exato no trilho configurado"),
        ("comp_validos_x", "posição inicial da fatia — para CG que só move objeto"),
        ("comp_trilho_px", "largura total do trilho, definida em <code>composicao.trilho_px</code>"),
        ("pct_validos / pct_brancos / pct_nulos", "os números da legenda"),
        ("pct_abstencao", "no canto direito, separado — outra base"),
        ("apuracao_pct", "percentual de urnas, no canto"),
    ])
    return modelo(
        "G4", "Tarja de brancos e nulos",
        "A versão de rodapé, sobre imagem: uma barra empilhada de 100% com válidos, brancos e "
        "nulos, e a abstenção à direita, separada porque tem outra base. As larguras vêm em "
        "pixels somando exato no trilho — sem sobra de 1px de fundo aparecendo entre duas fatias.",
        tarja, campos_tab, classe="sobre",
    )


def g5_curva(campos: dict) -> str:
    # curva de apuracao: arranque rapido, cauda longa - como e na vida real
    pontos = [(0, 0), (8, 14), (16, 31), (24, 44), (32, 54), (40, 61), (48, 67),
              (56, 72), (64, 76), (72, 79), (80, 82), (88, 84)]
    alt = lambda p: 520 - p * 4.6  # noqa: E731  (100% no topo, 0% na base)
    linha = " ".join(f"{x * 10},{alt(p):.0f}" for x, p in pontos)
    projecao = " ".join(f"{x * 10},{alt(p):.0f}" for x, p in [(88, 84), (108, 94), (124, 100)])

    grade = "".join(
        f'<line x1="0" y1="{alt(v):.0f}" x2="1240" y2="{alt(v):.0f}" '
        f'stroke="#22304a" stroke-width="1"/>'
        f'<text x="-12" y="{alt(v) + 7:.0f}" fill="#7d8aa0" font-size="20" '
        f'text-anchor="end">{v}%</text>'
        for v in (0, 25, 50, 75, 100)
    )
    grafico = (
        f'<svg viewBox="-70 -30 1360 600" style="position:absolute;left:5.7%;top:25%;width:64%">'
        f"{grade}"
        f'<polyline points="{linha}" fill="none" stroke="#2f97e8" stroke-width="6" '
        f'stroke-linejoin="round" stroke-linecap="round"/>'
        f'<polyline points="{projecao}" fill="none" stroke="#2f97e8" stroke-width="5" '
        f'stroke-dasharray="12 10" opacity="0.6"/>'
        f'<circle cx="880" cy="{alt(84):.0f}" r="10" fill="#2f97e8"/>'
        f'<line x1="1240" y1="30" x2="1240" y2="{alt(0):.0f}" stroke="#e8974a" stroke-width="2" '
        f'stroke-dasharray="7 7"/>'
        f'<text x="1232" y="20" fill="#e8974a" font-size="22" text-anchor="end">'
        f"PREVISÃO 22:10</text></svg>"
    )
    painel = (
        f'<div class="painel" style="top:26%;width:20%">'
        f'<h3 style="font-size:{px(26)}">No ritmo atual</h3>'
        f'<div style="font-size:{px(72)};font-weight:700;line-height:1">22:10</div>'
        f'<div style="color:#9fb0c9;font-size:{px(26)};margin-top:{px(6)}">previsão de 100%</div>'
        f'<div style="font-size:{px(38)};font-weight:600;margin-top:{px(38)}">1,9 p.p./min</div>'
        f'<div style="color:#9fb0c9;font-size:{px(24)}">ritmo dos últimos boletins</div>'
        f'<div style="font-size:{px(38)};font-weight:600;margin-top:{px(28)}">174.636</div>'
        f'<div style="color:#9fb0c9;font-size:{px(24)}">urnas que faltam</div></div>'
    )
    palco = (
        cabecalho_tela("RITMO DA APURAÇÃO",
                       f'{campos["apuracao_pct"]} das urnas totalizadas | boletim das 20:41', "")
        + grafico + painel
    )
    campos_tab = tabela("Campo do graficos.json", [
        ("alvos.presidente-br.serie[].pct", "cada ponto da curva — um por boletim publicado"),
        ("alvos.presidente-br.serie[].hora", "eixo do tempo"),
        ("alvos.presidente-br.projecao.previsao", "o horário grande: 100% no ritmo atual"),
        ("alvos.presidente-br.projecao.pontos_por_minuto", "o ritmo, em pontos percentuais por minuto"),
        ("alvos.presidente-br.projecao.minutos", "quanto falta, em minutos"),
        ("alvos.presidente-br.viradas[]", "marcos de troca de liderança, com hora e percentual"),
    ])
    return modelo(
        "G5", "Curva de apuração e previsão de fechamento",
        "Este é o quadro de gestão, não de ar: a que horas as urnas terminam, no passo dos últimos "
        "boletins. Define quando liberar equipe, quando cabe intervalo e qual praça está atrasada. "
        "É projeção de <strong>ritmo</strong> — não diz nada sobre quem vence, e não deve ir ao ar "
        "como se dissesse.",
        palco, campos_tab,
    )


def g6_contador(campos: dict) -> str:
    cores = {s: mistura(CINZA, ESCALA, URNAS[s] / 100) for s in CONTORNO}
    mini = (
        f'<svg viewBox="0 0 613 639" style="position:absolute;right:7%;top:16%;height:70%;'
        f'opacity:.9">'
        + "".join(
            f'<use href="#p-{s.lower()}" fill="{cores[s]}" stroke="#0b1220" stroke-width="1.2"/>'
            for s in sorted(CONTORNO)
        )
        + "</svg>"
    )
    corpo = (
        f'<div style="position:absolute;left:6.5%;top:26%">'
        f'<div style="font-size:{px(30)};color:#9fb0c9;letter-spacing:.14em">URNAS TOTALIZADAS</div>'
        f'<div style="font-size:{px(150)};font-weight:700;line-height:1;margin-top:{px(10)};'
        f'font-variant-numeric:tabular-nums">{campos["secoes_totalizadas"]}</div>'
        f'<div style="font-size:{px(38)};color:#9fb0c9;margin-top:{px(6)}">'
        f'de {campos["secoes_total"]} · {campos["apuracao_pct"]}</div>'
        f'<div class="barra-emp" style="height:{px(22)};width:{px(760)};margin-top:{px(34)};'
        f'background:#22304a">'
        f'<i style="width:{campos["apuracao_pct_num"]}%;background:{ESCALA}"></i></div>'
        f'<div style="font-size:{px(30)};margin-top:{px(34)}">'
        f'Faltam <b>{campos["secoes_restantes"]}</b> urnas</div></div>'
    )
    palco = (
        cabecalho_tela("APURAÇÃO — BRASIL", "boletim das 20:41 | atualiza sozinho a cada 20 s")
        + corpo + mini + creditos()
    )
    campos_tab = tabela("Campo do resumo", [
        ("secoes_totalizadas", "o número grande"),
        ("secoes_total", "o denominador"),
        ("secoes_restantes", "quantas faltam — a conta já vem pronta"),
        ("apuracao_pct", "percentual formatado, para o texto"),
        ("apuracao_pct_num", "o mesmo em número, para a largura da barra"),
        ("votos_restantes", "estimativa de votos que ainda faltam apurar"),
        ("reversivel", "1 quando a diferença entre 1º e 2º cabe no que falta apurar"),
    ])
    return modelo(
        "G6", "Contador de urnas",
        "O quadro mais simples e o mais pedido: quantas urnas já foram totalizadas. Serve de "
        "abertura de bloco e de passagem entre placares. O campo <code>reversivel</code> responde, "
        "na mesma leitura, se a diferença entre 1º e 2º ainda cabe no que falta apurar.",
        palco, campos_tab,
    )


def svgs_de_exemplo() -> list[Path]:
    """Os dois mapas como o exporter os grava, para a arte importar no vetor.

    Sao os MESMOS arquivos que o dia da eleicao produz - com dado ficticio.
    Existem no repositorio para o time abrir e medir sem precisar rodar nada.
    """
    from gctse.tse.parser import analisar

    def boletim(uf: str) -> dict:
        pct = URNAS[uf]
        partido = LIDERES[uf]
        return {
            "carg": "1", "cdabr": uf, "nmabr": uf, "tpabr": "UF", "f": "S",
            "dg": "04/10/2026", "hg": "20:41:00",
            "s": {"st": f"{int(17_481 * pct / 100)}", "s": "17.481", "pst": f"{pct},00"},
            "vv": "2.645.000", "vb": "38.800", "vn": "89.200", "tvn": "2.773.000",
            "ea": "5.794.000", "c": "2.773.000", "a": "769.000",
            "cand": [
                {"n": "12", "nm": "JOANA FIGUEIREDO", "cc": partido,
                 "vap": "1.265.000", "pvap": "47,82"},
                {"n": "27", "nm": "RICARDO ALMEIDA", "cc": "PDR" if partido != "PDR" else "PVL",
                 "vap": "1.088.000", "pvap": "41,15"},
            ],
        }

    itens = [
        (ordem, uf, analisar(boletim(uf), abrangencia=uf.lower(), cargo=1))
        for ordem, uf in enumerate(sorted(CONTORNO), start=1)
    ]
    texto = {"caixa": "alta", "formatar_numeros": True, "cores_partido": CORES_DEMO,
             "cor_padrao": "#7d93b3"}

    escritos: list[Path] = []
    for nome, modo, titulo in (
        ("exemplo-mapa-partido", "partido", "PRESIDENTE - LIDERANCA POR ESTADO"),
        ("exemplo-mapa-urnas", "apuracao", "URNAS TOTALIZADAS POR ESTADO"),
    ):
        exportador = criar(
            nome,
            {"tipo": "mapa", "modo": modo, "titulo": titulo, "formatos": ["svg"],
             "destino": str(RAIZ / "graficos")},
            texto,
            {"quebra_linha": "lf"},
        )
        escritos += exportador.exportar_lista(itens, nome)
    return escritos


def main() -> int:
    ap = boletim()
    campos = campos_do_exporter(ap)

    template = TEMPLATE.read_text(encoding="utf-8")

    modelos = "\n".join(
        [
            g1_mapa_partido(campos),
            g2_mapa_urnas(campos),
            g3_rosca(campos),
            g4_tarja_brancos(campos),
            g5_curva(campos),
            g6_contador(campos),
        ]
    )
    saida = template.replace("{{PATHS}}", defs_paths()).replace("{{MODELOS}}", modelos)
    DESTINO.write_text(saida, encoding="utf-8")
    print(f"gravado: {DESTINO} ({len(saida) / 1024:.0f} KB)")
    for caminho in svgs_de_exemplo():
        print(f"gravado: {caminho}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
