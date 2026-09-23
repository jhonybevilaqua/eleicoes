@echo off
title gctse - DIAGNOSTICO completo (OFICIAL)
cd /d "%~dp0"
echo.
echo   Valida TUDO contra o ambiente OFICIAL do TSE e grava DIAGNOSTICO.txt
echo   Use na noite da apuracao. Pode rodar com o INICIAR.bat aberto.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Diagnostico
echo.
echo   Envie o arquivo DIAGNOSTICO.txt desta pasta.
echo.
pause
