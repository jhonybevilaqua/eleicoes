@echo off
title gctse - preencher TARJAS com exemplos
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Preencher
echo.
echo Pronto. Monte as cenas do Castalia apontando para a pasta TARJAS.
pause
