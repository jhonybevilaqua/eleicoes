@echo off
title gctse - descobrir os codigos do SIMULADO do TSE
cd /d "%~dp0"
echo  Consultando o ambiente de SIMULADO do TSE (resultados-sim).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Descobrir -Teste
echo.
pause
