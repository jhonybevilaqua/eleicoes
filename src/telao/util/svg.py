"""Pecas comuns de quem desenha SVG para o ar: texto, numero e cor.

Separado do mapa porque o telao desenha os mesmos tipos de coisa - titulo,
percentual, fatia colorida - e duas copias dessas funcoes divergiriam na
primeira correcao.

A regra que justifica metade deste arquivo: **numero se formata sozinho,
nunca a linha inteira**. Um `.replace(".", ",")` aplicado sobre uma linha de
SVG troca tambem o separador decimal das coordenadas, e `x="1210.0"` vira
`x="1210,0"`, que o navegador ignora em silencio - o objeto simplesmente nao
aparece, e nao ha mensagem de erro para seguir.
"""

from __future__ import annotations

from xml.sax.saxutils import escape as _escape_xml

# Paleta de reserva para partido sem cor definida em 'texto.cores_partido'.
# Existe para o mapa nao sair de uma cor so antes de a arte fechar as cores -
# nao para substituir a decisao da arte. Oito matizes distinguiveis entre si,
# inclusive para quem nao separa vermelho de verde.
PALETA_RESERVA = [
    "#2f97e8", "#c0392b", "#27ae60", "#e8974a",
    "#8e44ad", "#16a085", "#d4c04a", "#7f8fa6",
]

CINZA_SEM_DADO = "#6b7688"
COR_FUNDO = "#0b1220"
COR_TEXTO = "#ffffff"
COR_APOIO = "#9fb0c9"
COR_DISCRETA = "#7d8aa0"
COR_LINHA = "#2a3547"


def escapar(texto: object) -> str:
    """Texto seguro dentro de um no SVG."""
    return _escape_xml(str(texto))


def int_br(valor: float) -> str:
    """12345678 -> '12.345.678'."""
    return f"{round(valor):,}".replace(",", ".")


def pct_br(valor: float, casas: int = 2) -> str:
    """63.4 -> '63,40'. Formata SO o numero (ver o cabecalho deste arquivo)."""
    return f"{float(valor):.{casas}f}".replace(".", ",")


def _canal(cor: str) -> tuple[int, int, int]:
    texto = str(cor or "").strip().lstrip("#")
    if len(texto) == 3:
        texto = "".join(c * 2 for c in texto)
    if len(texto) != 6:
        raise ValueError(f"cor hex invalida: {cor!r}")
    return tuple(int(texto[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def luminancia(cor: str) -> float:
    """0 (preto) a 1 (branco), para decidir se o texto por cima vai claro."""
    try:
        r, g, b = (c / 255 for c in _canal(cor))
    except ValueError:
        return 0.0
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contraste(fundo: str) -> str:
    """Cor de texto legivel sobre 'fundo'."""
    return "#10192b" if luminancia(fundo) > 0.6 else "#ffffff"


def mistura(cor_a: str, cor_b: str, fracao: float) -> str:
    """Interpola duas cores hex - usado em escala de intensidade."""
    try:
        a, b = _canal(cor_a), _canal(cor_b)
    except ValueError:
        return cor_b
    fracao = max(0.0, min(1.0, fracao))
    return "#" + "".join(f"{round(x + (y - x) * fracao):02x}" for x, y in zip(a, b))


def cor_de_reserva(indice: int) -> str:
    return PALETA_RESERVA[indice % len(PALETA_RESERVA)]


def texto(
    x: float,
    y: float,
    conteudo: object,
    *,
    tamanho: float = 30,
    cor: str = COR_TEXTO,
    peso: str = "",
    ancora: str = "",
    espacamento: str = "",
    opacidade: str = "",
) -> str:
    """Um <text> com os atributos que este projeto usa, e so eles."""
    atributos = [f'x="{x:g}"', f'y="{y:g}"', f'font-size="{tamanho:g}"', f'fill="{cor}"']
    if peso:
        atributos.append(f'font-weight="{peso}"')
    if ancora:
        atributos.append(f'text-anchor="{ancora}"')
    if espacamento:
        atributos.append(f'letter-spacing="{espacamento}"')
    if opacidade:
        atributos.append(f'opacity="{opacidade}"')
    return f"<text {' '.join(atributos)}>{escapar(conteudo)}</text>"


def retangulo(x: float, y: float, largura: float, altura: float, cor: str, raio: float = 0) -> str:
    arredondamento = f' rx="{raio:g}"' if raio else ""
    return (
        f'<rect x="{x:g}" y="{y:g}" width="{max(0.0, largura):g}" '
        f'height="{max(0.0, altura):g}"{arredondamento} fill="{cor}"/>'
    )
