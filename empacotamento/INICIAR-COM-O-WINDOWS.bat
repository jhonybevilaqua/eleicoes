@echo off
REM Faz o INICIAR.bat subir sozinho (minimizado) quando alguem logar.
cd /d "%~dp0"
set "PASTA=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "ATALHO=%PASTA%\gctse.lnk"
choice /c SN /m "Criar atalho de inicializacao para INICIAR.bat"
if errorlevel 2 exit /b 0
powershell -NoProfile -Command ^
  "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%ATALHO%');" ^
  "$s.TargetPath='%~dp0INICIAR.bat'; $s.WorkingDirectory='%~dp0';" ^
  "$s.WindowStyle=7; $s.Save()"
if exist "%ATALHO%" (echo Pronto.) else (echo Falhou. Crie a mao em shell:startup.)
pause
