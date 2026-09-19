@echo off
title TELAO - coleta no ar
cd /d "%~dp0"
echo ================================================================
echo   TELAO NO AR - lendo o TSE e redesenhando as telas
echo.
echo   Deixe esta janela aberta. Ctrl+C encerra.
echo   Para escolher a tela que vai ao ar: TELAO-MESA.bat
echo ================================================================
echo.
:loop
telao.exe rodar
echo.
echo Encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s...
timeout /t 10 /nobreak >nul
goto loop
