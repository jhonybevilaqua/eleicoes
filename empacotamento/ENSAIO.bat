@echo off
title gctse - ensaio com dados ficticios
cd /d "%~dp0"
echo ================================================================
echo   ENSAIO - dados INVENTADOS, nao consulta o TSE
echo   Apuracao completa em 10 minutos, para treinar com a equipe
echo.
echo   Grava em TARJAS-ENSAIO, NAO na pasta do ar. Para ver no GC,
echo   aponte uma cena de TESTE para essa pasta.
echo   Ctrl+C encerra
echo ================================================================
echo.
gctse.exe ensaio --duracao 600
echo.
pause
