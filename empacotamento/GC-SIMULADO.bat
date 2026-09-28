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
rem Reiniciar aqui nao adianta: falta preencher alguma coisa, e o programa
rem acabou de dizer o que. A janela fica aberta com a mensagem a vista.
echo.
echo Nao vou reiniciar: isso acima nao se resolve sozinho.
echo Corrija e abra este atalho de novo.
echo.
pause
exit /b 2
