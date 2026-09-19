"""Telas em retrato, 1080x1920, para o monitor vertical da cena.

Monitor de cena e um problema diferente do telao do switcher. Ele fica em
quadro o tempo todo, atras do apresentador, sem ninguem operando: nao ha mesa,
nao ha quem escolha. Entao ele **roda sozinho**, como uma apresentacao de
slides, e cada tela precisa se explicar em dois segundos - que e o tempo que a
camera fica nele antes de voltar para o apresentador.

Isso muda tres coisas em relacao as telas de 1920x1080:

1. UM NUMERO POR TELA. A tela horizontal tem espaco para um mapa e um painel
   ao lado; esta aqui tem um assunto so, em corpo grande. Quem olha de longe,
   de esguelha, no meio de uma entrevista, le um numero - nao uma tabela.
2. VERTICAL FAVORECE LISTA. 1920 pixels de altura cabem 27 estados em coluna
   sem apertar, coisa que na horizontal exigiria duas colunas.
3. SEM RODAPE TECNICO. O credito da malha e a hora do boletim ficam pequenos e
   embaixo, porque a tela esta em cena o tempo todo e texto miudo em cena vira
   sujeira visual.

As telas:

  urnas           urnas apuradas no Brasil - o numero que mais se repete no ar
  brancos-nulos   brancos e nulos, em rosca, com os absolutos
  comparecimento  quem foi votar e quem nao foi - existe antes do resultado
  placar          os candidatos, em lista vertical
  mapa            o mapa do Brasil por cor de partido, com a legenda embaixo
  estados         as 27 UFs em coluna: quem lidera em cada uma
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path

from gctse.malha_br import CENTRO, CONTORNO, CREDITO, LEGENDA_EXTERNA
from gctse.util.arquivos import escrever_texto
from gctse.util.svg import (
    COR_APOIO,
    COR_DISCRETA,
    COR_LINHA,
    contraste,
    escapar,
    int_br,
    pct_br,
    retangulo,
    texto,
)

from .config import Config
from .telas import (
    COR_BRANCOS,
    COR_ELEITO,
    COR_ESCALA,
    COR_NULOS,
    COR_VALIDOS,
    Dados,
    Mapa,
    Moldura,
)

log = logging.getLogger("telao.vertical")

LARGURA = 1080
ALTURA = 1920
MARGEM = 70.0

COR_ABSTENCAO = "#6b7688"

# Area util do corpo. Fora dela ficam o cabecalho (acima) e o rodape (abaixo).
# Declarada porque o erro facil aqui e desenhar tudo no terco de cima e deixar
# o resto morto - o que numa tela de 1920 de altura, em cena, salta aos olhos.
TOPO = 400.0
BASE = 1780.0

TIPOS = ("urnas", "brancos-nulos", "comparecimento", "placar", "mapa", "estados")

# A ordem padrao do rodizio. Comeca e termina no numero mais repetido no ar,
# para quem pega a tela no meio do giro ver primeiro o dado principal.
PADRAO = ["urnas", "brancos-nulos", "comparecimento", "placar", "mapa", "estados"]

TITULOS = {
    "urnas": "URNAS APURADAS",
    "brancos-nulos": "BRANCOS E NULOS",
    "comparecimento": "COMPARECIMENTO",
    "placar": "APURAÇÃO",
    "mapa": "LIDERANÇA POR ESTADO",
    "estados": "COMO CADA ESTADO VOTOU",
}


class MolduraV:
    """Moldura do retrato: faixa de topo, corpo e rodape discreto."""

    def __init__(self, cfg: Config):
        self.base = Moldura(cfg)
        self.fonte = self.base.fonte
        self.fundo = self.base.fundo

    def abrir(self) -> list[str]:
        return [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {LARGURA} {ALTURA}" '
            f'width="{LARGURA}" height="{ALTURA}" font-family="{escapar(self.fonte)}">',
            retangulo(0, 0, LARGURA, ALTURA, self.fundo),
        ]

    def cabecalho(self, titulo: str, sub: str = "", selo: str = "") -> list[str]:
        titulo = (titulo or "").upper()
        # o titulo comeca depois da barra lateral, entao a largura util e menor
        corpo = max(38, corpo_que_cabe(titulo, 64, LARGURA - 2 * MARGEM - 34, fator=0.75))
        partes = [
            retangulo(MARGEM, 96, 12, 76, COR_ESCALA),
            texto(MARGEM + 34, 158, titulo, tamanho=corpo, peso="700", espacamento="1"),
        ]
        if sub:
            partes.append(texto(MARGEM + 34, 212, sub, tamanho=30, cor=COR_APOIO))
        if selo:
            partes.append(retangulo(MARGEM, 254, LARGURA - 2 * MARGEM, 52, "#c0392b", raio=4))
            partes.append(
                texto(LARGURA / 2, 291, selo, tamanho=30, peso="600", ancora="middle")
            )
        return partes

    def rodape(self, dados: Dados, com_malha: bool = False) -> list[str]:
        ap = dados.nacional
        linha = "Fonte: TSE"
        if ap is not None and ap.gerado_em:
            linha += f"  ·  boletim das {ap.gerado_em.strftime('%H:%M')}"
        partes = [texto(MARGEM, ALTURA - 58, linha, tamanho=22, cor=COR_DISCRETA)]
        if com_malha and self.base.credito:
            partes.append(
                texto(LARGURA - MARGEM, ALTURA - 58, CREDITO, tamanho=18,
                      cor=COR_DISCRETA, ancora="end")
            )
        return partes

    def selo(self, dados: Dados) -> str:
        return self.base.selo(dados.nacional)

    def aviso(self, titulo: str) -> str:
        partes = self.abrir()
        partes += self.cabecalho(titulo)
        partes.append(
            texto(LARGURA / 2, ALTURA / 2, "AGUARDANDO BOLETIM", tamanho=48,
                  cor=COR_APOIO, ancora="middle", espacamento="2")
        )
        partes.append("</svg>")
        return "\n".join(partes)

    def fechar(self, partes: list[str]) -> str:
        partes.append("</svg>")
        return "\n".join(partes)


def corpo_que_cabe(
    valor: str,
    maximo: float,
    largura: float = LARGURA - 2 * MARGEM,
    fator: float = 0.62,
) -> float:
    """Maior corpo de fonte em que 'valor' ainda cabe na largura dada.

    Existe porque numero de eleicao cresce de digito sem avisar: '297.360'
    cabe folgado em corpo 200, mas o eleitorado apto do Brasil tem onze
    caracteres ('156.454.011') e vaza pela margem no mesmo corpo - o texto
    simplesmente sai da tela, sem erro nenhum, e so aparece no ar.

    O fator 0.62 e a largura media de um digito em relacao ao corpo, com folga
    para a fonte de reserva: a Barlow Condensed e estreita, mas quem nao a
    tiver instalada cai numa Arial Narrow - ou, em alguns renderizadores, numa
    sans larga - e o numero estouraria a margem. Sobrar margem e barato;
    vazar so aparece no ar.

    Texto em caixa alta usa 'fator' maior que numero: 'M' e 'D' sao bem mais
    largas que um digito, e um titulo dimensionado com a medida de numero
    corta a ultima palavra.
    """
    if not valor:
        return maximo
    # corpo inteiro: meio pixel de fonte nao muda nada no ar e deixa o SVG
    # legivel para quem for conferir o arquivo
    return float(int(min(maximo, largura / (len(valor) * fator))))


def _numerao(partes: list[str], y: float, valor: str, rotulo: str, apoio: str = "") -> float:
    """O bloco 'rotulo em cima, numero gigante embaixo', repetido nas telas.

    O rotulo vem ANTES do numero porque quem olha de relance le de cima para
    baixo e precisa saber do que e o numero antes de ler o numero.
    """
    partes.append(texto(MARGEM, y, rotulo, tamanho=32, cor=COR_APOIO, espacamento="5"))
    partes.append(texto(MARGEM, y + 150, valor, tamanho=corpo_que_cabe(valor, 190), peso="700"))
    if apoio:
        partes.append(texto(MARGEM, y + 208, apoio, tamanho=40, cor=COR_APOIO))
    return y + (250 if apoio else 200)


def _barra(partes: list[str], y: float, fracao: float, altura: float = 34) -> float:
    largura = LARGURA - 2 * MARGEM
    partes.append(retangulo(MARGEM, y, largura, altura, COR_LINHA, raio=2))
    partes.append(
        retangulo(MARGEM, y, largura * max(0.0, min(1.0, fracao)), altura, COR_ESCALA, raio=2)
    )
    return y + altura + 40


# ---------------------------------------------------------------------------
# As telas
# ---------------------------------------------------------------------------


def v_urnas(m: MolduraV, dados: Dados) -> str:
    """Urnas apuradas no Brasil. E o numero que mais se repete no ar."""
    totalizadas, total = dados.total_secoes
    if not total:
        return m.aviso(TITULOS["urnas"])

    pct = 100.0 * totalizadas / total
    partes = m.abrir()
    partes += m.cabecalho(
        TITULOS["urnas"],
        "no Brasil" if dados.nacional else "soma das praças com boletim",
        m.selo(dados),
    )

    partes.append(texto(MARGEM, TOPO + 30, "URNAS TOTALIZADAS", tamanho=34,
                        cor=COR_APOIO, espacamento="5"))
    numero = int_br(totalizadas)
    partes.append(texto(MARGEM, TOPO + 200, numero, tamanho=corpo_que_cabe(numero, 200),
                        peso="700"))
    partes.append(texto(MARGEM, TOPO + 262, f"de {int_br(total)}", tamanho=44, cor=COR_APOIO))

    _barra(partes, TOPO + 340, pct / 100.0, altura=54)
    partes.append(texto(MARGEM, TOPO + 570, f"{pct_br(pct)}%", tamanho=170, peso="700"))
    partes.append(texto(MARGEM, TOPO + 632, "da apuração concluída", tamanho=40, cor=COR_APOIO))

    ap = dados.nacional
    if ap is not None and ap.votos_apurados:
        partes.append(retangulo(MARGEM, TOPO + 740, LARGURA - 2 * MARGEM, 1, COR_LINHA))
        partes.append(texto(MARGEM, TOPO + 830, "VOTOS APURADOS", tamanho=34,
                            cor=COR_APOIO, espacamento="5"))
        apurados = int_br(ap.votos_apurados)
        partes.append(texto(MARGEM, TOPO + 950, apurados,
                            tamanho=corpo_que_cabe(apurados, 110), peso="700"))
        partes.append(texto(MARGEM, TOPO + 1010, "válidos, brancos e nulos somados",
                            tamanho=32, cor=COR_DISCRETA))

    partes += m.rodape(dados)
    return m.fechar(partes)


def v_brancos_nulos(m: MolduraV, dados: Dados) -> str:
    """Brancos e nulos: a rosca grande, com os absolutos embaixo."""
    ap = dados.nacional
    if ap is None or not ap.votos_apurados:
        return m.aviso(TITULOS["brancos-nulos"])

    partes = m.abrir()
    partes += m.cabecalho(
        TITULOS["brancos-nulos"], f"{pct_br(ap.pct_secoes)}% das urnas apuradas", m.selo(dados)
    )

    centro_x, centro_y, raio = LARGURA / 2, 800.0, 260.0
    circunferencia = 2 * 3.141592653589793 * raio
    fatias = (
        (ap.pct_validos, COR_VALIDOS, "Válidos", ap.votos_validos),
        (ap.pct_brancos, COR_BRANCOS, "Brancos", ap.votos_brancos),
        (ap.pct_nulos, COR_NULOS, "Nulos", ap.votos_nulos),
    )
    acumulado = 0.0
    for pct, cor, _rotulo, _votos in fatias:
        arco = circunferencia * pct / 100.0
        partes.append(
            f'<circle cx="{centro_x:g}" cy="{centro_y:g}" r="{raio:g}" fill="none" '
            f'stroke="{cor}" stroke-width="112" '
            f'stroke-dasharray="{arco:.2f} {circunferencia - arco:.2f}" '
            f'stroke-dashoffset="{-circunferencia * acumulado / 100.0:.2f}" '
            f'transform="rotate(-90 {centro_x:g} {centro_y:g})"/>'
        )
        acumulado += pct

    partes.append(texto(centro_x, centro_y + 10, f"{pct_br(ap.pct_brancos_nulos)}%",
                        tamanho=110, peso="700", ancora="middle"))
    partes.append(texto(centro_x, centro_y + 70, "BRANCOS + NULOS", tamanho=28,
                        cor=COR_APOIO, ancora="middle", espacamento="3"))

    y = 1300.0
    for pct, cor, rotulo, votos in fatias[1:] + fatias[:1]:   # brancos, nulos, validos
        partes.append(retangulo(MARGEM, y - 32, 36, 36, cor, raio=3))
        partes.append(texto(MARGEM + 60, y, rotulo, tamanho=46, peso="600"))
        partes.append(texto(LARGURA - MARGEM, y, int_br(votos), tamanho=46, ancora="end"))
        partes.append(texto(LARGURA - MARGEM, y + 48, f"{pct_br(pct)}%", tamanho=34,
                            cor=COR_APOIO, ancora="end"))
        y += 148

    partes.append(
        texto(MARGEM, y + 20, "sobre os votos apurados", tamanho=26, cor=COR_DISCRETA)
    )
    partes += m.rodape(dados)
    return m.fechar(partes)


def v_comparecimento(m: MolduraV, dados: Dados) -> str:
    """Quem foi votar e quem nao foi.

    E o unico numero que existe ANTES de sair resultado, entao esta tela tem
    conteudo desde a hora em que as urnas fecham - e nao fica aguardando
    boletim enquanto o resto do painel ainda esta vazio.
    """
    ap = dados.nacional
    if ap is None or not ap.eleitorado_apto:
        return m.aviso(TITULOS["comparecimento"])

    partes = m.abrir()
    partes += m.cabecalho(
        TITULOS["comparecimento"], f"{pct_br(ap.pct_secoes)}% das urnas apuradas", m.selo(dados)
    )

    partes.append(texto(MARGEM, TOPO + 30, "FORAM VOTAR", tamanho=34,
                        cor=COR_APOIO, espacamento="5"))
    compareceram = int_br(ap.comparecimento)
    partes.append(texto(MARGEM, TOPO + 200, compareceram,
                        tamanho=corpo_que_cabe(compareceram, 200), peso="700"))
    apoio = f"de {int_br(ap.eleitorado_apto)} eleitores aptos"
    partes.append(texto(MARGEM, TOPO + 262, apoio,
                        tamanho=corpo_que_cabe(apoio, 40), cor=COR_APOIO))
    partes.append(texto(MARGEM, TOPO + 430, f"{pct_br(ap.pct_comparecimento)}%",
                        tamanho=170, peso="700"))

    # Uma barra so, com as duas fatias: compareceu a esquerda, absteve a
    # direita. Sobre o eleitorado apto - as duas fatias fecham 100%.
    largura = LARGURA - 2 * MARGEM
    fracao = max(0.0, min(1.0, ap.pct_comparecimento / 100.0))
    partes.append(retangulo(MARGEM, TOPO + 500, largura, 54, COR_ABSTENCAO, raio=2))
    partes.append(retangulo(MARGEM, TOPO + 500, largura * fracao, 54, COR_ESCALA, raio=2))

    y = TOPO + 720
    partes.append(retangulo(MARGEM, y - 40, 40, 40, COR_ABSTENCAO, raio=3))
    partes.append(texto(MARGEM + 66, y, "Abstenção", tamanho=52, peso="600"))
    partes.append(texto(LARGURA - MARGEM, y, int_br(ap.abstencao), tamanho=52, ancora="end"))
    partes.append(texto(LARGURA - MARGEM, y + 50, f"{pct_br(ap.pct_abstencao)}%",
                        tamanho=36, cor=COR_APOIO, ancora="end"))

    if ap.votos_brancos or ap.votos_nulos:
        # quem foi votar e ainda assim nao escolheu ninguem - a leitura que
        # completa o comparecimento
        partes.append(retangulo(MARGEM, y + 130, largura, 1, COR_LINHA))
        partes.append(texto(MARGEM, y + 220, "FORAM E NÃO ESCOLHERAM", tamanho=34,
                            cor=COR_APOIO, espacamento="5"))
        sem_escolha = int_br(ap.votos_brancos + ap.votos_nulos)
        partes.append(texto(MARGEM, y + 330, sem_escolha,
                            tamanho=corpo_que_cabe(sem_escolha, 110), peso="700"))
        partes.append(texto(MARGEM, y + 390, f"brancos e nulos  ·  "
                            f"{pct_br(ap.pct_brancos_nulos)}% dos votos apurados",
                            tamanho=32, cor=COR_DISCRETA))

    partes += m.rodape(dados)
    return m.fechar(partes)


def v_placar(m: MolduraV, dados: Dados, limite: int = 5) -> str:
    """Os candidatos em lista vertical - o formato natural do retrato."""
    ap = dados.nacional
    if ap is None or not ap.candidatos:
        return m.aviso(TITULOS["placar"])

    candidatos = ap.candidatos[: max(1, limite)]
    partes = m.abrir()
    partes += m.cabecalho(
        ap.cargo_nome.upper(), f"{pct_br(ap.pct_secoes)}% das urnas apuradas", m.selo(dados)
    )

    topo = TOPO + 40
    passo = min(290.0, (BASE - topo) / len(candidatos))
    trilho = LARGURA - 2 * MARGEM
    referencia = max((c.percentual for c in candidatos), default=0.0) or 100.0

    for indice, cand in enumerate(candidatos):
        y = topo + indice * passo
        cor = m.base.cor_partido(cand.partido)
        fracao = max(0.0, min(1.0, cand.percentual / referencia))

        partes.append(retangulo(MARGEM, y - 52, 10, 70, cor))
        partes.append(texto(MARGEM + 30, y, cand.nome, tamanho=44, peso="600"))
        if cand.partido:
            partes.append(texto(MARGEM + 30, y + 42, cand.partido, tamanho=28, cor=COR_APOIO))
        partes.append(texto(LARGURA - MARGEM, y + 6, f"{pct_br(cand.percentual)}%",
                            tamanho=64, peso="700", ancora="end"))
        if cand.eleito:
            partes.append(texto(LARGURA - MARGEM, y + 46, "ELEITO", tamanho=26,
                                cor=COR_ELEITO, peso="700", ancora="end"))

        y_barra = y + 72
        partes.append(retangulo(MARGEM, y_barra, trilho, 26, COR_LINHA, raio=2))
        partes.append(
            retangulo(MARGEM, y_barra, max(6.0, trilho * fracao) if cand.percentual > 0 else 0.0,
                      26, cor, raio=2)
        )
        partes.append(texto(MARGEM, y_barra + 58, int_br(cand.votos), tamanho=30, cor=COR_APOIO))

    partes += m.rodape(dados)
    return m.fechar(partes)


def v_mapa(m: MolduraV, mapa: Mapa, dados: Dados) -> str:
    """O mapa do Brasil por cor de partido, com a legenda embaixo.

    O contorno do pais e quase quadrado (613x639), entao no retrato ele cabe
    inteiro na largura e ainda sobra altura para a legenda - que na tela
    horizontal precisa ir para o lado.
    """
    if not dados.estados:
        return m.aviso(TITULOS["mapa"])

    mapa_dados = mapa.dados(dados.estados, "partido")
    partes = m.abrir()
    partes += m.cabecalho(
        TITULOS["mapa"],
        f"{mapa_dados['pracas_com_dado']} de 27 estados com boletim",
        m.selo(dados),
    )

    escala = 1.5
    x0, y0 = (LARGURA - 613 * escala) / 2, 360.0
    partes.append(f'<g transform="translate({x0:g},{y0:g}) scale({escala:g})">')
    for sigla in sorted(CONTORNO):
        cor = (mapa_dados["estados"].get(sigla) or {}).get("cor", "#6b7688")
        partes.append(
            f'<path d="{CONTORNO[sigla]}" fill="{cor}" stroke="#0b1220" '
            f'stroke-width="1.2" stroke-linejoin="round"/>'
        )
    partes.append("</g>")

    for sigla in sorted(CONTORNO):
        if sigla in LEGENDA_EXTERNA:
            continue
        estado = mapa_dados["estados"].get(sigla) or {}
        cx, cy = CENTRO[sigla]
        partes.append(
            texto(x0 + cx * escala, y0 + cy * escala + 9, sigla, tamanho=26, peso="700",
                  cor=contraste(estado.get("cor", "#6b7688")), ancora="middle")
        )

    # legenda: quantos estados cada partido lidera, em duas colunas
    contagem: dict[str, dict] = {}
    for estado in mapa_dados["estados"].values():
        lider = estado.get("lider")
        if not estado.get("visivel") or not lider:
            continue
        registro = contagem.setdefault(lider["partido"] or "SEM PARTIDO",
                                       {"ufs": 0, "cor": lider["cor"]})
        registro["ufs"] += 1

    y = 1450.0
    partes.append(texto(MARGEM, y, "ESTADOS POR PARTIDO", tamanho=30, cor=COR_APOIO,
                        espacamento="4"))
    y += 60
    ordenados = sorted(contagem.items(), key=lambda kv: (-kv[1]["ufs"], kv[0]))[:8]
    for indice, (sigla, registro) in enumerate(ordenados):
        x = MARGEM + (indice % 2) * (LARGURA - 2 * MARGEM) / 2
        linha_y = y + (indice // 2) * 76
        partes.append(retangulo(x, linha_y - 30, 34, 34, registro["cor"], raio=3))
        partes.append(texto(x + 52, linha_y, sigla, tamanho=38, peso="600"))
        partes.append(texto(x + (LARGURA - 2 * MARGEM) / 2 - 40, linha_y, str(registro["ufs"]),
                            tamanho=38, ancora="end"))

    partes += m.rodape(dados, com_malha=True)
    return m.fechar(partes)


def v_estados(m: MolduraV, mapa: Mapa, dados: Dados) -> str:
    """As 27 UFs em coluna: quem lidera em cada uma.

    A altura do retrato comporta as 27 linhas sem apertar - na horizontal isso
    exigiria duas colunas e letra menor.
    """
    if not dados.estados:
        return m.aviso(TITULOS["estados"])

    mapa_dados = mapa.dados(dados.estados, "partido")
    partes = m.abrir()
    partes += m.cabecalho(
        TITULOS["estados"],
        f"{mapa_dados['pracas_com_dado']} de 27 estados com boletim",
        m.selo(dados),
    )

    topo, passo = 400.0, 54.0
    for indice, sigla in enumerate(sorted(CONTORNO)):
        estado = mapa_dados["estados"][sigla]
        y = topo + indice * passo
        lider = estado.get("lider") or {}
        partes.append(retangulo(MARGEM, y - 26, 8, 34, estado.get("cor", "#6b7688")))
        partes.append(texto(MARGEM + 24, y, sigla, tamanho=34, peso="700"))
        if estado.get("visivel") and lider:
            partes.append(texto(MARGEM + 100, y, lider.get("partido") or "—",
                                tamanho=30, cor=COR_APOIO))
            partes.append(texto(LARGURA - MARGEM, y,
                                f"{pct_br(lider.get('percentual', 0.0))}%",
                                tamanho=32, peso="600", ancora="end"))
        else:
            partes.append(texto(MARGEM + 100, y, "aguardando", tamanho=28, cor=COR_DISCRETA))

    partes += m.rodape(dados, com_malha=True)
    return m.fechar(partes)


# ---------------------------------------------------------------------------
# Despacho
# ---------------------------------------------------------------------------


def desenhar(cfg: Config, tipo: str, dados: Dados) -> str:
    moldura = MolduraV(cfg)
    if tipo == "urnas":
        return v_urnas(moldura, dados)
    if tipo == "brancos-nulos":
        return v_brancos_nulos(moldura, dados)
    if tipo == "comparecimento":
        return v_comparecimento(moldura, dados)
    if tipo == "placar":
        return v_placar(moldura, dados, int(cfg.vertical.get("limite_candidatos", 5)))
    if tipo == "mapa":
        return v_mapa(moldura, Mapa(moldura.base, cfg), dados)
    if tipo == "estados":
        return v_estados(moldura, Mapa(moldura.base, cfg), dados)
    raise ValueError(f"tipo de tela vertical desconhecido: {tipo!r}")


# ---------------------------------------------------------------------------
# Publicacao e a pagina do monitor
# ---------------------------------------------------------------------------


def telas_configuradas(cfg: Config) -> list[str]:
    """Os tipos que vao ao rodizio, na ordem. Desconhecido cai fora com aviso."""
    pedido = cfg.vertical.get("telas") or PADRAO
    if isinstance(pedido, str):
        pedido = [pedido]
    escolhidas: list[str] = []
    for item in pedido:
        tipo = str(item).strip().lower()
        if tipo not in TIPOS:
            log.warning("vertical: tela '%s' desconhecida - ignorada", tipo)
            continue
        if tipo not in escolhidas:
            escolhidas.append(tipo)
    return escolhidas


class PublicadorVertical:
    """Grava as telas do monitor vertical e a pagina que as roda."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.ativo = bool(cfg.vertical.get("ativo", False))
        self.destino = Path(cfg.vertical.get("destino", "telao-vertical"))
        self.rodizio = max(3, int(cfg.vertical.get("rodizio_segundos", 10)))
        self.tipos = telas_configuradas(cfg)
        self._impressoes: dict[str, str] = {}

    def publicar(self, dados: Dados) -> list[Path]:
        if not self.ativo or not self.tipos:
            return []

        escritos: list[Path] = []
        for tipo in self.tipos:
            try:
                svg = desenhar(self.cfg, tipo, dados)
            except Exception:
                # uma tela com defeito nao tira o monitor do ar: o rodizio
                # continua com as outras e o log diz qual quebrou
                log.exception("vertical: falha ao desenhar '%s'", tipo)
                continue
            if self._impressoes.get(tipo) == svg:
                continue
            self._impressoes[tipo] = svg
            escritos.append(escrever_texto(self.destino / f"{tipo}.svg", svg, nova_linha="\n"))

        escritos.append(self._lista())
        pagina = self.destino / "index.html"
        if not pagina.exists():
            escritos.append(escrever_texto(pagina, self.pagina(), nova_linha="\n"))
        return escritos

    def _lista(self) -> Path:
        corpo = {
            "atualizado_em": datetime.now().isoformat(timespec="seconds"),
            "rodizio_segundos": self.rodizio,
            "telas": [
                {"id": tipo, "titulo": TITULOS.get(tipo, tipo), "arquivo": f"{tipo}.svg"}
                for tipo in self.tipos
            ],
        }
        escrever_texto(
            self.destino / "telas.js",
            f"telaoVertical({json.dumps(corpo, ensure_ascii=False)});\n",
            nova_linha="\n",
        )
        return escrever_texto(
            self.destino / "telas.json",
            json.dumps(corpo, ensure_ascii=False, indent=2),
            nova_linha="\n",
        )

    def pagina(self) -> str:
        """A pagina do monitor: roda sozinha, sem ninguem operando.

        Diferente da tela do switcher, aqui NAO ha mesa e nao ha selecao para
        obedecer - o monitor fica em cena o tempo todo e ninguem vai ficar
        escolhendo. Ele gira, e so.

        O resto das travas e igual, pelos mesmos motivos: duas camadas em vez
        de recarregar (reload pisca branco, e isso estaria em quadro), falha
        mantem a tela que esta no ar (o monitor nao pode apagar atras do
        apresentador), e <script src> em vez de fetch, porque a pagina e
        aberta de uma pasta compartilhada em file://.

        A barra de progresso no rodape existe para quem esta no estudio saber
        quanto falta para a proxima troca - e nao ser pego trocando de tela no
        meio de uma fala.
        """
        fundo = str(self.cfg.aparencia.get("cor_fundo", "#0b1220"))
        return f"""<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<title>Monitor vertical — apuração TSE</title>
<style>
  html,body{{margin:0;height:100%;background:{fundo};overflow:hidden;cursor:none}}
  #palco{{position:fixed;inset:0}}
  #palco img{{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;
    opacity:0;transition:opacity .45s ease-in-out}}
  #palco img.ativo{{opacity:1}}
  #aviso{{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;
    color:#9fb0c9;font:30px "Barlow Condensed",Arial Narrow,sans-serif;letter-spacing:.1em}}
  #passo{{position:fixed;left:0;bottom:0;height:5px;background:#2f97e8;width:0;
    transition:width .95s linear;opacity:.55}}
  #estado{{position:fixed;left:10px;bottom:14px;font:13px ui-monospace,Menlo,monospace;
    color:#7d8aa0;display:none;white-space:pre}}
  body.debug #estado{{display:block}}
  body.debug{{cursor:default}}
</style>
<div id="palco"><img id="camadaA" alt=""><img id="camadaB" alt=""></div>
<div id="aviso">AGUARDANDO O PRIMEIRO BOLETIM</div>
<div id="passo"></div>
<div id="estado"></div>
<script>
(function () {{
  var RODIZIO = {self.rodizio};          // segundos por tela
  var LISTA = 5000;                      // relê a lista de telas
  var DESENHO = {max(2, self.cfg.intervalo_tela)} * 1000;

  var camadas = [document.getElementById("camadaA"), document.getElementById("camadaB")];
  var atual = 0, trocas = 0, falhas = 0, segundos = 0, indice = 0, parado = false;
  var telas = [], exibindo = "";
  var estado = document.getElementById("estado");
  var aviso = document.getElementById("aviso");
  var passo = document.getElementById("passo");

  if (location.search.indexOf("debug") >= 0) document.body.classList.add("debug");

  function anotar() {{
    estado.textContent = new Date().toLocaleTimeString("pt-BR")
      + "  |  " + (exibindo || "-") + "  " + (indice + 1) + "/" + telas.length
      + (parado ? "  (parado)" : "  (" + (RODIZIO - segundos) + "s)")
      + "  |  trocas: " + trocas + "  falhas: " + falhas;
  }}

  window.telaoVertical = function (lista) {{
    telas = lista.telas || [];
    if (telas.length && !exibindo) mostrar();
  }};

  function ler(arquivo) {{
    var no = document.createElement("script");
    no.src = arquivo + "?t=" + Date.now();
    no.onload = function () {{ no.parentNode && no.parentNode.removeChild(no); }};
    no.onerror = function () {{ falhas++; no.parentNode && no.parentNode.removeChild(no); }};
    document.head.appendChild(no);
  }}

  function mostrar() {{
    if (!telas.length) return;
    if (indice >= telas.length) indice = 0;
    exibindo = telas[indice].id;
    var proxima = camadas[1 - atual];
    proxima.onload = function () {{
      proxima.classList.add("ativo");
      camadas[atual].classList.remove("ativo");
      atual = 1 - atual;
      trocas++;
      aviso.style.display = "none";
      anotar();
    }};
    proxima.onerror = function () {{
      // mantem no ar o que ja esta: o monitor esta em quadro, apagar e pior
      falhas++;
      anotar();
    }};
    proxima.src = exibindo + ".svg?t=" + Date.now();
  }}

  function tique() {{
    if (parado) return;
    segundos++;
    passo.style.width = (100 * segundos / RODIZIO) + "%";
    if (segundos >= RODIZIO) {{
      segundos = 0;
      passo.style.width = "0";
      indice = (indice + 1) % Math.max(1, telas.length);
      mostrar();
    }}
    anotar();
  }}

  // Teclado so para conferencia no estudio - o monitor roda sozinho.
  document.addEventListener("keydown", function (e) {{
    if (e.key === " ") {{ parado = !parado; }}
    else if (e.key === "ArrowRight") {{ segundos = 0; indice++; mostrar(); }}
    else if (e.key === "ArrowLeft") {{
      segundos = 0; indice = (indice - 1 + telas.length) % Math.max(1, telas.length); mostrar();
    }} else if (e.key === "d" || e.key === "D") {{
      document.body.classList.toggle("debug");
    }}
    anotar();
  }});

  document.addEventListener("click", function () {{
    if (!document.fullscreenElement && document.documentElement.requestFullscreen) {{
      document.documentElement.requestFullscreen();
    }}
  }});

  ler("telas.js");
  setInterval(function () {{ ler("telas.js"); }}, LISTA);
  setInterval(tique, 1000);
  // relê o desenho da tela que está no ar, para pegar boletim novo sem esperar
  // a próxima troca do rodízio
  setInterval(function () {{ if (!parado) mostrar(); }}, DESENHO);
}})();
</script>
</html>
"""
