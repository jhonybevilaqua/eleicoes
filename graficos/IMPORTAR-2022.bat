@echo off
title gctse - IMPORTAR 2022 (TSE Dados Abertos)
rem Le votacao_candidato_munzona_2022.zip e detalhe_votacao_munzona_2022.zip
rem do Portal de Dados Abertos do TSE e grava dados-2022.json. Ver LEIA-ME.txt.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0importar-2022.ps1" %*
pause
