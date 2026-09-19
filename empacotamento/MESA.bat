@echo off
title gctse - mesa do telao
cd /d "%~dp0"
echo.
echo  Mesa do telao: clique no quadro que deve ir ao ar.
echo  A tela de exibicao obedece em cerca de 1 segundo.
echo.
echo  Fechar a mesa NAO tira nada do ar - o ultimo quadro escolhido continua.
echo.
gctse.exe mesa
if errorlevel 2 (
  echo.
  echo  A janela nao abriu neste PC. A lista abaixo faz a mesma coisa:
  echo.
  gctse.exe no-ar --listar
  echo.
  echo  Para trocar:  gctse.exe no-ar ^<id^>
  echo.
  pause
)
