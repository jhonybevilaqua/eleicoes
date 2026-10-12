@echo off
title gctse - NO AR
cd /d "%~dp0"
rem 7.2: o INICIAR abre tambem o PAINEL (janela propria, abre o Chrome).
rem So abre se o painel ainda nao estiver rodando (porta 8099 ocupada).
netstat -ano | find ":8099 " | find "LISTENING" >nul
if errorlevel 1 (
  echo  Abrindo o PAINEL das tarjas em outra janela...
  start "gctse - painel web" "%~dp0PAINEL.bat"
) else (
  echo  O PAINEL ja esta aberto - nao abro outro.
)
echo.
:loop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1"
echo.
echo Encerrou. Reiniciando em 10s... (Ctrl+C para sair)
timeout /t 10 /nobreak >nul
goto loop
