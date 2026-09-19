"""As telas do telao, cada uma num SVG de 1920x1080.

Seis telas:

  lideranca          mapa do Brasil pintado pela cor do partido de quem lidera
                     cada estado, com a contagem de estados por partido
  estados            o mesmo mapa, com a lista das 27 UFs ao lado: quem venceu
                     em cada uma, a sigla e o percentual
  como-votou         validos, brancos, nulos e abstencao - a composicao do voto
  apuracao-nacional  o contador de urnas do pais, em numero grande
  apuracao-estados   o mapa pintado pelo percentual de urnas totalizadas, com
                     o total apurado e as urnas apuradas praca a praca
  placar             os candidatos, com barra, percentual e votos

Todas sao desenhadas do zero a cada mudanca de boletim e gravadas inteiras -
nao ha estado parcial em disco. Praca sem boletim aparece em cinza com a sigla
legivel: buraco no mapa parece erro de arte no ar, cinza informa que o dado
ainda nao chegou.
"""

from __future__ import annotations

import logging
from typing import Any

from gctse.exporters.mapa import ExporterMapa
from gctse.historico import Ponto, projecao
from gctse.malha_br import CENTRO, CONTORNO, CREDITO, LEGENDA_EXTERNA, NOMES
from gctse.modelos import Apuracao
from gctse.util.svg import (
    COR_APOIO,
    COR_DISCRETA,
    COR_FUNDO,
    COR_LINHA,
    COR_TEXTO,
    contraste,
    cor_de_reserva,
    escapar,
    int_br,
    pct_br,
    retangulo,
    texto,
)

from .config import Config, Tela

log = logging.getLogger("telao.telas")

LARGURA = 1920
ALTURA = 1080
MARGEM = 110.0

COR_VALIDOS = "#4c6180"
COR_BRANCOS = "#d8dee9"
COR_NULOS = "#e8974a"
COR_ESCALA = "#2f97e8"
COR_ELEITO = "#5fce93"

SELO_PADRAO = "PARCIAL — NÃO OFICIAL"


# ---------------------------------------------------------------------------
# Moldura comum
# ---------------------------------------------------------------------------


