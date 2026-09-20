@echo off
setlocal
title TELAO - PRODUCAO (no ar)
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem  NO AR. So aceita boletim oficial do TSE (fase 'O').
rem
rem  Boletim simulado e descartado aqui, aconteca o que acontecer na config:
rem  a trava de fase e ligada pelo modo e nao ha valor de arquivo que a
rem  desligue. E a garantia de que um simulado do TSE nao vai ao ar como
rem  resultado.
rem
rem  Se o programa recusar subir dizendo que o codigo do pleito esta em '000',
rem  rode  telao.exe descobrir  e preencha os codigos em telao.yaml, na secao
rem  modos: producao:. Isso e de proposito: subir com codigo em branco passaria
rem  a noite inteira 'aguardando boletim' sem ninguem entender por que.
rem ---------------------------------------------------------------------------

set "TELAO_MODO=producao"

echo ==================================================================
echo   PRODUCAO - NO AR. So boletim oficial.
echo.
echo   Deixe esta janela aberta. Ctrl+C encerra.
echo   Reinicia sozinho se cair.
echo ==================================================================
echo.
:loop
telao.exe rodar
echo.
echo Encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s...
timeout /t 10 /nobreak >nul
goto loop
