@echo off
title gctse - TESTE com o simulado do TSE
cd /d "%~dp0"
echo  TESTE: aceita os boletins de SIMULADO do TSE (fase S).
echo  Grava na MESMA pasta TARJAS.
echo  Se o PowerShell cair, esta janela reinicia sozinha em 10s.
echo  Para encerrar de verdade: feche a janela, ou Ctrl+C duas vezes.
echo.
:loop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gctse.ps1" -Teste
echo.
echo Encerrou. Reiniciando em 10s... (feche a janela para sair)
timeout /t 10 /nobreak ^>nul
goto loop
