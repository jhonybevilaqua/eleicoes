@echo off
title gctse - regravar as tarjas vazias
cd /d "%~dp0"
echo.
echo   Regrava as tres tarjas VAZIAS, com todas as colunas.
echo   Use para montar ou refazer a cena no Castalia.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Modelos
echo.
pause
