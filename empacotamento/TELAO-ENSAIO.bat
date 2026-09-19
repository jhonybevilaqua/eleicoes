@echo off
title TELAO - ensaio (dados ficticios)
cd /d "%~dp0"
echo ================================================================
echo   ENSAIO - dados inventados, apuracao completa em 15 minutos.
echo   NAO consulta o TSE. Serve para treinar com a equipe.
echo.
echo   Abra TELAO-MESA.bat aqui e TELAO-TELA.bat no PC de exibicao.
echo   As telas saem marcadas PARCIAL - NAO OFICIAL.
echo ================================================================
echo.
telao.exe ensaio --duracao 900
pause
