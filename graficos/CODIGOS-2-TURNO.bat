@echo off
title gctse CODIGOS DO 2o TURNO
rem Le a lista de eleicoes do proprio TSE e mostra os codigos do 2o turno
rem (Presidente e Governador). Se achar, oferece gravar no
rem config-graficos.json (guarda copia do anterior). Nada e digitado na mao.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0codigos-2turno.ps1"
pause
