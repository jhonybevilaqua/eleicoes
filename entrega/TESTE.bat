@echo off
title gctse - TESTE com o simulado do TSE
cd /d "%~dp0"
echo  TESTE: aceita os boletins de SIMULADO do TSE (fase S).
echo  Grava na MESMA pasta TARJAS. Ctrl+C encerra.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Teste
pause
