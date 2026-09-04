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
  --name gctse --onedir --console --noconfirm --clean ^
  --paths src ^
  --hidden-import gctse.exporters.arquivo_csv ^
  --hidden-import gctse.exporters.arquivo_json ^
  --hidden-import gctse.exporters.arquivo_xml ^
  --hidden-import gctse.exporters.caspar ^
  --hidden-import gctse.exporters.classx ^
  --hidden-import gctse.exporters.http_push ^
  --hidden-import gctse.exporters.viz_tab ^
  gctse_launcher.py || exit /b 1

mkdir dist\gctse\config 2>nul
mkdir dist\gctse\docs 2>nul
copy config\*.yaml dist\gctse\config\ >nul
copy docs\*.md dist\gctse\docs\ >nul
copy README.md dist\gctse\ >nul
copy empacotamento\*.bat dist\gctse\ >nul
copy empacotamento\LEIA-ME.txt dist\gctse\ >nul
if not exist dist\gctse\config\config.yaml copy dist\gctse\config\config.recomendado.yaml dist\gctse\config\config.yaml >nul

echo.
echo Pronto: dist\gctse\  - copie a pasta inteira para o PC de operacao.
