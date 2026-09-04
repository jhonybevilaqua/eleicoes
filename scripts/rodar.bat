@echo off
REM Operacao continua no Windows. Ajuste o caminho se instalar em outra pasta.
setlocal
cd /d "%~dp0.."
if not exist .venv\Scripts\python.exe (
    echo Ambiente nao encontrado. Rode scripts\instalar.bat primeiro.
    exit /b 1
)
:loop
.venv\Scripts\python.exe -m gctse -c config\config.yaml rodar
echo.
echo Processo encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s... Ctrl+C para sair.
timeout /t 10 /nobreak >nul
goto loop
