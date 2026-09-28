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

rem O programa imprime a faixa do modo sozinho; aqui so o que ele nao sabe.
echo   Gravando na pasta TARJAS.
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
