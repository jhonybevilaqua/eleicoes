@echo off
title gctse - conferir se estamos recebendo dados do TSE
cd /d "%~dp0"
echo.
echo   Testando a conexao com o TSE. Leva menos de 1 minuto.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Conferir
echo.
pause
