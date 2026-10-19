@echo off
title gctse MUNICIPIOS - Presidente nas 5.570 cidades (OFICIAL)
cd /d "%~dp0"
:loop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0municipios.ps1"
echo.
echo Encerrou. Reiniciando em 10s... (Ctrl+C para sair)
timeout /t 10 /nobreak >nul
goto loop
