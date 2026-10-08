@echo off
title gctse - IMPORTAR PERFIL DO ELEITOR (TSE Dados Abertos)
rem Le perfil_eleitorado_2026.zip e perfil_comparecimento_abstencao_2026.zip
rem do Portal de Dados Abertos do TSE e grava web\perfil-eleitor.js. Ver LEIA-ME.txt.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0importar-perfil-eleitor.ps1" %*
pause
