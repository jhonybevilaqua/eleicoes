@echo off
title gctse GRAFICOS - OFICIAL
cd /d "%~dp0"
:loop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0graficos.ps1"
echo.
echo Encerrou. Reiniciando em 10s... (Ctrl+C para sair)
timeout /t 10 /nobreak >nul
goto loop
