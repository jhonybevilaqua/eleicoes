@echo off
title gctse - enderecos para o OBS
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = 8098; try { $c = Get-Content 'config-graficos.json' -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($x in $c.PSObject.Properties) { if ($x.Name -eq 'porta_gerenciador' -and [int] $x.Value -gt 0) { $p = [int] $x.Value } } } catch { }; $l = @('Cada OBS tem UMA fonte Navegador (desmarque Arquivo local), com o endereco:', '', ('  OBS da SAIDA HORIZONTAL:  http://localhost:{0}/saida.html?saida=h   (largura 1920, altura 1080)' -f $p), ('  OBS da SAIDA VERTICAL:    http://localhost:{0}/saida.html?saida=v   (largura 1080, altura 1920, girar 90 graus)' -f $p), '', ('Tela de gerenciamento (Chrome, monitor do Windows): http://localhost:{0}/gerenciador.html' -f $p), '', 'O GERENCIADOR.bat precisa estar aberto.'); $l | Set-Content -Encoding UTF8 'ENDERECOS-OBS.txt'; $l"
echo.
echo Os enderecos tambem foram gravados em ENDERECOS-OBS.txt. Passo a passo: OBS-DECKLINK.txt
pause
