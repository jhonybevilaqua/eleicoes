@echo off
title gctse RESUMO - HORIZONTAL
rem 5 telas de fechamento: mapa dos governadores, governadores e senado por
rem partido, Presidente por regiao, comparecimento. Teclas 1 a 5 vao direto.
rem Troca de tela: seta direita/esquerda, clique (botao direito volta),
rem roda do mouse ou passador de slides.
rem ENTER liga/desliga o giro automatico. Alt+F4 fecha.
rem Abre tambem ESTADOS.bat e GRAFICOS.bat se nao estiverem rodando.
rem
rem Mais de um monitor: MONITOR_X,MONITOR_Y = um ponto dentro do monitor
rem onde a tela deve abrir (principal = 0,0; a direita de um 1920 = 1920,0).
set MONITOR_X=0
set MONITOR_Y=0

cd /d "%~dp0"
powershell -NoProfile -Command "if ((Test-Path 'web\estados.js') -and ((Get-Date)-(Get-Item 'web\estados.js').LastWriteTime).TotalSeconds -lt 90) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto navegador
echo Abrindo a coleta dos estados - ESTADOS.bat
start "gctse ESTADOS" "%~dp0ESTADOS.bat"
timeout /t 6 /nobreak >nul

:navegador
powershell -NoProfile -Command "if ((Test-Path 'web\dados.js') -and ((Get-Date)-(Get-Item 'web\dados.js').LastWriteTime).TotalSeconds -lt 90) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto navegador2
echo Abrindo a coleta de Presidente - GRAFICOS.bat
start "gctse GRAFICOS" "%~dp0GRAFICOS.bat"
timeout /t 6 /nobreak >nul

:navegador2
set "PAGINA=%~dp0web\resumo-horizontal.html"
set "PERFIL=%~dp0navegador-resumo-horizontal"
set "NAV="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "NAV=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined NAV if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "NAV=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined NAV if exist "%LocalAppData%\Google\Chrome\Application\chrome.exe" set "NAV=%LocalAppData%\Google\Chrome\Application\chrome.exe"
if not defined NAV if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "NAV=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined NAV if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "NAV=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if defined NAV goto abrir
echo Nao achei o Chrome nem o Edge. Abra no navegador e aperte F11:
echo   "%PAGINA%"
pause
exit /b

:abrir
start "" "%NAV%" --user-data-dir="%PERFIL%" --kiosk --edge-kiosk-type=fullscreen --no-first-run --no-default-browser-check --hide-crash-restore-bubble --disable-session-crashed-bubble --disable-translate --disable-features=Translate --window-position=%MONITOR_X%,%MONITOR_Y% "%PAGINA%"
