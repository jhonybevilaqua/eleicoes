@echo off
REM Faz o gctse subir sozinho quando o Windows iniciar.
REM
REM Cria um atalho para 4-rodar.bat na pasta de Inicializar do usuario atual.
REM E o caminho mais confiavel em maquina de operacao com login automatico:
REM roda dentro da sessao do usuario, entao enxerga as pastas de rede que o
REM usuario enxerga. Tarefa agendada rodando como SYSTEM NAO enxerga.
REM
REM Para desfazer: apague o atalho da pasta que este script abre no fim.
setlocal
cd /d "%~dp0"

if not exist "%~dp04-rodar.bat" (
    echo ERRO: 4-rodar.bat nao encontrado nesta pasta.
    pause
    exit /b 1
)

set "INICIALIZAR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "ATALHO=%INICIALIZAR%\gctse - apuracao TSE.lnk"

echo Vai criar:
echo   %ATALHO%
echo apontando para:
echo   %~dp04-rodar.bat
echo.
choice /c SN /m "Confirma"
if errorlevel 2 exit /b 0

powershell -NoProfile -Command ^
  "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%ATALHO%');" ^
  "$s.TargetPath='%~dp04-rodar.bat';" ^
  "$s.WorkingDirectory='%~dp0';" ^
  "$s.Description='Apuracao TSE para o GC';" ^
  "$s.Save()"

if exist "%ATALHO%" (
    echo.
    echo Pronto. O sistema sobe no proximo login.
    echo Para desfazer, apague o atalho da pasta que vai abrir.
    explorer "%INICIALIZAR%"
) else (
    echo.
    echo Nao foi possivel criar o atalho. Crie manualmente:
    echo   1. Win+R, digite: shell:startup
    echo   2. Arraste 4-rodar.bat para la segurando Alt ^(cria atalho^)
)
pause