class Moldura:
    """Cabecalho, rodape e fundo - iguais em todas as telas.

    Uma moldura so, e nao uma por tela, porque o telespectador precisa
    reconhecer que os seis quadros sao do mesmo bloco: mesmo lugar do titulo,
    mesmo lugar do selo, mesmo rodape.
    """

    def __init__(self, cfg: Config):
        aparencia = cfg.aparencia
        self.fonte = str(
            aparencia.get("fonte", "Barlow Condensed, Arial Narrow, Helvetica, sans-serif")
        )
        self.fundo = str(aparencia.get("cor_fundo", COR_FUNDO))
        self.selo_texto = str(aparencia.get("selo_nao_oficial", SELO_PADRAO))
        self.cores_partido = {
            str(k).strip().upper(): str(v)
            for k, v in (aparencia.get("cores_partido") or {}).items()
        }
        self.cor_padrao = str(aparencia.get("cor_padrao", ""))
        self.paleta_reserva = bool(aparencia.get("paleta_reserva", True))
        self.credito = bool(aparencia.get("credito_malha", True))

    def abrir(self) -> list[str]:
        return [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {LARGURA} {ALTURA}" '
            f'width="{LARGURA}" height="{ALTURA}" font-family="{escapar(self.fonte)}">',
            retangulo(0, 0, LARGURA, ALTURA, self.fundo),
        ]

    def cabecalho(self, titulo: str, sub: str = "", selo: str = "") -> list[str]:
        titulo = (titulo or "").upper()
        # O titulo vem da config e pode ser longo: encolhe a fonte em vez de
        # passar por cima do selo, que e o que nao pode ser encoberto.
        corpo = max(34, min(52, int(52 * 32 / max(len(titulo), 1))))
        partes = [texto(MARGEM, 86, titulo, tamanho=corpo, peso="700", espacamento="1")]
        if sub:
            partes.append(texto(MARGEM, 128, sub, tamanho=28, cor=COR_APOIO))
        if selo:
            largura = 34 + len(selo) * 16
            partes.append(retangulo(LARGURA - MARGEM - largura, 50, largura, 48, "#c0392b", raio=4))
            partes.append(
                texto(LARGURA - MARGEM - largura / 2, 83, selo, tamanho=26, peso="600",
                      ancora="middle")
            )
        return partes

    def rodape(self, ap: Apuracao | None, nota: str = "", com_malha: bool = False) -> list[str]:
        linha = nota or "Fonte: TSE — Divulgação de Resultados"
        if ap is not None and ap.gerado_em:
            linha += f"  |  boletim das {ap.gerado_em.strftime('%H:%M:%S')}"
        partes = [texto(MARGEM, ALTURA - 44, linha, tamanho=20, cor=COR_DISCRETA)]
        if com_malha and self.credito:
            partes.append(
                texto(LARGURA - MARGEM, ALTURA - 44, CREDITO, tamanho=18,
                      cor=COR_DISCRETA, ancora="end")
            )
        return partes

    def selo(self, ap: Apuracao | None) -> str:
        return "" if (ap is None or ap.oficial) else self.selo_texto

    def cor_partido(self, sigla: str) -> str:
        sigla = (sigla or "").strip().upper()
        if sigla in self.cores_partido:
            return self.cores_partido[sigla]
        if self.paleta_reserva and sigla:
            return cor_de_reserva(sum(ord(c) for c in sigla))
        return self.cor_padrao or cor_de_reserva(0)

    def aviso(self, titulo: str, motivo: str) -> str:
        """Tela sem dado: diz o que falta, em vez de sair preta.

        Preto no ar parece cabo solto e manda o operador procurar defeito no
        lugar errado.
        """
        partes = self.abrir()
        partes += self.cabecalho(titulo)
        partes.append(texto(MARGEM, ALTURA / 2, motivo, tamanho=44, cor=COR_APOIO))
        partes.append("</svg>")
        return "\n".join(partes)

    def fechar(self, partes: list[str]) -> str:
        partes.append("</svg>")
        return "\n".join(partes)


# ---------------------------------------------------------------------------
# O mapa, e os numeros por estado
# ---------------------------------------------------------------------------


class Mapa:
    """Ponte para o desenho de mapa ja testado do gctse.

    O gctse desenha o mesmo mapa para o hot folder do GC. Reusar aqui, em vez
    de escrever um segundo, evita o pior defeito possivel nesse tipo de
    sistema: o mapa da tarja e o mapa do telao discordando sobre quem venceu
    num estado, ao vivo, no mesmo bloco.
    """

    def __init__(self, moldura: Moldura, cfg: Config):
        self.moldura = moldura
        self.cfg = cfg

    def _exportador(self, modo: str, titulo: str) -> ExporterMapa:
        return ExporterMapa(
            nome="telao",
            opcoes={
                "tipo": "mapa",
                "modo": modo,
                "titulo": titulo,
                "formatos": [],
                "fonte": self.moldura.fonte,
                "cor_fundo": self.moldura.fundo,
                "cor_escala": str(self.cfg.aparencia.get("cor_escala", COR_ESCALA)),
                "paleta_reserva": self.moldura.paleta_reserva,
            },
            cfg_texto={
                "caixa": "alta",
                "formatar_numeros": True,
                "cores_partido": self.moldura.cores_partido,
                "cor_padrao": self.moldura.cor_padrao,
                "selo_nao_oficial": self.moldura.selo_texto,
            },
            cfg_saida={},
        )

    def itens(self, estados: dict[str, Apuracao]) -> list[tuple[int, str, Apuracao | None]]:
        return [
            (ordem, sigla, estados.get(sigla))
            for ordem, sigla in enumerate(sorted(CONTORNO), start=1)
        ]

    def dados(self, estados: dict[str, Apuracao], modo: str = "partido") -> dict:
        return self._exportador(modo, "").montar(self.itens(estados))

    def desenhar(self, estados: dict[str, Apuracao], modo: str, titulo: str) -> str:
        exportador = self._exportador(modo, titulo)
        return exportador.desenhar(exportador.montar(self.itens(estados)))


