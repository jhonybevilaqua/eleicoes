@echo off
setlocal
title gctse - tela do mapa (PC de exibicao)
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem  Abre o mapa em tela cheia, sem barra de navegacao e sem cursor, para a
rem  saida de video deste PC entrar no switcher como uma fonte qualquer.
rem
rem  A pagina se atualiza sozinha. Nao ha nada para montar no GC: o desenho
rem  chega pronto.
rem
rem  Uso:
rem    TELA-MAPA.bat                          usa a pasta local de saida
rem    TELA-MAPA.bat "\\PC-OPERACAO\gctse\dados\saida\mapa\mapa-presidente.html"
rem
rem  No segundo caso, este PC nao precisa do gctse instalado - so precisa
rem  enxergar a pasta compartilhada do PC que coleta.
rem ---------------------------------------------------------------------------

set "PAGINA=%~1"
if "%PAGINA%"=="" set "PAGINA=%~dp0dados\saida\mapa\mapa-presidente.html"
if not exist "%PAGINA%" set "PAGINA=%~dp0TARJAS\mapa\mapa-presidente.html"

if not exist "%PAGINA%" (
  echo.
  echo  Nao encontrei a tela do mapa.
  echo.
  echo  Procurei em:
  echo    %~dp0dados\saida\mapa\mapa-presidente.html
  echo    %~dp0TARJAS\mapa\mapa-presidente.html
  echo.
  echo  O arquivo so existe depois que o gctse roda pelo menos uma vez com
  echo  'tela' na lista de formatos do exporter de mapa. Rode INICIAR.bat, ou
  echo  passe o caminho como parametro:
  echo.
  echo    TELA-MAPA.bat "\\PC-OPERACAO\gctse\dados\saida\mapa\mapa-presidente.html"
  echo.
  pause
  exit /b 1
)

rem Chrome primeiro, Edge como alternativa - o Edge existe em todo Windows 10/11.
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
  echo  Abra o arquivo abaixo manualmente no navegador e aperte F11:
  echo    %PAGINA%
  echo.
  pause
  exit /b 1
)

echo ================================================================
echo   TELA DO MAPA - %PAGINA%
echo.
echo   Tela cheia. Alt+F4 fecha.
echo   A pagina se atualiza sozinha; nao precisa recarregar.
echo   Para conferir se esta atualizando, feche e rode:
echo     TELA-MAPA.bat "%PAGINA%?debug=1"
echo ================================================================
echo.

rem Perfil proprio: separa esta janela do navegador de uso comum do PC, para
rem uma aba aberta por alguem nao derrubar o que esta no ar.
start "" "%NAVEGADOR%" %ARGS% --user-data-dir="%TEMP%\gctse-tela" "file:///%PAGINA:\=/%"
endlocal
