@echo off
title gctse - apuracao no ar
cd /d "%~dp0"
echo ================================================================
echo   NO AR - lendo o TSE e gravando na pasta TARJAS
echo   Acompanhe abrindo TARJAS\painel.html
echo   Ctrl+C encerra
echo ================================================================
echo.
:loop
gctse.exe rodar
echo.
echo Encerrou (codigo %ERRORLEVEL%). Reiniciando em 10s...
timeout /t 10 /nobreak >nul
goto loop
