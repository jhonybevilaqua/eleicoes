@echo off
setlocal
title TELAO - MODO SIMULADO (dias de teste do TSE)
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem  Le o TSE nos DIAS DE TESTE, quando ele publica boletim em fase 'S'.
rem
rem  Todas as telas saem carimbadas com o selo de simulado, e o selo nao pode
rem  ser desligado. Isso e proposital: se alguem abrir este atalho por engano
rem  no dia da eleicao, o carimbo aparece no ar e o erro e visto na hora.
rem
rem  O modo vem desta janela, nao de arquivo - entao nao ha estado para alguem
rem  esquecer de trocar depois.
rem ---------------------------------------------------------------------------

set "TELAO_MODO=simulado"

echo ==================================================================
echo   MODO SIMULADO - dados de TESTE do TSE
echo.
echo   As telas saem carimbadas. Para o dia da eleicao use
echo   TELAO-PRODUCAO.bat.
echo.
echo   Deixe esta janela aberta. Ctrl+C encerra.
echo ==================================================================
echo.
:loop
telao.exe rodar
echo.
echo Encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s...
timeout /t 10 /nobreak >nul
goto loop
