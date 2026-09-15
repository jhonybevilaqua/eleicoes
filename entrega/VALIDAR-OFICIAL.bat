@echo off
title gctse - validar os numeros contra o TSE (OFICIAL)
cd /d "%~dp0"
echo.
echo   Confere numero por numero no ambiente OFICIAL.
echo   Deixe o INICIAR.bat rodando numa outra janela antes.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Validar
echo.
pause
