@echo off
title gctse - painel web
cd /d "%~dp0"
echo  Abrindo o painel em http://localhost:8099
echo  Deixe esta janela aberta. Ctrl+C encerra o painel (a coleta continua).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PAINEL.ps1"
pause
