@echo off
cd /d "%~dp0"
echo ================================================================
echo  ENSAIO - dados INVENTADOS, apuracao completa em 10 minutos.
echo  Nao consulta o TSE. Nao coloque esta saida no ar.
echo  Ctrl+C encerra.
echo ================================================================
echo.
gctse.exe ensaio --duracao 600
echo.
pause
