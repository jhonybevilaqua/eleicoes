@echo off
setlocal
title TELAO - tela (PC de exibicao)
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem  Abre o telao em tela cheia, sem barra de navegacao e sem cursor. A saida
rem  de video deste PC entra no switcher como uma fonte qualquer.
rem
rem  Uso:
rem    TELAO-TELA.bat                 telao na pasta local
rem    TELAO-TELA.bat "\\PC-OPERACAO\gctse\TELAO\telao\index.html"
rem
rem  No segundo caso este PC nao precisa de nada instalado - so precisa
rem  enxergar a pasta compartilhada do PC que coleta.
rem
rem  Na propria tela:
rem    1..9      escolhe a tela
rem    setas     avanca / volta
rem    R         liga e desliga o rodizio automatico
rem    M         devolve o comando para a mesa
rem    D         mostra o rodape de conferencia
rem    Alt+F4    fecha
rem ---------------------------------------------------------------------------

set "PAGINA=%~1"
if "%PAGINA%"=="" set "PAGINA=%~dp0telao\index.html"

if not exist "%PAGINA%" (
  echo.
  echo  Nao encontrei a tela do telao em:
  echo    %PAGINA%
  echo.
  echo  Ela so existe depois que a coleta roda pelo menos uma vez.
  echo  Rode TELAO-COLETA.bat - ou TELAO-ENSAIO.bat, para testar sem o TSE.
  echo.
  echo  Se o telao esta em outro PC, passe o caminho:
  echo    TELAO-TELA.bat "\\PC-OPERACAO\gctse\TELAO\telao\index.html"
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
echo   TELAO NO AR - %PAGINA%
echo.
echo   1..9 escolhe   setas avancam   R rodizio   M volta p/ mesa
echo   D mostra o rodape de conferencia          Alt+F4 fecha
echo ================================================================
echo.

rem Perfil proprio: separa esta janela do navegador de uso comum do PC, para
rem uma aba aberta por alguem nao derrubar o que esta no ar.
start "" "%NAVEGADOR%" %ARGS% --user-data-dir="%TEMP%\telao-tela" "file:///%PAGINA:\=/%"
endlocal
