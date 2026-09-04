"""Gera o PDF das tarjas a partir de tarjas/modelos.html.

O modo '?impressao' da propria pagina monta a versao de papel: um modelo por
pagina, mais as pranchas de arte em pagina cheia no fim. Fonte unica - mexer na
pagina e o PDF acompanha.

Alem do PDF, exporta cada tarja em PNG 1920x1080 para tarjas/artes/. Sao os
mesmos quadros das pranchas, no tamanho de projeto, para o designer calcar a
cena no LiveBoard por cima.

    pip install playwright && playwright install chromium
    python scripts/gerar_pdf_tarjas.py
"""

import asyncio
import os
import pathlib
from playwright.async_api import async_playwright

RAIZ = pathlib.Path(__file__).resolve().parents[1]
ORIGEM = RAIZ / "tarjas" / "modelos.html"
DESTINO = RAIZ / "tarjas" / "Tarjas-Eleicoes-2026.pdf"
PASTA_ARTES = RAIZ / "tarjas" / "artes"
# em ambiente com Chromium proprio, aponte com CHROMIUM_PATH
NAVEGADOR = os.environ.get("CHROMIUM_PATH")

async def main():
    async with async_playwright() as p:
        nav = await p.chromium.launch(**({"executable_path": NAVEGADOR} if NAVEGADOR else {}))
        pag = await nav.new_page(viewport={"width": 1600, "height": 1200})
        await pag.emulate_media(color_scheme="light")
        await pag.goto(f"file://{ORIGEM}?impressao", wait_until="networkidle")
        await pag.wait_for_timeout(1200)          # tempo para as fontes do Google
        n = await pag.locator(".modelo").count()
        print(f"{n} modelos renderizados")
        # margens zeradas na API para o CSS mandar: as paginas normais usam
        # '@page' e as pranchas de arte usam '@page cheia', sem margem nenhuma
        await pag.pdf(path=str(DESTINO), format="A4", landscape=True, print_background=True,
                      prefer_css_page_size=True,
                      margin={"top": "0", "bottom": "0", "left": "0", "right": "0"})
        print(f"PDF gerado em {DESTINO}")

        await exportar_artes(pag)
        await nav.close()


async def exportar_artes(pag):
    """Salva cada tarja como PNG no tamanho de projeto, 1920x1080.

    O palco usa unidades de container query, entao forcar a largura para 1920px
    faz cada medida cair exatamente no pixel de projeto - o PNG sai com as
    mesmas proporcoes que a cena precisa ter no GC.
    """
    PASTA_ARTES.mkdir(parents=True, exist_ok=True)
    await pag.emulate_media(media="screen")
    await pag.set_viewport_size({"width": 1990, "height": 1240})
    await pag.add_style_tag(content="""
        .wrap{max-width:none!important}
        .prova{height:auto!important}
        .prova .palco{width:1920px!important;max-width:none!important;
                      border:0!important;border-radius:0!important}
    """)
    await pag.wait_for_timeout(600)

    quadros = await pag.locator("[data-arte]").all()
    for quadro in quadros:
        nome = await quadro.get_attribute("data-arte")
        caixa = await quadro.bounding_box()
        await quadro.screenshot(path=str(PASTA_ARTES / f"{nome}.png"))
        print(f"  arte {nome}.png  {round(caixa['width'])}x{round(caixa['height'])}")
    print(f"{len(quadros)} artes em {PASTA_ARTES}")


asyncio.run(main())
