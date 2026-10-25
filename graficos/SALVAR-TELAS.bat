@echo off
title gctse SALVAR TODAS AS TELAS (PNG com fotos)
rem Grava todas as telas que tem dado em PNG Full HD, com as fotos dos
rem candidatos, em TELAS-SALVAS\data_hora. Para o Jornalismo usar depois da
rem eleicao: rode depois de 100% das urnas. Tambem ha o botao no gerenciador.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0salvar-telas.ps1"
