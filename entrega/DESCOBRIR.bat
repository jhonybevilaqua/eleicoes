@echo off
title gctse - descobrir os codigos do TSE
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Descobrir
echo.
pause
