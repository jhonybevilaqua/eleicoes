@echo off
title gctse GUARDAR DADOS DO TSE
rem Copia para o disco (pasta tse-local e web\fotos-tse) os boletins do 1o
rem turno, os de 2022 e as fotos dos eleitos. Se o TSE parar de entregar no
rem dia do 2o turno, GRAFICOS.bat e ESTADOS.bat usam esta copia sozinhos.
rem Sem fotos: GUARDAR-DADOS-TSE.bat semfotos
cd /d "%~dp0"
if /i "%1"=="semfotos" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0guardar-tse.ps1" -SemFotos
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0guardar-tse.ps1"
)
