"""Telao: quadros de tela cheia com o dado do TSE, para um PC de exibicao.

A ideia, em uma frase: **o GC nao participa**. Cada quadro sai daqui como um
SVG 1920x1080 ja desenhado e pintado, reescrito a cada boletim. O PC de
exibicao mostra o quadro escolhido em tela cheia e sua saida de video entra no
switcher como uma fonte qualquer.

Isso existe porque a operacao do GC no dia estara ocupada com as tarjas. Cada
grafico montado no gerador de caracteres e mais um vinculo para conferir no
D-1 e mais uma coisa para dar errado no ar, competindo com o que o operador
precisa fazer ao vivo. O telao tira essa fila do caminho: nao ha vinculo, nao
ha cena, nao ha conta - ha um arquivo de imagem que se atualiza sozinho.

    dados/saida/telao/
        mapa-partido.svg     um por quadro configurado, reescrito por ciclo
        urnas.svg
        presidente.svg
        ...
        quadros.json         a lista, para a tela e a mesa saberem o que existe
        no-ar.json           qual quadro esta selecionado
        index.html           a tela de exibicao (escrita uma vez)

A selecao ('no-ar.json') e escrita pela mesa - 'gctse mesa', uma janela com um
botao por quadro - ou por 'gctse no-ar <id>', para quem prefere um atalho. A
tela de exibicao segue o arquivo, entao quem opera pode estar em outro PC,
desde que enxergue a pasta.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from .historico import Ponto, projecao
from .modelos import Apuracao
from .util.arquivos import escrever_texto
from .util.svg import (
    COR_APOIO,
    COR_DISCRETA,
    COR_FUNDO,
    COR_LINHA,
    COR_TEXTO,
    cor_de_reserva,
    escapar,
    int_br,
    mistura,
    pct_br,
    retangulo,
    texto,
)

log = logging.getLogger("gctse.telao")

LARGURA = 1920
ALTURA = 1080
MARGEM = 110.0

# Cores das fatias de composicao do voto. Ficam aqui, e nao na config, porque
# nao sao cor de partido: sao rotulos fixos do grafico, e trocar de cor entre
# um bloco e outro so confundiria quem esta assistindo.
COR_VALIDOS = "#4c6180"
COR_BRANCOS = "#d8dee9"
COR_NULOS = "#e8974a"
COR_ABSTENCAO = "#6b7688"
COR_ESCALA = "#2f97e8"

TIPOS = ("placar", "composicao", "contador", "curva", "mapa")


@dataclass
class Quadro:
    """Um quadro configurado: o que desenhar e de onde tirar o dado."""

    id: str
    tipo: str
    titulo: str = ""
    alvo: str = ""            # placar, composicao, contador, curva
    mapa: str = ""            # nome do grupo em 'mapas', para tipo 'mapa'
    limite: int = 6           # linhas do placar
    opcoes: dict[str, Any] = field(default_factory=dict)


def ler_quadros(config_telao: dict[str, Any]) -> list[Quadro]:
    """Le a secao 'telao' da config. Quadro invalido e descartado com aviso.

    Descartar em vez de abortar e deliberado: um erro de digitacao num quadro
    nao pode impedir o sistema de subir no dia da eleicao. O que sobra vai ao
    ar; o que caiu aparece no log e na validacao.
    """
    quadros: list[Quadro] = []
    vistos: set[str] = set()
    for item in config_telao.get("quadros") or []:
        if not isinstance(item, dict):
            continue
        tipo = str(item.get("tipo", "")).strip().lower()
        identificador = str(item.get("id") or "").strip() or tipo
        if tipo not in TIPOS:
            log.warning("telao: quadro '%s' com tipo desconhecido '%s' - ignorado",
                        identificador, tipo)
            continue
        if identificador in vistos:
            log.warning("telao: quadro '%s' repetido - so o primeiro vale", identificador)
            continue
        vistos.add(identificador)
        quadros.append(
            Quadro(
                id=identificador,
                tipo=tipo,
                titulo=str(item.get("titulo", "")),
                alvo=str(item.get("alvo", "")),
                mapa=str(item.get("mapa", "")),
                limite=int(item.get("limite_candidatos", 6)),
                opcoes={k: v for k, v in item.items()
                        if k not in ("id", "tipo", "titulo", "alvo", "mapa", "limite_candidatos")},
            )
        )
    return quadros


def problemas(config_telao: dict[str, Any], nomes_alvo: set[str], nomes_mapa: set[str]) -> list[str]:
    """Conferencia para o 'gctse validar': quadro apontando para o nada."""
    achados: list[str] = []
    for quadro in ler_quadros(config_telao):
        if quadro.tipo == "mapa":
            if not quadro.mapa:
                achados.append(f"telao: quadro '{quadro.id}' do tipo mapa sem 'mapa:'")
            elif quadro.mapa not in nomes_mapa:
                achados.append(
                    f"telao: quadro '{quadro.id}' cita mapa inexistente '{quadro.mapa}'"
                )
        elif not quadro.alvo:
            achados.append(f"telao: quadro '{quadro.id}' sem 'alvo:'")
        elif quadro.alvo not in nomes_alvo:
            achados.append(f"telao: quadro '{quadro.id}' cita alvo inexistente '{quadro.alvo}'")
    return achados


# ---------------------------------------------------------------------------
# Moldura comum
# ---------------------------------------------------------------------------


def _abrir(fonte: str, fundo: str) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {LARGURA} {ALTURA}" '
        f'width="{LARGURA}" height="{ALTURA}" font-family="{escapar(fonte)}">',
        retangulo(0, 0, LARGURA, ALTURA, fundo),
    ]


def _cabecalho(titulo: str, sub: str, selo: str) -> list[str]:
    titulo = (titulo or "").upper()
    # Titulo vem da config e pode ser longo: encolhe a fonte em vez de passar
    # por cima do selo de fase, que e o que nao pode ser encoberto.
    corpo = max(34, min(52, int(52 * 32 / max(len(titulo), 1))))
    partes = [texto(MARGEM, 86, titulo, tamanho=corpo, peso="700", espacamento="1")]
    if sub:
        partes.append(texto(MARGEM, 128, sub, tamanho=28, cor=COR_APOIO))
    if selo:
        largura = 34 + len(selo) * 16
        partes.append(retangulo(LARGURA - MARGEM - largura, 50, largura, 48, "#c0392b", raio=4))
        partes.append(
            texto(LARGURA - MARGEM - largura / 2, 83, selo, tamanho=26, peso="600", ancora="middle")
        )
    return partes


def _rodape(ap: Apuracao | None, extra: str = "") -> list[str]:
    linha = extra or "Fonte: TSE - boletim de urnas totalizadas"
    if ap is not None and ap.gerado_em:
        linha += f"  |  boletim das {ap.gerado_em.strftime('%H:%M:%S')}"
    return [texto(MARGEM, ALTURA - 44, linha, tamanho=20, cor=COR_DISCRETA)]


def _sem_dado(fonte: str, fundo: str, titulo: str, motivo: str) -> str:
    """Quadro sem boletim. Diz o que falta, em vez de sair preto.

    Preto no ar parece cabo solto e manda o operador procurar defeito no lugar
    errado. Uma linha dizendo 'aguardando boletim' resolve a duvida de quem
    esta no switcher sem custar nada.
    """
    partes = _abrir(fonte, fundo)
    partes += _cabecalho(titulo, "", "")
    partes.append(
        texto(MARGEM, ALTURA / 2, motivo, tamanho=44, cor=COR_APOIO)
    )
    partes.append("</svg>")
    return "\n".join(partes)


# ---------------------------------------------------------------------------
# Quadros
# ---------------------------------------------------------------------------


def desenhar_placar(quadro: Quadro, ap: Apuracao, cores: dict, fonte: str, fundo: str) -> str:
    """Placar de candidatos: nome, partido, barra, percentual e votos."""
    partes = _abrir(fonte, fundo)
    sub = f"{ap.abrangencia_nome}  |  {pct_br(ap.pct_secoes)}% das urnas totalizadas"
    partes += _cabecalho(quadro.titulo or ap.cargo_nome, sub, _selo(ap, quadro))

    candidatos = ap.candidatos[: max(1, quadro.limite)]
    if not candidatos:
        return _sem_dado(fonte, fundo, quadro.titulo or ap.cargo_nome, "aguardando boletim")

    # Distribui as linhas pela area util e centra o bloco: com 2 candidatos o
    # placar nao fica esparramado, com 8 nao fica apertado no topo.
    area_topo, area_base = 200.0, ALTURA - 120.0
    altura_linha = min(150.0, (area_base - area_topo) / len(candidatos))
    topo = area_topo + ((area_base - area_topo) - altura_linha * len(candidatos)) / 2 + 44
    trilho = 980.0
    trilho_x = 640.0
    # A barra e normalizada pelo LIDER, nao pelo total: em proporcional o
    # primeiro colocado fica na casa de 4% e uma barra sobre 100% seria um
    # traco invisivel. O numero ao lado continua sendo o percentual real.
    referencia = max((c.percentual for c in candidatos), default=0.0) or 100.0

    for indice, cand in enumerate(candidatos):
        y = topo + indice * altura_linha
        cor = _cor_partido(cand.partido, cores)
        fracao = max(0.0, min(1.0, cand.percentual / referencia))
        largura = max(6.0, trilho * fracao) if cand.percentual > 0 else 0.0

        partes.append(retangulo(MARGEM, y - 44, 10, 62, cor))
        partes.append(texto(MARGEM + 30, y, cand.nome, tamanho=38, peso="600"))
        if cand.partido:
            partes.append(texto(MARGEM + 30, y + 34, cand.partido, tamanho=24, cor=COR_APOIO))
        if cand.eleito:
            partes.append(retangulo(MARGEM + 30, y + 46, 116, 30, "#13341f", raio=3))
            partes.append(texto(MARGEM + 88, y + 68, "ELEITO", tamanho=21, cor="#5fce93",
                                peso="700", ancora="middle"))

        partes.append(retangulo(trilho_x, y - 34, trilho, 44, COR_LINHA, raio=2))
        partes.append(retangulo(trilho_x, y - 34, largura, 44, cor, raio=2))
        partes.append(
            texto(trilho_x + trilho + 30, y, f"{pct_br(cand.percentual)}%",
                  tamanho=44, peso="700")
        )
        partes.append(
            texto(trilho_x + trilho - 14, y + 44, int_br(cand.votos),
                  tamanho=24, cor=COR_APOIO, ancora="end")
        )

    partes += _rodape(ap, f"{int_br(ap.secoes_totalizadas)} de {int_br(ap.secoes_total)} urnas")
    partes.append("</svg>")
    return "\n".join(partes)


def desenhar_composicao(quadro: Quadro, ap: Apuracao, cores: dict, fonte: str, fundo: str) -> str:
    """Rosca de validos/brancos/nulos, com a abstencao fora dela."""
    if not ap.votos_apurados:
        return _sem_dado(fonte, fundo, quadro.titulo or "COMO O BRASIL VOTOU",
                         "aguardando boletim")

    partes = _abrir(fonte, fundo)
    sub = f"{ap.abrangencia_nome}  |  {pct_br(ap.pct_secoes)}% das urnas totalizadas"
    partes += _cabecalho(quadro.titulo or "COMO O BRASIL VOTOU", sub, _selo(ap, quadro))

    centro_x, centro_y, raio = 520.0, 620.0, 230.0
    circunferencia = 2 * 3.141592653589793 * raio
    fatias = (
        ("validos", ap.pct_validos, COR_VALIDOS, "Válidos", ap.votos_validos),
        ("brancos", ap.pct_brancos, COR_BRANCOS, "Brancos", ap.votos_brancos),
        ("nulos", ap.pct_nulos, COR_NULOS, "Nulos", ap.votos_nulos),
    )

    acumulado = 0.0
    for _chave, pct, cor, _rotulo, _votos in fatias:
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
    for _chave, pct, cor, rotulo, votos in fatias:
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

    partes += _rodape(ap)
    partes.append("</svg>")
    return "\n".join(partes)


def desenhar_contador(quadro: Quadro, ap: Apuracao, cores: dict, fonte: str, fundo: str) -> str:
    """O numero grande: quantas urnas ja foram totalizadas."""
    partes = _abrir(fonte, fundo)
    partes += _cabecalho(quadro.titulo or f"APURAÇÃO — {ap.abrangencia_nome}",
                         "atualiza sozinho a cada boletim", _selo(ap, quadro))

    partes.append(texto(MARGEM, 330, "URNAS TOTALIZADAS", tamanho=34, cor=COR_APOIO,
                        espacamento="6"))
    partes.append(texto(MARGEM, 500, int_br(ap.secoes_totalizadas), tamanho=170, peso="700"))
    partes.append(
        texto(MARGEM, 570, f"de {int_br(ap.secoes_total)}  ·  {pct_br(ap.pct_secoes)}%",
              tamanho=44, cor=COR_APOIO)
    )

    trilho, trilho_y = LARGURA - 2 * MARGEM, 660.0
    partes.append(retangulo(MARGEM, trilho_y, trilho, 30, COR_LINHA, raio=2))
    partes.append(
        retangulo(MARGEM, trilho_y, trilho * max(0.0, min(100.0, ap.pct_secoes)) / 100.0,
                  30, COR_ESCALA, raio=2)
    )

    partes.append(texto(MARGEM, 790, f"Faltam {int_br(ap.secoes_restantes)} urnas", tamanho=40))
    if ap.candidatos and len(ap.candidatos) > 1 and not ap.totalizada:
        recado = (
            f"Diferença de {int_br(ap.diferenca_lider)} votos"
            + ("  ·  ainda cabe no que falta apurar" if ap.reversivel
               else "  ·  maior do que o que falta apurar")
        )
        partes.append(texto(MARGEM, 850, recado, tamanho=30, cor=COR_APOIO))

    partes += _rodape(ap)
    partes.append("</svg>")
    return "\n".join(partes)


def desenhar_curva(quadro: Quadro, ap: Apuracao | None, pontos: list[Ponto],
                   fonte: str, fundo: str) -> str:
    """Ritmo da apuracao e previsao de fechamento.

    Quadro de gestao, nao de ar: responde a que horas as urnas terminam, no
    passo dos ultimos boletins. Nao diz nada sobre quem vence.
    """
    titulo = quadro.titulo or "RITMO DA APURAÇÃO"
    # Serie curta demais nao vira curva nem previsao. No inicio da noite o TSE
    # publica em rajada - varios boletins em poucos segundos -, e uma regressao
    # sobre isso devolve ritmos absurdos ("699 p.p./min") e um horario de
    # fechamento que nao significa nada. Melhor dizer que esta reunindo dado do
    # que por no ar uma projecao que o proprio relogio desmente.
    minimo = float(quadro.opcoes.get("minimo_minutos", 5))
    span = (
        (pontos[-1].instante - pontos[0].instante).total_seconds() / 60.0
        if len(pontos) >= 2 else 0.0
    )
    if len(pontos) < 3 or span < minimo:
        return _sem_dado(fonte, fundo, titulo, "reunindo boletins para traçar a curva")

    prev = projecao(pontos)
    partes = _abrir(fonte, fundo)
    sub = f"{pct_br(pontos[-1].pct)}% das urnas totalizadas"
    partes += _cabecalho(titulo, sub, _selo(ap, quadro) if ap else "")

    esq, dir_, topo, base = MARGEM + 80, 1300.0, 240.0, 860.0
    inicio = pontos[0].instante
    fim_minutos = max(1.0, (pontos[-1].instante - inicio).total_seconds() / 60.0)
    # O eixo reserva espaco para a projecao, senao a linha tracejada sairia do
    # quadro justamente no momento em que ela interessa. E cresce em degraus de
    # 30 min, com piso de 60: se a escala mudasse a cada boletim, a curva
    # inteira saltaria de lugar no video a cada 20 segundos.
    bruto = fim_minutos + max(5.0, (prev.get("minutos") or 0))
    escala_minutos = max(60.0, 30.0 * (int(bruto / 30.0) + 1))

    def px(minuto: float) -> float:
        return esq + (dir_ - esq) * min(1.0, minuto / escala_minutos)

    def py(pct: float) -> float:
        return base - (base - topo) * max(0.0, min(100.0, pct)) / 100.0

    for marca in (0, 25, 50, 75, 100):
        partes.append(
            f'<line x1="{esq:g}" y1="{py(marca):.1f}" x2="{dir_:g}" y2="{py(marca):.1f}" '
            f'stroke="{COR_LINHA}" stroke-width="1"/>'
        )
        partes.append(texto(esq - 18, py(marca) + 8, f"{marca}%", tamanho=24,
                            cor=COR_DISCRETA, ancora="end"))

    trilha = " ".join(
        f"{px((p.instante - inicio).total_seconds() / 60.0):.1f},{py(p.pct):.1f}"
        for p in pontos
    )
    partes.append(
        f'<polyline points="{trilha}" fill="none" stroke="{COR_ESCALA}" stroke-width="6" '
        f'stroke-linejoin="round" stroke-linecap="round"/>'
    )
    partes.append(
        f'<circle cx="{px(fim_minutos):.1f}" cy="{py(pontos[-1].pct):.1f}" r="10" '
        f'fill="{COR_ESCALA}"/>'
    )
    partes.append(texto(esq, base + 40, pontos[0].instante.strftime("%H:%M"),
                        tamanho=24, cor=COR_DISCRETA))
    # a hora do fim so aparece se nao for colidir com a do inicio
    if px(fim_minutos) - esq > 90:
        partes.append(texto(px(fim_minutos), base + 40, pontos[-1].instante.strftime("%H:%M"),
                            tamanho=24, cor=COR_DISCRETA, ancora="middle"))

    if prev.get("previsao") and prev.get("minutos"):
        x_fim = px(fim_minutos + prev["minutos"])
        partes.append(
            f'<polyline points="{px(fim_minutos):.1f},{py(pontos[-1].pct):.1f} '
            f'{x_fim:.1f},{py(100):.1f}" fill="none" stroke="{COR_ESCALA}" '
            f'stroke-width="5" stroke-dasharray="12 10" opacity="0.6"/>'
        )
        partes.append(
            f'<line x1="{x_fim:.1f}" y1="{topo - 40:g}" x2="{x_fim:.1f}" y2="{base:g}" '
            f'stroke="{COR_NULOS}" stroke-width="2" stroke-dasharray="7 7"/>'
        )
        partes.append(texto(x_fim - 10, topo - 50, f"PREVISÃO {prev['previsao']}",
                            tamanho=24, cor=COR_NULOS, ancora="end"))

    painel_x = 1420.0
    partes.append(texto(painel_x, 300, "NO RITMO ATUAL", tamanho=26, cor=COR_APOIO,
                        peso="600", espacamento="2"))
    partes.append(texto(painel_x, 400, prev.get("previsao") or "—", tamanho=96, peso="700"))
    partes.append(texto(painel_x, 444, "previsão de 100%", tamanho=26, cor=COR_APOIO))
    partes.append(
        texto(painel_x, 560, f"{pct_br(prev.get('pontos_por_minuto') or 0.0, 1)} p.p./min",
              tamanho=44, peso="600")
    )
    partes.append(texto(painel_x, 600, "ritmo dos últimos boletins", tamanho=24, cor=COR_APOIO))
    faltam = max(0, pontos[-1].secoes_total - pontos[-1].secoes_totalizadas)
    partes.append(texto(painel_x, 700, int_br(faltam), tamanho=44, peso="600"))
    partes.append(texto(painel_x, 740, "urnas que faltam", tamanho=24, cor=COR_APOIO))

    partes += _rodape(ap, "Projeção de ritmo, não de resultado")
    partes.append("</svg>")
    return "\n".join(partes)


def _cor_partido(partido: str, cores: dict) -> str:
    """Cor do partido, com paleta de reserva antes do cinza padrao.

    A ordem importa: num placar de tela cheia, cair no 'cor_padrao' deixaria
    todas as barras iguais, e barra da mesma cor para candidatos diferentes
    nao informa nada - e o telespectador le a cor antes de ler o nome. So com
    'paleta_reserva: false' o cinza padrao volta a valer, para quem prefere
    uma barra neutra a uma cor que a arte nao escolheu.
    """
    sigla = (partido or "").strip().upper()
    definida = (cores.get("cores_partido") or {}).get(sigla)
    if definida:
        return str(definida)
    if cores.get("paleta_reserva", True) and sigla:
        return cor_de_reserva(sum(ord(c) for c in sigla))
    return str(cores.get("cor_padrao") or cor_de_reserva(0))


def _selo(ap: Apuracao | None, quadro: Quadro) -> str:
    if ap is None or ap.oficial:
        return ""
    # Acento aqui e seguro: quem le e um navegador, nao um GC legado - por
    # isso o telao nao herda o 'selo_nao_oficial' da secao 'texto', que e
    # escrito sem acento de proposito para os exporters de arquivo.
    return str(quadro.opcoes.get("selo") or "PARCIAL — NÃO OFICIAL")


# ---------------------------------------------------------------------------
# Escrita do conjunto
# ---------------------------------------------------------------------------


def escrever_selecao(pasta: Path, identificador: str) -> Path:
    """Grava qual quadro esta no ar, nos DOIS formatos que o telao usa.

    Ponto unico de escrita de proposito: o .json e lido pela mesa e pelo
    monitoramento, o .js e o unico que a tela de exibicao consegue ler de
    file://. Escrever so um deles deixa a mesa e a tela discordando em
    silencio - a mesa mostra um quadro, o ar mostra outro.
    """
    corpo = {"quadro": identificador, "em": datetime.now().isoformat(timespec="seconds")}
    escrever_par_js(pasta / "no-ar.js", "gctseNoAr", corpo)
    return escrever_texto(
        pasta / "no-ar.json", json.dumps(corpo, ensure_ascii=False), nova_linha="\n"
    )


def escrever_par_js(caminho: Path, funcao: str, corpo: dict) -> Path:
    """Grava o mesmo dado do .json como uma CHAMADA DE FUNCAO em .js.

    Parece redundante e nao e. A tela de exibicao e aberta de uma pasta - por
    'file://', quase sempre uma pasta compartilhada do PC de operacao - e nessa
    origem o navegador bloqueia tanto 'fetch' quanto XMLHttpRequest, inclusive
    para um arquivo vizinho. Um <script src="..."> carrega sem esse bloqueio,
    entao a tela le a selecao por aqui.

    O .json continua existindo para tudo o mais: a mesa, o monitoramento, e
    qualquer coisa que leia o estado do telao de fora.
    """
    return escrever_texto(
        caminho,
        f"{funcao}({json.dumps(corpo, ensure_ascii=False)});\n",
        nova_linha="\n",
    )


class Telao:
    def __init__(self, cfg_telao: dict[str, Any], cfg_texto: dict[str, Any]):
        self.cfg = cfg_telao or {}
        self.ativo = bool(self.cfg.get("ativo", False))
        self.destino = Path(self.cfg.get("destino", "dados/saida/telao"))
        self.intervalo = int(self.cfg.get("intervalo_segundos", 8))
        self.fonte = str(
            self.cfg.get("fonte", "Barlow Condensed, Arial Narrow, Helvetica, sans-serif")
        )
        self.fundo = str(self.cfg.get("cor_fundo", COR_FUNDO))
        self.quadros = ler_quadros(self.cfg)
        self.cores = {
            "cores_partido": (cfg_texto or {}).get("cores_partido") or {},
            "cor_padrao": (cfg_texto or {}).get("cor_padrao") or "",
            "paleta_reserva": bool(self.cfg.get("paleta_reserva", True)),
        }
        self._impressoes: dict[str, str] = {}

    # --- selecao ---

    @property
    def arquivo_no_ar(self) -> Path:
        return self.destino / "no-ar.json"

    def no_ar(self) -> str:
        try:
            dados = json.loads(self.arquivo_no_ar.read_text(encoding="utf-8"))
            return str(dados.get("quadro", ""))
        except (OSError, json.JSONDecodeError, AttributeError):
            return ""

    def selecionar(self, identificador: str) -> None:
        escrever_selecao(self.destino, identificador)

    # --- ciclo ---

    def publicar(
        self,
        apuracoes: dict[str, Apuracao],
        mapas: dict[str, str],
        series: dict[str, list[Ponto]],
    ) -> list[Path]:
        """Reescreve os quadros que mudaram. Devolve o que foi gravado.

        'mapas' chega pronto (id do grupo -> SVG) porque quem monta o mapa e o
        exporter, no mesmo ciclo - redesenhar aqui seria fazer a mesma conta
        duas vezes e abrir espaco para as duas versoes discordarem.
        """
        if not self.ativo or not self.quadros:
            return []

        escritos: list[Path] = []
        for quadro in self.quadros:
            try:
                desenho = self._desenhar(quadro, apuracoes, mapas, series)
            except Exception:
                # Um quadro com defeito nao pode derrubar os outros nem o ciclo.
                log.exception("telao: falha ao desenhar o quadro '%s'", quadro.id)
                continue
            if desenho is None:
                continue
            # dedupe proprio: sem isso a tela recarregaria um desenho igual a
            # cada ciclo, e o PC de exibicao redecodificaria o SVG a toa
            if self._impressoes.get(quadro.id) == desenho:
                continue
            self._impressoes[quadro.id] = desenho
            escritos.append(
                escrever_texto(self.destino / f"{quadro.id}.svg", desenho, nova_linha="\n")
            )

        escritos.append(self._escrever_lista())
        pagina = self.destino / "index.html"
        if not pagina.exists():
            escritos.append(escrever_texto(pagina, self.pagina(), nova_linha="\n"))
        # Primeiro quadro como padrao - e tambem o reparo do par .js quando so
        # o .json existe (telao de uma versao anterior, ou arquivo apagado a
        # mao): sem o .js a tela nao consegue ler a selecao em file://.
        if self.quadros and not (self.destino / "no-ar.js").exists():
            self.selecionar(self.no_ar() or self.quadros[0].id)
        return escritos

    def _desenhar(
        self,
        quadro: Quadro,
        apuracoes: dict[str, Apuracao],
        mapas: dict[str, str],
        series: dict[str, list[Ponto]],
    ) -> str | None:
        if quadro.tipo == "mapa":
            return mapas.get(quadro.mapa)

        ap = apuracoes.get(quadro.alvo)
        if quadro.tipo == "curva":
            pontos = series.get(quadro.alvo) or []
            return desenhar_curva(quadro, ap, pontos, self.fonte, self.fundo)
        if ap is None:
            return _sem_dado(self.fonte, self.fundo, quadro.titulo or quadro.id,
                             "aguardando boletim")
        if quadro.tipo == "placar":
            return desenhar_placar(quadro, ap, self.cores, self.fonte, self.fundo)
        if quadro.tipo == "composicao":
            return desenhar_composicao(quadro, ap, self.cores, self.fonte, self.fundo)
        if quadro.tipo == "contador":
            return desenhar_contador(quadro, ap, self.cores, self.fonte, self.fundo)
        return None

    def _escrever_lista(self) -> Path:
        corpo = {
            "atualizado_em": datetime.now().isoformat(timespec="seconds"),
            "intervalo_segundos": self.intervalo,
            "quadros": [
                {"id": q.id, "tipo": q.tipo, "titulo": q.titulo or q.id, "arquivo": f"{q.id}.svg"}
                for q in self.quadros
            ],
        }
        escrever_par_js(self.destino / "quadros.js", "gctseQuadros", corpo)
        return escrever_texto(
            self.destino / "quadros.json",
            json.dumps(corpo, ensure_ascii=False, indent=2),
            nova_linha="\n",
        )

    # --- tela de exibicao ---

    def pagina(self) -> str:
        """A tela do PC de exibicao. Escrita uma vez; o conteudo e que muda.

        Segue 'no-ar.json', entao quem escolhe o quadro pode estar em outro PC.
        Tambem aceita teclado (1-9, setas, R para rodizio), para o caso de
        quem opera estar sentado na propria maquina de exibicao.

        As tres travas de sempre, pelos mesmos motivos do mapa: duas camadas em
        vez de recarregar (reload pisca branco), falha mantem o quadro no ar
        (pasta de rede oscila), e <img> em vez de fetch para o SVG (o navegador
        bloqueia fetch em file://, que e como este arquivo sera aberto).
        """
        return f"""<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<title>Telão - apuração TSE</title>
<style>
  html,body{{margin:0;height:100%;background:{self.fundo};overflow:hidden;cursor:none}}
  #palco{{position:fixed;inset:0}}
  #palco img{{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;
    opacity:0;transition:opacity .28s linear}}
  #palco img.ativo{{opacity:1}}
  #aviso{{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;
    color:#9fb0c9;font:28px "Barlow Condensed",Arial Narrow,sans-serif;letter-spacing:.08em}}
  #estado{{position:fixed;left:8px;bottom:6px;font:12px ui-monospace,Menlo,monospace;
    color:#7d8aa0;display:none;white-space:pre}}
  body.debug #estado{{display:block}}
  body.debug{{cursor:default}}
