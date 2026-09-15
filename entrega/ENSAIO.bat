@echo off
title gctse - ENSAIO (dados ficticios)
cd /d "%~dp0"
echo  ENSAIO: dados inventados, nao consulta o TSE.
echo  Apuracao completa em 10 minutos. Ctrl+C encerra.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Ensaio
pause