def _mapa_reduzido(dados: dict, x: float, y: float, escala: float) -> list[str]:
    """Desenha o mapa num canto, para a tela que divide espaco com uma lista."""
    estados = dados["estados"]
    partes = [f'<g transform="translate({x:g},{y:g}) scale({escala:g})">']
    for sigla in sorted(CONTORNO):
        cor = (estados.get(sigla) or {}).get("cor", "#6b7688")
        partes.append(
            f'<path d="{CONTORNO[sigla]}" fill="{cor}" stroke="#0b1220" '
            f'stroke-width="1.2" stroke-linejoin="round"/>'
        )
    partes.append("</g>")

    # Sigla so onde cabe: no mapa reduzido os estados pequenos ja sao
    # ilegiveis, e a lista ao lado os cobre.
    for sigla in sorted(CONTORNO):
        if sigla in LEGENDA_EXTERNA:
            continue
        estado = estados.get(sigla) or {}
        cx, cy = CENTRO[sigla]
        partes.append(
            texto(x + cx * escala, y + cy * escala + 8, sigla, tamanho=22, peso="700",
                  cor=contraste(estado.get("cor", "#6b7688")), ancora="middle")
        )
    return partes


# ---------------------------------------------------------------------------
# As telas
# ---------------------------------------------------------------------------


def tela_lideranca(moldura: Moldura, mapa: Mapa, tela: Tela, dados) -> str:
    """Mapa do Brasil pintado pela cor do partido de quem lidera cada estado."""
    if not dados.estados:
        return moldura.aviso(tela.titulo or "LIDERANÇA POR ESTADO", "aguardando boletim")
    return mapa.desenhar(dados.estados, "partido", tela.titulo or "LIDERANÇA POR ESTADO")


def tela_apuracao_estados(moldura: Moldura, mapa: Mapa, tela: Tela, dados) -> str:
    """O mesmo mapa, pintado pelo percentual de urnas totalizadas."""
    if not dados.estados:
        return moldura.aviso(tela.titulo or "APURAÇÃO POR ESTADO", "aguardando boletim")
    return mapa.desenhar(dados.estados, "apuracao", tela.titulo or "APURAÇÃO POR ESTADO")


