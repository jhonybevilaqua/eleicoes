@echo off
cd /d "%~dp0"
echo Gerando os arquivos de exemplo e o mapa de vinculos...
echo.
gctse.exe exemplo
echo.
echo Abra a pasta exemplos\ e use os arquivos para montar a cena no LiveBoard.
echo O mapa de qual campo esta onde fica em exemplos\mapa\.
echo.
pause
