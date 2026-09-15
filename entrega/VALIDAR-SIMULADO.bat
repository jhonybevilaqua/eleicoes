@echo off
title gctse - validar os numeros contra o TSE
cd /d "%~dp0"
echo.
echo   Confere numero por numero: o que o TSE mandou x o que esta na tarja.
echo   Deixe o TESTE.bat rodando numa outra janela antes.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Validar -Teste
echo.
pause
