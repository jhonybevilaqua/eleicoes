@echo off
title gctse LIBERAR CONTROLE PELO iPAD
rem Uma vez, COMO ADMINISTRADOR: libera a porta do gerenciador (8098) para a
rem rede interna (iPad no Wi-Fi da emissora) e abre o firewall SO para redes
rem privadas/dominio. Depois, no config-graficos.json:
rem    "acesso_rede": true,
rem    "senha_controle": "uma senha de 4+ caracteres"   (um iPad so)
rem ou "usuarios": [ ... ]  (varias pessoas, cada uma com sua senha - LEIA-ME 3.18)
rem e reabra o GERENCIADOR.bat. Desfazer: LIBERAR-IPAD.bat desfazer
net session >nul 2>&1
if errorlevel 1 (
  echo Pedindo permissao de administrador...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%1' -Verb RunAs"
  exit /b
)
set PORTA=8098
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "try { $c = Get-Content '%~dp0config-graficos.json' -Raw | ConvertFrom-Json; if ($c.porta_gerenciador) { $c.porta_gerenciador } else { 8098 } } catch { 8098 }"`) do set PORTA=%%p
if /i "%1"=="desfazer" (
  netsh http delete urlacl url=http://+:%PORTA%/
  netsh advfirewall firewall delete rule name="gctse gerenciador %PORTA%"
  echo Desfeito.
  pause
  exit /b
)
netsh http delete urlacl url=http://+:%PORTA%/ >nul 2>&1
netsh http add urlacl url=http://+:%PORTA%/ sddl=D:(A;;GX;;;WD)
netsh advfirewall firewall delete rule name="gctse gerenciador %PORTA%" >nul 2>&1
netsh advfirewall firewall add rule name="gctse gerenciador %PORTA%" dir=in action=allow protocol=TCP localport=%PORTA% profile=private,domain
echo.
echo Pronto. Enderecos deste PC na rede (use no iPad: http://ENDERECO:%PORTA%/controle.html):
powershell -NoProfile -Command "[Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { '   ' + $_.ToString() }"
echo.
echo Agora: "acesso_rede": true e "senha_controle" no config-graficos.json e reabra o GERENCIADOR.bat.
pause
