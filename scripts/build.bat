@echo off
REM Compila o executavel localmente, num Windows que tenha Python instalado.
REM O normal e deixar o GitHub compilar (aba Actions); use isto so se a
REM politica de TI exigir compilacao interna.
setlocal
cd /d "%~dp0.."

python -m venv .venv-build || exit /b 1
.venv-build\Scripts\python.exe -m pip install --upgrade pip
.venv-build\Scripts\python.exe -m pip install -r requirements.txt pyinstaller || exit /b 1

.venv-build\Scripts\python.exe -m PyInstaller ^
  --name telao --onedir --console --noconfirm --clean ^
  --paths src ^
  --hidden-import telao.mapa ^
  --hidden-import telao.telas ^
  --hidden-import telao.vertical ^
  --hidden-import telao.mesa ^
  --hidden-import tkinter ^
  telao_launcher.py || exit /b 1

echo.
echo Montando a pasta de distribuicao...
mkdir dist\telao\docs 2>nul
copy config\telao.yaml dist\telao\ >nul
copy docs\*.md dist\telao\docs\ >nul
copy empacotamento\*.bat dist\telao\ >nul
copy empacotamento\LEIA-ME.txt dist\telao\ >nul

echo.
echo Pronto: dist\telao
echo Copie essa pasta inteira para o PC de operacao.
pause