def tela_estados(moldura: Moldura, mapa: Mapa, tela: Tela, dados) -> str:
    """Mapa + as 27 UFs listadas: quem venceu, o partido e o percentual.

    O mapa responde de longe ('o Sul esta de uma cor so'); a lista responde de
    perto ('quem ganhou em Sergipe'). Juntos cobrem as duas perguntas que o
    apresentador faz sobre o mesmo quadro.
    """
    if not dados.estados:
        return moldura.aviso(tela.titulo or "COMO CADA ESTADO VOTOU", "aguardando boletim")

    mapa_dados = mapa.dados(dados.estados, "partido")
    partes = moldura.abrir()
    com_dado = mapa_dados["pracas_com_dado"]
    partes += moldura.cabecalho(
        tela.titulo or "COMO CADA ESTADO VOTOU",
        f"{com_dado} de 27 estados com boletim publicado",
        moldura.selo(dados.nacional),
    )
    partes += _mapa_reduzido(mapa_dados, 40.0, 185.0, 1.26)

    # Duas colunas de 14 linhas cobrem as 27 UFs sem rolagem e sem apertar.
    coluna_x = (880.0, 1400.0)
    largura_coluna = 430.0
    topo, passo = 210.0, 60.0
    for indice, sigla in enumerate(sorted(CONTORNO)):
        estado = mapa_dados["estados"][sigla]
        x = coluna_x[indice // 14]
        y = topo + (indice % 14) * passo
        lider = estado.get("lider") or {}
        cor = estado.get("cor", "#6b7688")

        partes.append(retangulo(x, y - 26, 8, 34, cor))
        partes.append(texto(x + 22, y, sigla, tamanho=30, peso="700"))
        if estado.get("visivel") and lider:
            partes.append(
                texto(x + 86, y, lider.get("partido") or "—", tamanho=28, cor=COR_APOIO)
            )
            partes.append(
                texto(x + largura_coluna, y, f"{pct_br(lider.get('percentual', 0.0))}%",
                      tamanho=28, peso="600", ancora="end")
            )
            if lider.get("eleito"):
                partes.append(
                    texto(x + largura_coluna - 100, y, "ELEITO", tamanho=19, cor=COR_ELEITO,
                          peso="700", ancora="end")
                )
        else:
            partes.append(texto(x + 86, y, "aguardando", tamanho=26, cor=COR_DISCRETA))

    partes += moldura.rodape(dados.nacional, com_malha=True)
    return moldura.fechar(partes)


def tela_como_votou(moldura: Moldura, tela: Tela, dados) -> str:
    """Validos, brancos e nulos numa rosca; abstencao fora dela."""
    ap = dados.nacional
    titulo = tela.titulo or "COMO O BRASIL VOTOU"
    if ap is None or not ap.votos_apurados:
        return moldura.aviso(titulo, "aguardando boletim")

    partes = moldura.abrir()
    partes += moldura.cabecalho(
        titulo,
        f"{ap.abrangencia_nome}  |  {pct_br(ap.pct_secoes)}% das urnas totalizadas",
        moldura.selo(ap),
    )

    centro_x, centro_y, raio = 520.0, 620.0, 230.0
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
            f'stroke="{cor}" stroke-width="104" '
            f'stroke-dasharray="{arco:.2f} {circunferencia - arco:.2f}" '
            f'stroke-dashoffset="{-circunferencia * acumulado / 100.0:.2f}" '
            f'transform="rotate(-90 {centro_x:g} {centro_y:g})"/>'
        )
        acumulado += pct

    partes.append(texto(centro_x, centro_y - 6, f"{pct_br(ap.pct_brancos_nulos)}%",
                        tamanho=84, peso="700", ancora="middle"))
    partes.append(texto(centro_x, centro_y + 46, "BRANCOS + NULOS", tamanho=26,
                        cor=COR_APOIO, ancora="middle", espacamento="2"))

    painel_x, y = 1010.0, 330.0
    for pct, cor, rotulo, votos in fatias:
        partes.append(retangulo(painel_x, y - 26, 30, 30, cor, raio=3))
        partes.append(texto(painel_x + 50, y, rotulo, tamanho=38, peso="600"))
        partes.append(texto(painel_x + 480, y, f"{pct_br(pct)}%", tamanho=38,
                            cor=COR_APOIO, ancora="end"))
        partes.append(texto(LARGURA - MARGEM, y, int_br(votos), tamanho=38, ancora="end"))
        y += 84

    partes.append(retangulo(painel_x, y - 6, LARGURA - MARGEM - painel_x, 1, COR_LINHA))
    y += 56
    partes.append(texto(painel_x + 50, y, "Abstenção", tamanho=38, peso="600"))
    partes.append(texto(painel_x + 480, y, f"{pct_br(ap.pct_abstencao)}%", tamanho=38,
                        cor=COR_APOIO, ancora="end"))
    partes.append(texto(LARGURA - MARGEM, y, int_br(ap.abstencao), tamanho=38, ancora="end"))
    # Duas linhas: em uma so, esta nota saía pela borda direita da tela.
    partes.append(texto(painel_x + 50, y + 50, "Válidos, brancos e nulos sobre os votos",
                        tamanho=22, cor=COR_DISCRETA))
    partes.append(texto(painel_x + 50, y + 78, "apurados. Abstenção sobre o eleitorado apto.",
                        tamanho=22, cor=COR_DISCRETA))

    partes += moldura.rodape(ap)
    return moldura.fechar(partes)


