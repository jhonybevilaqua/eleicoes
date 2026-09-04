"""Gera o PDF das tarjas a partir de tarjas/modelos.html.

O modo '?impressao' da propria pagina monta a versao de papel: cada modelo
aparece nos dois estados (parcial e fechamento) lado a lado, um por pagina.
Fonte unica - mexer na pagina e o PDF acompanha.

    pip install playwright && playwright install chromium
    python scripts/gerar_pdf_tarjas.py
"""

import asyncio
import os
import pathlib
from playwright.async_api import async_playwright

RAIZ = pathlib.Path(__file__).resolve().parents[1]
ORIGEM = RAIZ / "tarjas" / "modelos.html"
DESTINO = RAIZ / "tarjas" / "Tarjas-EV-News-2026.pdf"
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
        await pag.pdf(path=str(DESTINO), format="A4", landscape=True, print_background=True,
                      margin={"top": "9mm", "bottom": "10mm", "left": "12mm", "right": "12mm"})
        await nav.close()
        print(f"PDF gerado em {DESTINO}")


asyncio.run(main())
