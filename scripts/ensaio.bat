@echo off
REM Ensaio com dados simulados - nao consulta o TSE.
setlocal
cd /d "%~dp0.."
.venv\Scripts\python.exe -m gctse -c config\config.yaml ensaio --duracao 600
