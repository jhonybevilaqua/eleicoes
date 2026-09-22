@echo off
setlocal
title GC - MODO SIMULADO (dias de teste do TSE)
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem  Le o TSE nos DIAS DE TESTE, quando ele publica boletim em fase 'S'.
rem
rem  Grava nas MESMAS tarjas de sempre, nos mesmos caminhos: e isso que faz o
rem  teste provar a cena de verdade. O que muda e que TODA tarja sai com o selo
rem  de simulado, e o selo nao pode ser desligado - nem por config, nem por
rem  boletim que venha marcado como oficial.
rem
rem  O modo vem desta janela, nao de arquivo: nao ha estado para alguem
rem  esquecer de trocar depois.
rem ---------------------------------------------------------------------------

set "GCTSE_MODO=simulado"

echo ==================================================================
echo   MODO SIMULADO - dados de TESTE do TSE
echo.
echo   As tarjas saem carimbadas. Para o dia da eleicao use
echo   GC-PRODUCAO.bat.
echo.
echo   Acompanhe abrindo TARJAS\painel.html
echo   Deixe esta janela aberta. Ctrl+C encerra.
echo ==================================================================
echo.
:loop
gctse.exe rodar
echo.
echo Encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s...
timeout /t 10 /nobreak >nul
goto loop
