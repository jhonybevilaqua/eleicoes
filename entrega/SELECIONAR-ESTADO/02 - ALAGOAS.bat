@echo off
REM Escreve a praca escolhida nos SELECAO da pasta acima (governador e senador).
REM Para escolher so um dos dois, use o painel web (PAINEL.bat).
echo al> "%~dp0..\SELECAO.txt"
echo al> "%~dp0..\SELECAO-SENADOR.txt"
echo Governador e senador agora mostram: ALAGOAS
timeout /t 2 /nobreak >nul
