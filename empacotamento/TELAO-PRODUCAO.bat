@echo off
setlocal
title TELAO - NO AR (dia da eleicao)
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem  O atalho do dia 4. So aceita boletim oficial (fase 'O'): um simulado do
rem  TSE que apareca no meio da noite e descartado, e nenhuma linha de config
rem  derruba essa trava.
rem
rem  Se a janela fechar sozinha, ela volta em 10s. Isso cobre queda de rede e
rem  erro nao previsto sem ninguem ter de ficar olhando o PC.
rem
rem  O programa imprime a faixa do modo sozinho; aqui nao se repete.
rem ---------------------------------------------------------------------------

set "TELAO_MODO=producao"

:loop
telao.exe rodar
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
