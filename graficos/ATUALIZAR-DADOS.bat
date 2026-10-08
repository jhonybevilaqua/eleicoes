@echo off
title gctse - ATUALIZAR DADOS DO TSE
rem Roda em sequencia: GUARDAR-DADOS-TSE, IMPORTAR-CANDIDATOS e
rem IMPORTAR-PERFIL-ELEITOR. Tambem pelo botao "dados do TSE" do gerenciador.
rem So uma etapa: ATUALIZAR-DADOS.bat perfil  (ou tse, candidatos)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizar-dados.ps1" %*
