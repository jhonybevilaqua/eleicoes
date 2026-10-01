@echo off
title gctse APRESENTACAO HORIZONTAL
rem gctse GRAFICOS - apresentacao HORIZONTAL em tela cheia, troca a cada 15 s.
rem Abre tambem o GRAFICOS.bat se a coleta nao estiver rodando nesta maquina.
rem Se o navegador fechar ou cair, reabre sozinho em 10 s.
rem Tempo, ordem e rotacao: web\apresentacao-config.js
rem
rem Mais de um monitor: a tela cheia abre no monitor onde esta o ponto
rem MONITOR_X,MONITOR_Y (canto de cima/esquerda de cada monitor em
rem Configuracoes > Sistema > Tela). Monitor principal = 0,0.
rem Ex.: monitor a direita de um 1920x1080 principal = 1920,0
rem      monitor a esquerda do principal = -1080,0 (vertical) ou -1920,0
set MONITOR_X=0
set MONITOR_Y=0

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apresentacao.ps1" -Formato h -MonitorX:%MONITOR_X% -MonitorY:%MONITOR_Y%
