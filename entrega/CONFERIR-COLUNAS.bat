@echo off
title gctse - conferir as colunas dos arquivos
cd /d "%~dp0"
echo.
echo   Mostra, numeradas, as colunas de cada arquivo em TARJAS.
echo   Compare com o que o DataSource Editor do Castalia mostra.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Campos
echo.
echo   O mesmo texto ficou salvo em CAMPOS-AGORA.txt
echo.
pause
