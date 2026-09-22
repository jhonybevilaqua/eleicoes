@echo off
setlocal
title GC - NO AR (dia da eleicao)
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem  O atalho do dia 4. So aceita boletim oficial (fase 'O'): um simulado do
rem  TSE que apareca no meio da noite e descartado, e nenhuma linha de config
rem  derruba essa trava.
rem
rem  Se a janela fechar sozinha, ela volta em 10s. Isso cobre queda de rede e
rem  erro nao previsto sem ninguem ter de ficar olhando o PC.
rem ---------------------------------------------------------------------------

set "GCTSE_MODO=producao"

echo ==================================================================
echo   NO AR - lendo o TSE e gravando na pasta TARJAS
echo.
echo   So boletim oficial. Acompanhe abrindo TARJAS\painel.html
echo   Deixe esta janela aberta. Ctrl+C encerra.
echo ==================================================================
echo.
:loop
gctse.exe rodar
echo.
echo Encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s...
timeout /t 10 /nobreak >nul
goto loop
