@echo off
title gctse - DIAGNOSTICO completo (simulado)
cd /d "%~dp0"
echo.
echo   Valida TUDO contra o SIMULADO do TSE e grava DIAGNOSTICO.txt
echo   Leva de 1 a 2 minutos. Pode rodar com o TESTE.bat aberto.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Diagnostico -Teste
echo.
echo   Envie o arquivo DIAGNOSTICO.txt desta pasta.
echo.
pause
