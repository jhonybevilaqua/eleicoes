@echo off
title gctse ESTADOS - Governador e Senador (OFICIAL)
cd /d "%~dp0"
:loop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0estados.ps1"
echo.
echo Encerrou. Reiniciando em 10s... (Ctrl+C para sair)
timeout /t 10 /nobreak >nul
goto loop
