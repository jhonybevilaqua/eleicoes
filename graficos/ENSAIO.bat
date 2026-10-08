@echo off
title gctse ENSAIO GERAL - 2o turno simulado (NAO VAI AO AR)
rem Treino da equipe: copia o sistema para a pasta "ensaio", liga um TSE
rem SIMULADO (dados ficticios) e abre coletas + gerenciador do ensaio na
rem porta 8096. O OBS/DeckLink (porta 8098) nao recebe nada.
rem Tempo da apuracao simulada: ENSAIO.bat 40  (= 40 minutos; padrao 20)
cd /d "%~dp0"
set MIN=%1
if "%MIN%"=="" set MIN=20
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensaio.ps1" -Minutos %MIN%
pause
