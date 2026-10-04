@echo off
title gctse - VER ELEITO
rem Mostra o que o TSE manda (e=, st=) para Governador e Senador de um
rem estado e o que a tela recebeu. Grava VER-ELEITO.txt.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ver-eleito.ps1"
pause
