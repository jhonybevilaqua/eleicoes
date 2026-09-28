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

rem O programa imprime a faixa do modo sozinho; aqui so o que ele nao sabe.
echo   Para o dia da eleicao use GC-PRODUCAO.bat.
echo   Acompanhe abrindo TARJAS\painel.html
echo   Deixe esta janela aberta. Ctrl+C encerra.
echo.
:loop
gctse.exe rodar
if %ERRORLEVEL% EQU 2 goto configuracao
echo.
echo Encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s...
timeout /t 10 /nobreak >nul
goto loop

:configuracao
rem Falta preencher alguma coisa, e o programa acabou de dizer o que. Nao da
rem para reiniciar em 10s como nas outras saidas - a mensagem sumiria da tela
rem antes de alguem ler, e a janela viraria uma parede de texto repetido.
rem
rem Mas tambem nao da para PARAR de vez: este atalho pode ter subido
rem minimizado pelo INICIAR-COM-O-WINDOWS, sem ninguem olhando, e ai ficaria
rem parado para sempre mesmo depois de a config ser corrigida.
rem
rem Entao espera 60s e tenta de novo: tempo de sobra para ler, e volta
rem sozinho assim que o arquivo for arrumado.
echo.
echo Isso acima nao se resolve sozinho: corrija a configuracao.
echo Vou reler o arquivo em 60s. Ctrl+C encerra.
timeout /t 60 /nobreak >nul
goto loop
