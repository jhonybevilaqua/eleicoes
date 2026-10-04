@echo off
title gctse - OBS das saidas da DeckLink
rem Abre de novo os dois OBS das saidas (se algum foi fechado). O
rem GERENCIADOR.bat ja faz isso sozinho; este e so para reabrir.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0obs-saidas.ps1" -Auto
