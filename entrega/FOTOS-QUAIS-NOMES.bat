@echo off
title gctse - nomes das fotos dos candidatos
cd /d "%~dp0"
echo.
echo   Le a lista de candidatos a presidente no TSE e mostra com que nome
echo   salvar a foto de cada um. Grava FOTOS\LISTA-DE-FOTOS.txt
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Fotos -Teste
echo.
pause
