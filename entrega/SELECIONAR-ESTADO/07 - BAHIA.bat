@echo off
REM Escreve a praca escolhida no SELECAO.txt da pasta acima.
REM O gctse le esse arquivo e troca a tarja em cerca de 1 segundo.
echo ba> "%~dp0..\SELECAO.txt"
echo Tarja de governador e senador agora mostra: BAHIA
timeout /t 2 /nobreak >nul
