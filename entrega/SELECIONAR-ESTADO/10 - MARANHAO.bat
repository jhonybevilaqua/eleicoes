@echo off
REM Escreve a praca escolhida nos SELECAO da pasta acima (governador e senador).
REM Para escolher so um dos dois, use o painel web (PAINEL.bat).
echo ma> "%~dp0..\SELECAO.txt"
echo ma> "%~dp0..\SELECAO-SENADOR.txt"
echo Governador e senador agora mostram: MARANHAO
timeout /t 2 /nobreak >nul
