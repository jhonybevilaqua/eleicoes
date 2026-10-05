@echo off
title gctse - IMPORTAR EVOLUCAO (log das tarjas)
rem Arraste sobre este arquivo o log das tarjas do dia da eleicao
rem (logs\gctse-AAAA-MM-DD.log) ou a pasta logs inteira. Sem arrastar,
rem procura na pasta "importar" ao lado. Ver LEIA-ME.txt.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0importar-evolucao.ps1" %*
pause