def tela_apuracao_nacional(moldura: Moldura, tela: Tela, dados) -> str:
    """O contador de urnas do pais, em numero grande."""
    ap = dados.nacional
    titulo = tela.titulo or "APURAÇÃO NACIONAL"
    totalizadas, total = dados.total_secoes
    if not total:
        return moldura.aviso(titulo, "aguardando boletim")

    pct = round(100.0 * totalizadas / total, 2) if total else 0.0
    parcial = ap is None      # sem o arquivo nacional, o numero e soma de UFs
    partes = moldura.abrir()
    partes += moldura.cabecalho(
        titulo,
        "soma das praças com boletim" if parcial else "atualiza sozinho a cada boletim",
        moldura.selo(ap),
    )

    partes.append(texto(MARGEM, 330, "URNAS TOTALIZADAS", tamanho=34, cor=COR_APOIO,
                        espacamento="6"))
    partes.append(texto(MARGEM, 500, int_br(totalizadas), tamanho=170, peso="700"))
    partes.append(texto(MARGEM, 570, f"de {int_br(total)}  ·  {pct_br(pct)}%",
                        tamanho=44, cor=COR_APOIO))

    trilho = LARGURA - 2 * MARGEM
    partes.append(retangulo(MARGEM, 660, trilho, 30, COR_LINHA, raio=2))
    partes.append(retangulo(MARGEM, 660, trilho * max(0.0, min(100.0, pct)) / 100.0, 30,
                            COR_ESCALA, raio=2))
    partes.append(texto(MARGEM, 790, f"Faltam {int_br(max(0, total - totalizadas))} urnas",
                        tamanho=40))

    if ap is not None and len(ap.candidatos) > 1 and not ap.totalizada:
        recado = (
            f"Diferença de {int_br(ap.diferenca_lider)} votos"
            + ("  ·  ainda cabe no que falta apurar" if ap.reversivel
               else "  ·  maior do que o que falta apurar")
        )
        partes.append(texto(MARGEM, 850, recado, tamanho=30, cor=COR_APOIO))

    partes += moldura.rodape(ap)
    return moldura.fechar(partes)


