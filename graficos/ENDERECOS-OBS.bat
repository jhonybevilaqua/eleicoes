@echo off
title gctse - enderecos para o OBS
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = 8098; try { $c = Get-Content 'config-graficos.json' -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($x in $c.PSObject.Properties) { if ($x.Name -eq 'porta_gerenciador' -and [int] $x.Value -gt 0) { $p = [int] $x.Value } } } catch { }; $l = @('O GERENCIADOR.bat ja configura os dois OBS sozinho. So para montar na mao (outro OBS / vMix):', 'UMA fonte Navegador (desmarque Arquivo local), largura 1920, altura 1080:', '', ('  SAIDA HORIZONTAL:  http://localhost:{0}/saida.html?saida=h' -f $p), ('  SAIDA VERTICAL:    http://localhost:{0}/saida.html?saida=v&obs=1   (ja vem girada; sentido: botoes no gerenciador)' -f $p), '', 'Captura de janela (plano B): abra estes enderecos no Chrome e aperte F11:', ('  http://localhost:{0}/saida.html?saida=h    e    http://localhost:{0}/saida.html?saida=v' -f $p), '', ('Tela de gerenciamento (Chrome, monitor do Windows): http://localhost:{0}/gerenciador.html' -f $p), '', 'O GERENCIADOR.bat precisa estar aberto.'); $l | Set-Content -Encoding UTF8 'ENDERECOS-OBS.txt'; $l"
echo.
echo Os enderecos tambem foram gravados em ENDERECOS-OBS.txt. Passo a passo: OBS-DECKLINK.txt
pause
