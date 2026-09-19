"""Ponto de entrada do executavel do telao (PyInstaller).

Igual ao gctse_launcher.py: o PyInstaller precisa de um script, nao de um
modulo. Nao ha logica aqui - veja src/telao/cli.py.
"""

import sys

from telao.cli import main

if __name__ == "__main__":
    sys.exit(main())
