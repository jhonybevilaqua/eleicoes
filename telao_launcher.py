"""Ponto de entrada do executavel (PyInstaller).

O PyInstaller precisa de um script, nao de um modulo. Nao ha logica aqui -
veja src/telao/cli.py.
"""

import sys

from telao.cli import main

if __name__ == "__main__":
    sys.exit(main())
