@echo off
REM Instalacao no PC de operacao (Windows + Python 3.9+).
setlocal
cd /d "%~dp0.."
python -m venv .venv || exit /b 1
.venv\Scripts\python.exe -m pip install --upgrade pip
.venv\Scripts\python.exe -m pip install -r requirements.txt || exit /b 1
.venv\Scripts\python.exe -m pip install -e . || exit /b 1
if not exist config\config.yaml copy config\config.example.yaml config\config.yaml
echo.
echo Pronto. Edite config\config.yaml e rode: scripts\rodar.bat
