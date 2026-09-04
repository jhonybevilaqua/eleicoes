@echo off
REM Atalho: rode "gctse <comando>" de dentro da pasta do projeto, sem precisar
REM ativar o ambiente virtual. Ex.: gctse exemplo
setlocal
cd /d "%~dp0"
if not exist .venv\Scripts\python.exe (
    echo Ambiente nao encontrado. Rode scripts\instalar.bat primeiro.
    exit /b 1
)
.venv\Scripts\python.exe -m gctse %*
