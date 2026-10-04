@echo off
title gctse - enderecos das telas para o OBS
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$web = Join-Path (Get-Location) 'web'; $itens = @(@('SAIDA 1 - HORIZONTAL (fonte Navegador 1920 x 1080)', ''), @('  Apresentacao', 'apresentacao-horizontal.html'), @('  Giro dos estados', 'giro-estados-horizontal.html'), @('  Resumo (7 telas)', 'resumo-horizontal.html'), @('', ''), @('SAIDA 2 - VERTICAL (fonte Navegador 1080 x 1920, girada 90 graus no OBS)', ''), @('  Apresentacao', 'apresentacao-vertical.html'), @('  Giro dos estados', 'giro-estados-vertical.html'), @('  Resumo (7 telas)', 'resumo-vertical.html'), @('', ''), @('GERENCIAMENTO - abrir no Chrome, no monitor do Windows', ''), @('  Pagina do operador', 'index.html')); $linhas = foreach ($x in $itens) { if ($x[1]) { $c = ((Join-Path $web $x[1]) -replace '\\', '/').TrimStart('/'); $u = 'file:///' + ((($c.Split('/')) | ForEach-Object { if ($_ -match '^[A-Za-z]:$') { $_ } else { [uri]::EscapeDataString($_) } }) -join '/'); '{0,-22} {1}' -f $x[0], $u } else { $x[0] } }; $linhas | Set-Content -Encoding UTF8 'ENDERECOS-OBS.txt'; $linhas"
echo.
echo Os enderecos tambem foram gravados em ENDERECOS-OBS.txt (para copiar e colar no OBS).
echo Passo a passo completo: OBS-DECKLINK.txt
pause
