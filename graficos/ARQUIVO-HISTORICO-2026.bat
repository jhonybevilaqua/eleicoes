@echo off
title gctse ARQUIVO HISTORICO 2026
rem Depois do 2o turno (resultado final): guarda o 1o e o 2o turno completos
rem do TSE (Brasil, estados, capitais, exterior, governadores, Camara,
rem Assembleias, 2022 e fotos), mais evolucao minuto a minuto, logs e dados
rem das telas, num .zip em "arquivo-historico" - base para 2028 e 2030.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0guardar-tse.ps1" -Historico
