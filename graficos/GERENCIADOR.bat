@echo off
title gctse GERENCIADOR - deixe esta janela aberta
rem Tela de gerenciamento das saidas (DeckLink via OBS):
rem   - abre TODAS as coletas: Presidente (GRAFICOS.bat), estados (ESTADOS.bat)
rem     e municipios (MUNICIPIOS.bat), se nao estiverem rodando - e o
rem     gerenciador confere de novo e abre a que faltar
rem   - abre os dois OBS (saida horizontal e vertical), sozinho
rem   - liga o servidor do gerenciador (esta janela) e abre a pagina
rem     http://localhost:8098/gerenciador.html
cd /d "%~dp0"
rem 3.29.1: arquivos vindos de um .zip baixado ficam "bloqueados" pelo Windows
rem (pergunta "Deseja executar?" e a coleta nao abre): desbloqueia a pasta.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath (Get-Location) -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

powershell -NoProfile -Command "if ((Test-Path 'web\dados.js') -and ((Get-Date)-(Get-Item 'web\dados.js').LastWriteTime).TotalSeconds -lt 90) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto estados
echo Abrindo a coleta de Presidente - GRAFICOS.bat
start "gctse GRAFICOS" "%~dp0GRAFICOS.bat"

:estados
powershell -NoProfile -Command "if ((Test-Path 'web\estados.js') -and ((Get-Date)-(Get-Item 'web\estados.js').LastWriteTime).TotalSeconds -lt 90) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto municipios
echo Abrindo a coleta dos estados - ESTADOS.bat
start "gctse ESTADOS" "%~dp0ESTADOS.bat"

:municipios
rem 3.28: Presidente em cada cidade (tela Mapa por municipio)
powershell -NoProfile -Command "if ((Test-Path 'web\municipios.js') -and ((Get-Date)-(Get-Item 'web\municipios.js').LastWriteTime).TotalSeconds -lt 600) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto servidor
echo Abrindo a coleta dos municipios - MUNICIPIOS.bat
start "gctse MUNICIPIOS" "%~dp0MUNICIPIOS.bat"

:servidor
rem Os dois OBS (um por saida da DeckLink), automatico - ver OBS-DECKLINK.txt:
rem usa o OBS instalado, monta as copias e a configuracao na 1a vez e abre
rem os dois quando o servidor responder.
start "gctse OBS das saidas" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0obs-saidas.ps1" -Auto
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gerenciador.ps1" -AbrirPagina
:loop
echo.
echo O servidor do gerenciador encerrou. Reiniciando em 5s... (Ctrl+C para sair)
timeout /t 5 /nobreak >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gerenciador.ps1"
goto loop
