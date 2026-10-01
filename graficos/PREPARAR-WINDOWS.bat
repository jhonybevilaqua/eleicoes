@echo off
title gctse GRAFICOS - preparar o Windows
rem Tela sempre ligada, sem suspender, sem protecao de tela e sem
rem notificacoes por cima da tela cheia. Opcao D desfaz.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0preparar-windows.ps1"
