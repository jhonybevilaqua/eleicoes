@echo off
title gctse - TESTE com o simulado do TSE
cd /d "%~dp0"
echo ================================================================
echo   TESTE - aceita os boletins de SIMULADO do TSE (fase S)
echo   Grava na MESMA pasta TARJAS, entao a cena nao muda de caminho
echo   Acompanhe abrindo TARJAS\painel.html
echo   Ctrl+C encerra
echo ================================================================
echo.
gctse.exe rodar --permitir-nao-oficial
echo.
pause
