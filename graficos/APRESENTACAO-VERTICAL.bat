@echo off
rem gctse GRAFICOS - apresentacao VERTICAL em tela cheia, troca a cada 15 s.
rem O GRAFICOS.bat precisa estar aberto (ele busca os dados do TSE).
rem Tempo, ordem e rotacao: web\apresentacao-config.js
rem
rem Mais de um monitor: a tela cheia abre no monitor onde esta o ponto
rem MONITOR_X,MONITOR_Y (canto de cima/esquerda de cada monitor em
rem Configuracoes > Sistema > Tela). Monitor principal = 0,0.
rem Ex.: monitor a direita de um 1920x1080 principal = 1920,0
set MONITOR_X=0
set MONITOR_Y=0

cd /d "%~dp0"
set "PAGINA=%~dp0web\apresentacao-vertical.html"
set "PERFIL=%~dp0navegador-vertical"

set "NAV="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "NAV=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined NAV if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "NAV=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined NAV if exist "%LocalAppData%\Google\Chrome\Application\chrome.exe" set "NAV=%LocalAppData%\Google\Chrome\Application\chrome.exe"
if not defined NAV if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "NAV=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined NAV if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "NAV=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if defined NAV goto abrir
echo Nao achei o Chrome nem o Edge neste computador.
echo Abra no navegador o arquivo abaixo e aperte F11:
echo   "%PAGINA%"
pause
exit /b

:abrir

rem Perfil proprio: abre uma janela nova em tela cheia mesmo com o
rem navegador ja aberto. Para sair da tela cheia: Alt+F4.
start "" "%NAV%" --user-data-dir="%PERFIL%" --kiosk --edge-kiosk-type=fullscreen --no-first-run --no-default-browser-check --disable-translate --disable-features=Translate --window-position=%MONITOR_X%,%MONITOR_Y% "%PAGINA%"
