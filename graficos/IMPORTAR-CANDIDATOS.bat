@echo off
title gctse - IMPORTAR CANDIDATOS (genero, TSE Dados Abertos)
rem Le consulta_cand_2026.zip (e 2022) do Portal de Dados Abertos do TSE
rem e grava web\candidatos-genero.js. Ver LEIA-ME.txt.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0importar-candidatos.ps1" %*
pause
