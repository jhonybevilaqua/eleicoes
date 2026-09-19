"""Mesa do telao: uma janela com um botao por tela.

Quem dirige clica na tela que quer no ar; a mesa grava a selecao e o PC de
exibicao - que pode estar em outra sala, desde que enxergue a pasta - obedece
em cerca de um segundo.

Deliberadamente um ARQUIVO, nao um servidor nem uma conexao: nao ha porta
aberta para cair no meio da transmissao, e se a mesa fechar por qualquer
motivo, o ultimo quadro escolhido continua no ar. Fechar a mesa nunca tira
nada do video.

A janela e Tkinter, que vem com o Python e e empacotada pelo PyInstaller sem
dependencia extra. Onde o Tkinter nao existir - um Windows Server enxuto, uma
instalacao sem Tcl/Tk -, a mesa avisa e aponta o caminho de linha de comando,
que faz exatamente a mesma coisa:

    telao no-ar lideranca
"""

from __future__ import annotations

from pathlib import Path

from .exibicao import escrever_selecao, ler_selecao, ler_telas

CORES = {
    "fundo": "#131b28",
    "painel": "#1b2534",
    "texto": "#e8edf5",
    "apoio": "#93a3bb",
    "no_ar": "#c0392b",
    "borda": "#293446",
}


def abrir(pasta: Path) -> int:
    """Abre a janela da mesa. Devolve o codigo de saida do comando."""
    try:
        import tkinter as tk
    except ImportError:
        print("Tkinter nao esta disponivel neste Python, entao a janela nao abre.")
        print("A selecao pela linha de comando faz a mesma coisa:")
        print("    telao no-ar <id-da-tela>")
        print("    telao no-ar --listar")
        return 2

    telas = ler_telas(pasta)
    if not telas:
        print(f"Nenhuma tela publicada em {pasta}.")
        print("O telao grava 'telas.json' depois do primeiro ciclo. Rode 'telao rodar'")
        print("(ou 'telao ensaio', para testar sem o TSE) e abra a mesa de novo.")
        return 1

    janela = tk.Tk()
    janela.title("Mesa do telao")
    janela.configure(bg=CORES["fundo"])
    janela.minsize(460, 220)

    tk.Label(
        janela, text="TELA NO AR", bg=CORES["fundo"], fg=CORES["apoio"],
        font=("Segoe UI", 10, "bold"),
    ).pack(anchor="w", padx=18, pady=(16, 2))

    rotulo_atual = tk.Label(
        janela, text="—", bg=CORES["fundo"], fg=CORES["texto"], font=("Segoe UI", 16, "bold"),
    )
    rotulo_atual.pack(anchor="w", padx=18, pady=(0, 14))

    lista = tk.Frame(janela, bg=CORES["fundo"])
    lista.pack(fill="both", expand=True, padx=12, pady=(0, 10))

    botoes: dict[str, tk.Button] = {}

    def pintar(selecionado: str) -> None:
        for identificador, botao in botoes.items():
            no_ar = identificador == selecionado
            botao.configure(
                bg=CORES["no_ar"] if no_ar else CORES["painel"],
                fg="#ffffff" if no_ar else CORES["texto"],
                activebackground=CORES["no_ar"] if no_ar else CORES["borda"],
            )
        atual = next((t for t in telas if t["id"] == selecionado), None)
        rotulo_atual.configure(text=(atual or {}).get("titulo") or selecionado or "—")

    def escolher(identificador: str) -> None:
        try:
            escrever_selecao(pasta, identificador)
        except OSError as exc:
            rotulo_atual.configure(text=f"falha ao gravar: {exc}")
            return
        pintar(identificador)

    for indice, tela in enumerate(telas, start=1):
        botao = tk.Button(
            lista,
            text=f"  {indice}   {tela.get('titulo') or tela['id']}",
            anchor="w",
            font=("Segoe UI", 12),
            relief="flat",
            bd=0,
            padx=14,
            pady=11,
            cursor="hand2",
            command=lambda i=tela["id"]: escolher(i),
        )
        botao.pack(fill="x", pady=3)
        botoes[tela["id"]] = botao
        # o numero do botao e a mesma tecla que troca a tela no PC de
        # exibicao, para quem opera nao ter dois mapas mentais diferentes
        if indice <= 9:
            janela.bind(str(indice), lambda _e, i=tela["id"]: escolher(i))

    tk.Label(
        janela,
        text=f"Pasta: {pasta}",
        bg=CORES["fundo"], fg=CORES["apoio"], font=("Segoe UI", 8), anchor="w",
    ).pack(fill="x", padx=18, pady=(0, 10))

    def acompanhar() -> None:
        """Relê a seleção: se alguém trocar por fora, a mesa mostra a verdade."""
        pintar(ler_selecao(pasta))
        janela.after(2000, acompanhar)

    acompanhar()
    janela.mainloop()
    return 0
