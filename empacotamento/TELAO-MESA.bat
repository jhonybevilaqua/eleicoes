@echo off
title TELAO - mesa
cd /d "%~dp0"
echo.
echo  Mesa do telao: clique na tela que deve ir ao ar.
echo  O PC de exibicao obedece em cerca de 1 segundo.
echo.
echo  Fechar a mesa NAO tira nada do ar - a ultima tela escolhida continua.
echo.
telao.exe mesa
if errorlevel 2 (
  echo.
  echo  A janela nao abriu neste PC. A lista abaixo faz a mesma coisa:
  echo.
  telao.exe no-ar --listar
  echo.
  echo  Para trocar:  telao.exe no-ar ^<id^>
  echo.
  pause
)
