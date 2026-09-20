@echo off
setlocal
title TELAO - monitor vertical da cena
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem  Abre o monitor VERTICAL (1080x1920) em tela cheia. Ele roda sozinho, como
rem  apresentacao de slides, trocando de informacao a cada 10 segundos.
rem
rem  Nao ha mesa aqui: este monitor fica em cena o tempo todo, sem ninguem
rem  operando. Ele gira, e so.
rem
rem  Uso:
rem    TELAO-VERTICAL.bat             pasta local
rem    TELAO-VERTICAL.bat "\\PC-OPERACAO\gctse\TELAO\telao-vertical\index.html"
rem
rem  Na propria tela, so para conferencia no estudio:
rem    ESPACO    pausa e retoma o giro
rem    setas     avanca / volta na hora
rem    D         mostra o rodape de conferencia
rem    Alt+F4    fecha
rem
rem  IMPORTANTE: o monitor precisa estar configurado em RETRATO no Windows
rem  (Configuracoes > Sistema > Video > Orientacao: Retrato). Sem isso o
rem  Windows entrega 1920x1080 para o navegador e a tela sai com tarjas.
rem ---------------------------------------------------------------------------

set "PAGINA=%~1"
if "%PAGINA%"=="" set "PAGINA=%~dp0telao-vertical\index.html"

if not exist "%PAGINA%" (
  echo.
  echo  Nao encontrei o monitor vertical em:
  echo    %PAGINA%
  echo.
  echo  Ele so existe depois que a coleta roda pelo menos uma vez com
  echo  'vertical.ativo: true' no telao.yaml.
  echo  Rode TELAO-SIMULADO.bat, TELAO-PRODUCAO.bat ou TELAO-ENSAIO.bat.
  echo.
  pause
  exit /b 1
)

set "NAVEGADOR="
for %%C in (
  "%ProgramFiles%\Google\Chrome\Application\chrome.exe"
  "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
  "%LocalAppData%\Google\Chrome\Application\chrome.exe"
) do if not defined NAVEGADOR if exist %%C set "NAVEGADOR=%%~C"

set "ARGS=--kiosk --force-device-scale-factor=1 --disable-pinch --noerrdialogs --disable-infobars --no-first-run --disable-session-crashed-bubble"

if not defined NAVEGADOR (
  for %%C in (
    "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
    "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
  ) do if not defined NAVEGADOR if exist %%C (
    set "NAVEGADOR=%%~C"
    set "ARGS=--kiosk --edge-kiosk-type=fullscreen --force-device-scale-factor=1 --noerrdialogs --no-first-run"
  )
)

if not defined NAVEGADOR (
  echo.
  echo  Nao encontrei Chrome nem Edge neste PC.
  echo  Abra o arquivo abaixo no navegador e aperte F11:
  echo    %PAGINA%
  echo.
  pause
  exit /b 1
)

echo ================================================================
echo   MONITOR VERTICAL - %PAGINA%
echo.
echo   Roda sozinho. ESPACO pausa, setas avancam, D confere.
echo   Confira se o monitor esta em RETRATO nas configuracoes do Windows.
echo ================================================================
echo.

rem --window-position joga a janela no monitor da direita. Ajuste o X para o
rem seu arranjo: 1920 supoe o monitor vertical a direita de um Full HD.
start "" "%NAVEGADOR%" %ARGS% --window-position=1920,0 --user-data-dir="%TEMP%\telao-vertical" "file:///%PAGINA:\=/%"
endlocal
