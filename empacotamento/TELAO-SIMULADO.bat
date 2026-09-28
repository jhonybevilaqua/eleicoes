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
rem
rem  O programa imprime a faixa do modo sozinho; aqui nao se repete.
rem ---------------------------------------------------------------------------

set "TELAO_MODO=simulado"

:loop
telao.exe rodar
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
