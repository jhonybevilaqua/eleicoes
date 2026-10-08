<#
    gctse GRAFICOS - ENSAIO GERAL (ENSAIO.bat)

    Treino da equipe com uma noite de 2o turno SIMULADA, sem risco de ir ao ar:
      1. copia o sistema para a pasta "ensaio" (sem os dados reais)
      2. liga o TSE simulado (ensaio-tse.ps1, porta 8799 - dados FICTICIOS)
      3. abre as duas coletas (Presidente e estados) lendo o simulado
      4. abre o gerenciador do ensaio na porta 8096 - o OBS usa a 8098, entao
         nada do ensaio chega na DeckLink
    Toda tela sai riscada "ENSAIO - DADOS FICTICIOS - NAO VAI AO AR".
    ENTER nesta janela encerra o ensaio e fecha tudo o que ele abriu.
#>
param([double] $Minutos = 20)
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dest = Join-Path $Raiz "ensaio"
$Marca = "PASTA-DO-ENSAIO.txt"
$PortaTse = 8799
$PortaGer = 8096

function Aviso([string] $txt, [string] $cor = "Gray") { Write-Host ("{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $txt) -ForegroundColor $cor }

Write-Host ""
Write-Host "  ==========================================================" -ForegroundColor Yellow
Write-Host "   ENSAIO GERAL - 2o TURNO SIMULADO  (dados ficticios)" -ForegroundColor Yellow
Write-Host "   Nada daqui vai ao ar: o gerenciador do ensaio e outro." -ForegroundColor Yellow
Write-Host "  ==========================================================" -ForegroundColor Yellow
Write-Host ""

# 1. copia limpa (so apaga a pasta se ela for mesmo a do ensaio)
if (Test-Path $Dest) {
    if (-not (Test-Path (Join-Path $Dest $Marca))) {
        Aviso "Ja existe uma pasta 'ensaio' que nao foi criada pelo ENSAIO.bat. Renomeie-a e tente de novo." "Red"
        exit 1
    }
    Remove-Item -LiteralPath $Dest -Recurse -Force
}
New-Item -ItemType Directory -Path $Dest | Out-Null
Set-Content -Path (Join-Path $Dest $Marca) -Value "Pasta criada pelo ENSAIO.bat - apagada e recriada a cada ensaio. Nao guarde nada aqui." -Encoding ASCII
$fora = @("ENSAIO.bat", "ensaio.ps1", "web\dados.js", "web\estados.js", "web\candidatos-genero.js", "gerenciador-estado.json", "obs-saidas.json", $Marca)
$pastasFora = @("ensaio", "logs", "importar", "obs", "copias-de-seguranca", "tse-local")
foreach ($item in Get-ChildItem -LiteralPath $Raiz -Recurse -Force) {
    $rel = $item.FullName.Substring($Raiz.Length).TrimStart('\', '/')
    $topo = ($rel -split '[\\/]')[0]
    if ($pastasFora -contains $topo) { continue }
    if ($fora -contains ($rel -replace '/', '\')) { continue }
    if (($rel -replace '/', '\') -like "web\fotos-tse*") { continue }   # fotos guardadas do TSE real
    if ($item.Name -like "evolucao-*.json" -or $item.Name -like "cores-atribuidas-*.json") { continue }
    $alvo = Join-Path $Dest $rel
    if ($item.PSIsContainer) { if (-not (Test-Path $alvo)) { New-Item -ItemType Directory -Path $alvo | Out-Null } }
    else { Copy-Item -LiteralPath $item.FullName -Destination $alvo -Force }
}

# 2. configuracao do ensaio: a do sistema, apontando para o TSE simulado
$cfg = Get-Content (Join-Path $Raiz "config-graficos.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$cfg.tse = [pscustomobject][ordered]@{
    base_url = "http://localhost:$PortaTse"; ciclo = "ele2026"
    eleicao_presidente = "9262"; eleicao_presidente_1turno = "9257"
    eleicao_estaduais = "9263"; eleicao_estaduais_1turno = "9259"; eleicao_camara = "9259"
}
$cfg | Add-Member -NotePropertyName ensaio -NotePropertyValue $true -Force
$cfg | Add-Member -NotePropertyName porta_gerenciador -NotePropertyValue $PortaGer -Force
$cfg | Add-Member -NotePropertyName intervalo_segundos -NotePropertyValue 10 -Force
$cfg | Add-Member -NotePropertyName intervalo_estados_segundos -NotePropertyValue 15 -Force
$json = $cfg | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText((Join-Path $Dest "config-graficos.json"), $json, (New-Object Text.UTF8Encoding($false)))
Aviso "Copia do sistema pronta em: $Dest" "Green"

# 3. abre tudo (cada um na sua janela) e guarda quem abriu, para fechar no fim
$ps = "powershell"
if ($env:WINDIR -and (Test-Path (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"))) { $ps = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe" }
$abertos = @()
function Abrir([string] $titulo, [string] $arq, [string] $extra) {
    $cmd = "`$host.UI.RawUI.WindowTitle = 'ENSAIO - $titulo'; & '" + ((Join-Path $Dest $arq) -replace "'", "''") + "' $extra"
    return Start-Process -FilePath $ps -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-Command", $cmd) -WorkingDirectory $Dest -PassThru
}
$abertos += Abrir "TSE SIMULADO" "ensaio-tse.ps1" "-Porta $PortaTse -Minutos $($Minutos.ToString([Globalization.CultureInfo]::InvariantCulture))"
Start-Sleep -Seconds 3
$abertos += Abrir "PRESIDENTE" "graficos.ps1" ""
$abertos += Abrir "ESTADOS" "estados.ps1" ""
Start-Sleep -Seconds 4
$abertos += Abrir "GERENCIADOR" "gerenciador.ps1" "-AbrirPagina"

Write-Host ""
Aviso "ENSAIO NO AR (so nesta maquina):" "Yellow"
Aviso "  gerenciador do ensaio ... http://localhost:$PortaGer/gerenciador.html" "Cyan"
Aviso "  saida horizontal ....... http://localhost:$PortaGer/saida.html?saida=h" "Cyan"
Aviso "  saida vertical ......... http://localhost:$PortaGer/saida.html?saida=v" "Cyan"
Aviso "A apuracao simulada vai de 0 a 100% em $Minutos minutos (virada no meio, ELEITO no fim)." "Gray"
Aviso "O gerenciador de verdade (8098) e o OBS NAO recebem nada do ensaio." "Gray"
Write-Host ""
Read-Host "Aperte ENTER para ENCERRAR o ensaio e fechar as janelas dele" | Out-Null

foreach ($p in $abertos) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { } }
Aviso "Ensaio encerrado. A pasta 'ensaio' pode ficar; ela e recriada a cada ensaio." "Green"
