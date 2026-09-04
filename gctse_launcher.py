"""Ponto de entrada do executavel empacotado (PyInstaller).

O PyInstaller precisa de um script, nao de um modulo, entao este arquivo so
chama a CLI. Nao ha logica aqui - veja src/gctse/cli.py.
"""

import sys

from gctse.cli import main

if __name__ == "__main__":
    sys.exit(main())