def tela_placar(moldura: Moldura, tela: Tela, dados) -> str:
    """Os candidatos, com barra, percentual e votos."""
    ap = dados.nacional
    titulo = tela.titulo or (ap.cargo_nome if ap else "PLACAR")
    if ap is None or not ap.candidatos:
        return moldura.aviso(titulo, "aguardando boletim")

    limite = int(tela.opcoes.get("limite_candidatos", 6))
    candidatos = ap.candidatos[: max(1, limite)]

    partes = moldura.abrir()
    partes += moldura.cabecalho(
        titulo,
        f"{ap.abrangencia_nome}  |  {pct_br(ap.pct_secoes)}% das urnas totalizadas",
        moldura.selo(ap),
    )

    # Distribui as linhas pela area util e centra o bloco: com 2 candidatos o
    # placar nao fica esparramado, com 8 nao fica apertado no topo.
    area_topo, area_base = 200.0, ALTURA - 120.0
    altura_linha = min(150.0, (area_base - area_topo) / len(candidatos))
    topo = area_topo + ((area_base - area_topo) - altura_linha * len(candidatos)) / 2 + 44
    trilho, trilho_x = 980.0, 640.0
    # Barra normalizada pelo LIDER: em proporcional o primeiro colocado fica na
    # casa de 4% e uma barra sobre 100% seria um traco invisivel. O numero ao
    # lado continua sendo o percentual real.
    referencia = max((c.percentual for c in candidatos), default=0.0) or 100.0

    for indice, cand in enumerate(candidatos):
        y = topo + indice * altura_linha
        cor = moldura.cor_partido(cand.partido)
        fracao = max(0.0, min(1.0, cand.percentual / referencia))
        largura = max(6.0, trilho * fracao) if cand.percentual > 0 else 0.0

        partes.append(retangulo(MARGEM, y - 44, 10, 62, cor))
        partes.append(texto(MARGEM + 30, y, cand.nome, tamanho=38, peso="600"))
        if cand.partido:
            partes.append(texto(MARGEM + 30, y + 34, cand.partido, tamanho=24, cor=COR_APOIO))
        if cand.eleito:
            partes.append(retangulo(MARGEM + 30, y + 46, 116, 30, "#13341f", raio=3))
            partes.append(texto(MARGEM + 88, y + 68, "ELEITO", tamanho=21, cor=COR_ELEITO,
                                peso="700", ancora="middle"))
        partes.append(retangulo(trilho_x, y - 34, trilho, 44, COR_LINHA, raio=2))
        partes.append(retangulo(trilho_x, y - 34, largura, 44, cor, raio=2))
        partes.append(texto(trilho_x + trilho + 30, y, f"{pct_br(cand.percentual)}%",
                            tamanho=44, peso="700"))
        partes.append(texto(trilho_x + trilho - 14, y + 44, int_br(cand.votos),
                            tamanho=24, cor=COR_APOIO, ancora="end"))

    totalizadas, total = dados.total_secoes
    partes += moldura.rodape(ap, f"{int_br(totalizadas)} de {int_br(total)} urnas")
    return moldura.fechar(partes)


# ---------------------------------------------------------------------------
# Despacho
# ---------------------------------------------------------------------------


class Dados:
    """O que as telas leem do coletor, sem conhecer o coletor."""

    def __init__(self, nacional: Apuracao | None, estados: dict[str, Apuracao],
                 serie: list[Ponto], total_secoes: tuple[int, int]):
        self.nacional = nacional
        self.estados = estados
        self.serie = serie
        self.total_secoes = total_secoes

    @classmethod
    def do_coletor(cls, coletor) -> "Dados":
        return cls(
            nacional=coletor.nacional,
            estados=dict(coletor.estados),
            serie=coletor.serie.get("nacional", []),
            total_secoes=coletor.total_secoes(),
        )


def desenhar(cfg: Config, tela: Tela, dados: Dados) -> str:
    """Devolve o SVG da tela pedida."""
    moldura = Moldura(cfg)
    mapa = Mapa(moldura, cfg)

    if tela.tipo == "lideranca":
        return tela_lideranca(moldura, mapa, tela, dados)
    if tela.tipo == "estados":
        return tela_estados(moldura, mapa, tela, dados)
    if tela.tipo == "apuracao-estados":
        return tela_apuracao_estados(moldura, mapa, tela, dados)
    if tela.tipo == "como-votou":
        return tela_como_votou(moldura, tela, dados)
    if tela.tipo == "apuracao-nacional":
        return tela_apuracao_nacional(moldura, tela, dados)
    if tela.tipo == "placar":
        return tela_placar(moldura, tela, dados)
    raise ValueError(f"tipo de tela desconhecido: {tela.tipo!r}")


def resumo(dados: Dados) -> dict[str, Any]:
    """Numeros do ciclo, para o log e para a conferencia."""
    totalizadas, total = dados.total_secoes
    return {
        "estados_com_boletim": len(dados.estados),
        "secoes_totalizadas": totalizadas,
        "secoes_total": total,
        "pct": round(100.0 * totalizadas / total, 2) if total else 0.0,
        "nacional": dados.nacional is not None,
        "projecao": projecao(dados.serie) if dados.serie else {},
    }