</style>
<div id="palco"><img id="camadaA" alt=""><img id="camadaB" alt=""></div>
<div id="aviso">AGUARDANDO O PRIMEIRO BOLETIM</div>
<div id="estado"></div>
<script>
(function () {{
  // Duas urgencias diferentes, dois relogios:
  //   SELECAO  quem clica na mesa espera o quadro entrar agora, nao no
  //            proximo ciclo - e o arquivo lido tem 60 bytes
  //   DESENHO  o SVG so muda quando chega boletim novo, entao reler no
  //            intervalo configurado basta e poupa decodificacao
  var SELECAO = 1000;
  var DESENHO = {max(2, self.intervalo)} * 1000;

  var camadas = [document.getElementById("camadaA"), document.getElementById("camadaB")];
  var atual = 0, trocas = 0, falhas = 0;
  var estado = document.getElementById("estado");
  var aviso = document.getElementById("aviso");
  var quadros = [], escolhido = "", manual = false, rodizio = 0, passo = 0;

  if (location.search.indexOf("debug") >= 0) document.body.classList.add("debug");

  function anotar(texto) {{
    estado.textContent = texto
      + "  |  quadro: " + (escolhido || "-")
      + (rodizio ? "  (rodizio " + rodizio + "s)" : manual ? "  (teclado)" : "  (mesa)")
      + "  |  trocas: " + trocas + "  falhas: " + falhas;
  }}

  // A tela e aberta de file:// (pasta compartilhada), e nessa origem o
  // navegador bloqueia fetch E XMLHttpRequest, inclusive para o arquivo
  // vizinho. <script src> nao passa por esse bloqueio - por isso o telao
  // grava 'quadros.js' e 'no-ar.js' com o mesmo conteudo dos .json.
  window.gctseQuadros = function (lista) {{
    quadros = lista.quadros || [];
    if (!escolhido && quadros.length) trocarPara(quadros[0].id);
  }};
  window.gctseNoAr = function (sel) {{
    if (manual || rodizio || !sel.quadro) return;
    if (sel.quadro !== escolhido) trocarPara(sel.quadro);
  }};

  function ler(arquivo) {{
    var no = document.createElement("script");
    no.src = arquivo + "?t=" + Date.now();
    no.onload = function () {{ no.parentNode && no.parentNode.removeChild(no); }};
    no.onerror = function () {{
      falhas++;
      no.parentNode && no.parentNode.removeChild(no);
    }};
    document.head.appendChild(no);
  }}

  function trocarPara(id) {{
    escolhido = id;
    mostrar();
  }}

  function mostrar() {{
    if (!escolhido) return;
    var proxima = camadas[1 - atual];
    proxima.onload = function () {{
      proxima.classList.add("ativo");
      camadas[atual].classList.remove("ativo");
      atual = 1 - atual;
      trocas++;
      aviso.style.display = "none";
      anotar(new Date().toLocaleTimeString("pt-BR"));
    }};
    proxima.onerror = function () {{
      // mantem o que ja esta no ar: melhor um quadro atrasado do que tela preta
      falhas++;
      anotar("falha as " + new Date().toLocaleTimeString("pt-BR"));
    }};
    proxima.src = escolhido + ".svg?t=" + Date.now();
  }}

  function conferirSelecao() {{
    ler("quadros.js");
    if (rodizio) {{
      passo += SELECAO / 1000;
      if (passo >= rodizio && quadros.length) {{
        passo = 0;
        var i = quadros.findIndex(function (q) {{ return q.id === escolhido; }});
        trocarPara(quadros[(i + 1) % quadros.length].id);
      }}
      return;
    }}
    if (!manual) ler("no-ar.js");
  }}

  function indiceAtual() {{
    return quadros.findIndex(function (q) {{ return q.id === escolhido; }});
  }}

  document.addEventListener("keydown", function (e) {{
    if (e.key >= "1" && e.key <= "9") {{
      var n = parseInt(e.key, 10) - 1;
      if (quadros[n]) {{ manual = true; rodizio = 0; trocarPara(quadros[n].id); }}
    }} else if (e.key === "ArrowRight" && quadros.length) {{
      manual = true; rodizio = 0;
      trocarPara(quadros[(indiceAtual() + 1) % quadros.length].id);
    }} else if (e.key === "ArrowLeft" && quadros.length) {{
      manual = true; rodizio = 0;
      trocarPara(quadros[(indiceAtual() - 1 + quadros.length) % quadros.length].id);
    }} else if (e.key === "r" || e.key === "R") {{
      rodizio = rodizio ? 0 : 20; passo = 0; manual = false;
    }} else if (e.key === "m" || e.key === "M") {{
      manual = false; rodizio = 0;      // devolve o comando para a mesa
      ler("no-ar.js");
    }} else if (e.key === "d" || e.key === "D") {{
      document.body.classList.toggle("debug");
    }}
    anotar(new Date().toLocaleTimeString("pt-BR"));
  }});

  document.addEventListener("click", function () {{
    if (!document.fullscreenElement && document.documentElement.requestFullscreen) {{
      document.documentElement.requestFullscreen();
    }}
  }});

  conferirSelecao();
  setInterval(conferirSelecao, SELECAO);
  setInterval(mostrar, DESENHO);
}})();
</script>
</html>
"""
