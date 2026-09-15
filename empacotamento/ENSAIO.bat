@echo off
title gctse - ensaio com dados ficticios
cd /d "%~dp0"
echo ================================================================
echo   ENSAIO - dados INVENTADOS, nao consulta o TSE
echo   Apuracao completa em 10 minutos, para treinar com a equipe
echo   Ctrl+C encerra
echo ================================================================
echo.
gctse.exe ensaio --duracao 600
echo.
pause
