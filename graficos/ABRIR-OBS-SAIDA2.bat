@echo off
title gctse - OBS da SAIDA 2 da DeckLink
rem Abre o OBS portatil da SAIDA 2 (cada saida tem o seu OBS, com a sua
rem configuracao - assim as duas saidas da DeckLink nao se misturam).
rem Ajuste a pasta abaixo se extraiu o OBS em outro lugar.
set "OBS=D:\OBS-SAIDA2"

if exist "%OBS%\bin\64bit\obs64.exe" goto abrir
rem chamado pelo GERENCIADOR.bat: sem OBS instalado, segue sem avisar
if /i "%~1"=="auto" exit /b
echo Nao achei o OBS em %OBS%
echo Veja o passo 1 do OBS-DECKLINK.txt (extrair o ZIP do OBS nessa pasta)
echo ou corrija a linha set "OBS=..." neste arquivo (Bloco de Notas).
pause
exit /b

:abrir
cd /d "%OBS%\bin\64bit"
start "" obs64.exe --portable --multi
