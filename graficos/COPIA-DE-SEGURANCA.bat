@echo off
title gctse COPIA DE SEGURANCA
rem Guarda a pasta inteira (programas, config, dados lidos do TSE, evolucao
rem minuto a minuto, logs) num .zip com data e hora em "copias-de-seguranca".
rem Pode rodar com tudo aberto. Tambem ha o botao no gerenciador.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0copia-seguranca.ps1"
