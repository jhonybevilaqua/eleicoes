@echo off
title gctse GRAFICOS - SIMULADO DO TSE (NAO USAR NO AR)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0graficos.ps1" -Teste
pause
