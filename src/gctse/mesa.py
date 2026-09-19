"""Mesa do telao: uma janela com um botao por quadro.

Quem opera clica no quadro que quer no ar; a mesa escreve 'no-ar.json' e a
tela de exibicao - que pode estar em outro PC, desde que enxergue a pasta -
segue o arquivo no ciclo seguinte.

Deliberadamente um ARQUIVO, nao um servidor nem uma conexao: nao ha porta
aberta para cair no meio da transmissao, e se a mesa fechar por qualquer
motivo, o ultimo quadro escolhido continua no ar. Fechar a mesa nunca tira
nada do video.

A janela e Tkinter, que vem com o Python e e empacotada pelo PyInstaller sem
dependencia extra. Onde o Tkinter nao existir - um Windows Server enxuto, uma
instalacao sem Tcl/Tk -, a mesa avisa e aponta o caminho de linha de comando,
que faz exatamente a mesma coisa:

    gctse no-ar mapa-partido
"""

from __future__ import annotations

import json
from pathlib import Path

CORES = {
    "fundo": "#131b28",
    "painel": "#1b2534",
    "texto": "#e8edf5",
    "apoio": "#93a3bb",
    "no_ar": "#c0392b",
    "borda": "#293446",
}


def ler_quadros(pasta: Path) -> list[dict]:
    """Lista de quadros publicada pelo telao ('quadros.json')."""
    try:
        dados = json.loads((pasta / "quadros.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    return [q for q in dados.get("quadros", []) if isinstance(q, dict) and q.get("id")]


def ler_no_ar(pasta: Path) -> str:
    try:
        dados = json.loads((pasta / "no-ar.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    return str(dados.get("quadro", ""))


def escrever_no_ar(pasta: Path, identificador: str) -> Path:
    """Delega ao telao: a selecao tem de sair nos dois formatos, sempre.

    A mesa ja escreveu so o .json uma vez nesta historia, e o resultado foi a
    mesa marcando um quadro enquanto o ar mostrava outro - a tela le o .js.
    Por isso aqui nao ha copia da logica, ha uma chamada.
    """
    from .telao import escrever_selecao

    return escrever_selecao(pasta, identificador)


def abrir(pasta: Path) -> int:
    """Abre a janela da mesa. Devolve o codigo de saida do comando."""
    try:
        import tkinter as tk
    except ImportError:
        print("Tkinter nao esta disponivel neste Python, entao a janela nao abre.")
        print("A selecao pela linha de comando faz a mesma coisa:")
        print("    gctse no-ar <id-do-quadro>")
        print("    gctse no-ar --listar")
        return 2

    quadros = ler_quadros(pasta)
    if not quadros:
        print(f"Nenhum quadro publicado em {pasta}.")
        print("O telao grava 'quadros.json' depois do primeiro ciclo. Rode 'gctse rodar'")
        print("(ou 'gctse ensaio', para testar sem o TSE) e abra a mesa de novo.")
        return 1

    janela = tk.Tk()
    janela.title("Mesa do telao - gctse")
    janela.configure(bg=CORES["fundo"])
    janela.minsize(460, 220)

    tk.Label(
        janela, text="QUADRO NO AR", bg=CORES["fundo"], fg=CORES["apoio"],
        font=("Segoe UI", 10, "bold"),
    ).pack(anchor="w", padx=18, pady=(16, 2))

    rotulo_atual = tk.Label(
        janela, text="—", bg=CORES["fundo"], fg=CORES["texto"], font=("Segoe UI", 16, "bold"),
    )
    rotulo_atual.pack(anchor="w", padx=18, pady=(0, 14))

    quadro_lista = tk.Frame(janela, bg=CORES["fundo"])
    quadro_lista.pack(fill="both", expand=True, padx=12, pady=(0, 10))

    botoes: dict[str, tk.Button] = {}

    def pintar(selecionado: str) -> None:
        for identificador, botao in botoes.items():
            no_ar = identificador == selecionado
            botao.configure(
                bg=CORES["no_ar"] if no_ar else CORES["painel"],
                fg="#ffffff" if no_ar else CORES["texto"],
                activebackground=CORES["no_ar"] if no_ar else CORES["borda"],
            )
        atual = next((q for q in quadros if q["id"] == selecionado), None)
        rotulo_atual.configure(text=(atual or {}).get("titulo") or selecionado or "—")

    def escolher(identificador: str) -> None:
        try:
            escrever_no_ar(pasta, identificador)
        except OSError as exc:
            rotulo_atual.configure(text=f"falha ao gravar: {exc}")
            return
        pintar(identificador)

    for indice, quadro in enumerate(quadros, start=1):
        botao = tk.Button(
            quadro_lista,
            text=f"  {indice}   {quadro.get('titulo') or quadro['id']}",
            anchor="w",
            font=("Segoe UI", 12),
            relief="flat",
            bd=0,
            padx=14,
            pady=11,
            cursor="hand2",
            command=lambda i=quadro["id"]: escolher(i),
        )
        botao.pack(fill="x", pady=3)
        botoes[quadro["id"]] = botao
        # o numero do botao e a mesma tecla que troca o quadro na tela de
        # exibicao, para quem opera nao ter dois mapas mentais diferentes
        if indice <= 9:
            janela.bind(str(indice), lambda _e, i=quadro["id"]: escolher(i))

    tk.Label(
        janela,
        text=f"Pasta: {pasta}",
        bg=CORES["fundo"], fg=CORES["apoio"], font=("Segoe UI", 8), anchor="w",
    ).pack(fill="x", padx=18, pady=(0, 10))

    def acompanhar() -> None:
        """Relê a seleção: se alguém trocar por fora, a mesa mostra a verdade."""
        pintar(ler_no_ar(pasta))
        janela.after(2000, acompanhar)

    acompanhar()
    janela.mainloop()
    return 0
