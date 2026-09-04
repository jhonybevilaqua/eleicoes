@echo off
REM Operacao real. Reinicia sozinho se o processo cair.
cd /d "%~dp0"
echo ================================================================
echo  OPERACAO - lendo o TSE. Ctrl+C encerra.
echo ================================================================
:loop
gctse.exe rodar
echo.
echo Processo encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s...
timeout /t 10 /nobreak >nul
goto loop
