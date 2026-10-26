@echo off
title gctse REPRISE DA NOITE (treino - NAO VAI AO AR)
rem Reproduz a apuracao do Presidente com o Historico de totalizacao do TSE
rem (Dados Abertos), acelerada, numa copia separada (pasta reprise). Para
rem treinar a equipe. Ver LEIA-ME.txt. Fechar esta janela para parar.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reprise.ps1" %*
pause
