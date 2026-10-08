<#
    gctse GRAFICOS - CODIGOS DO 2o TURNO (CODIGOS-2-TURNO.bat)

    Le a lista de eleicoes do PROPRIO TSE ({base_url}/comum/config/ele-c.json,
    o mesmo arquivo que as tarjas usam) e mostra o codigo de cada eleicao
    geral: Presidente (cargo 1) e Governador (cargo 3), por pleito e data.
    Se achar o pleito do 2o turno (data 25/10/2026, com Presidente e
    Governador), oferece gravar no config-graficos.json:
        eleicao_presidente  e  eleicao_estaduais  = codigos do 2o turno
        *_1turno e eleicao_camara                 = ficam com os do 1o turno
    Antes de gravar, guarda uma copia do config (config-graficos.ANTES-2T.json).
    Nada e digitado na mao e nada e inventado: sem o pleito na lista do TSE,
    nao grava.
#>
param([string] $Data = "25/10/2026", [switch] $SoMostrar)
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
function Prop($o, [string] $n) { return ($null -ne $o -and $null -ne $o.PSObject.Properties[$n]) }
function Campo($o, [string] $n) { if (Prop $o $n) { return "$($o.$n)" } return "" }

$arqCfg = Join-Path $Raiz "config-graficos.json"
$cfg = Get-Content $arqCfg -Raw -Encoding UTF8 | ConvertFrom-Json
$base = "$($cfg.tse.base_url)".TrimEnd('/')
$url = "$base/comum/config/ele-c.json"
Write-Host "Lendo a lista de eleicoes do TSE: $url" -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri $url -TimeoutSec 20 -UseBasicParsing -Headers @{ "User-Agent" = "gctse-graficos/1.0"; "Accept" = "application/json,*/*" }
    $bytes = $resp.RawContentStream.ToArray()
    $lista = ([Text.Encoding]::UTF8.GetString($bytes)) | ConvertFrom-Json
} catch {
    Write-Host "Nao consegui ler: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Confira a internet e o base_url do config-graficos.json. NADA foi alterado." -ForegroundColor Yellow
    exit 1
}
if (-not (Prop $lista "pl")) { Write-Host "O arquivo do TSE nao trouxe a lista de pleitos (campo pl). NADA foi alterado." -ForegroundColor Red; exit 1 }

# pleitos com eleicao geral (Presidente 1 / Governador 3 / Senador 5)
$achados = @()
foreach ($pl in $lista.pl) {
    if (-not (Prop $pl "e")) { continue }
    $porCargo = @{}
    foreach ($e in $pl.e) {
        $cargos = @()
        if (Prop $e "abr") { foreach ($a in $e.abr) { if (Prop $a "cp") { foreach ($c in $a.cp) { $cargos += (Campo $c "cd") } } } }
        foreach ($k in @("1", "3", "5")) { if ($cargos -contains $k -and -not $porCargo.ContainsKey($k)) { $porCargo[$k] = (Campo $e "cd") } }
    }
    if ($porCargo.Count) { $achados += [pscustomobject]@{ pleito = (Campo $pl "cd"); data = (Campo $pl "dt"); pres = $porCargo["1"]; gov = $porCargo["3"]; sen = $porCargo["5"] } }
}
Write-Host ""
Write-Host "Pleitos com eleicao geral na lista do TSE:" -ForegroundColor White
foreach ($a in $achados) {
    Write-Host ("  pleito {0,-6} data {1,-12} Presidente {2,-6} Governador {3,-6} Senador {4}" -f $a.pleito, $a.data, $(if ($a.pres) { $a.pres } else { "-" }), $(if ($a.gov) { $a.gov } else { "-" }), $(if ($a.sen) { $a.sen } else { "-" }))
}
Write-Host ""
Write-Host ("No config hoje: eleicao_presidente {0} | eleicao_estaduais {1} | 1o turno: {2} / {3} | camara {4}" -f (Campo $cfg.tse "eleicao_presidente"), (Campo $cfg.tse "eleicao_estaduais"),
    (Campo $cfg.tse "eleicao_presidente_1turno"), (Campo $cfg.tse "eleicao_estaduais_1turno"), (Campo $cfg.tse "eleicao_camara")) -ForegroundColor Gray

$t2 = @($achados | Where-Object { $_.data -like "*$Data*" -and $_.pres -and $_.gov })
if ($t2.Count -ne 1) {
    Write-Host ""
    if ($t2.Count -eq 0) { Write-Host "O TSE ainda NAO publicou o pleito de $Data com Presidente e Governador. Rode de novo mais perto do dia. NADA foi alterado." -ForegroundColor Yellow }
    else { Write-Host "Ha $($t2.Count) pleitos de $Data - confira com a engenharia antes de mudar. NADA foi alterado." -ForegroundColor Yellow }
    exit 2
}
$x = $t2[0]
$pres1 = $(if (Campo $cfg.tse "eleicao_presidente_1turno") { Campo $cfg.tse "eleicao_presidente_1turno" } else { Campo $cfg.tse "eleicao_presidente" })
$est1 = $(if (Campo $cfg.tse "eleicao_estaduais_1turno") { Campo $cfg.tse "eleicao_estaduais_1turno" } else { Campo $cfg.tse "eleicao_estaduais" })
$cam = $(if (Campo $cfg.tse "eleicao_camara") { Campo $cfg.tse "eleicao_camara" } else { $est1 })
Write-Host ""
Write-Host "2o TURNO ENCONTRADO NO TSE: pleito $($x.pleito) ($($x.data))" -ForegroundColor Green
Write-Host "  eleicao_presidente ........ $($x.pres)   (1o turno fica: $pres1)" -ForegroundColor Green
Write-Host "  eleicao_estaduais ......... $($x.gov)   (1o turno fica: $est1)" -ForegroundColor Green
Write-Host "  eleicao_camara ............ $cam   (Camara so tem 1o turno)" -ForegroundColor Green
if ((Campo $cfg.tse "eleicao_presidente") -eq $x.pres -and (Campo $cfg.tse "eleicao_estaduais") -eq $x.gov) {
    Write-Host ""; Write-Host "O config JA esta com os codigos do 2o turno. Nada a fazer." -ForegroundColor Green; exit 0
}
if ($SoMostrar) { exit 0 }
Write-Host ""
$r = Read-Host "Gravar estes codigos no config-graficos.json? (S/N)"
if ($r -notmatch '^[sS]') { Write-Host "Nada foi alterado." -ForegroundColor Yellow; exit 0 }

Copy-Item -LiteralPath $arqCfg -Destination (Join-Path $Raiz "config-graficos.ANTES-2T.json") -Force
foreach ($par in @(@("eleicao_presidente_1turno", $pres1), @("eleicao_estaduais_1turno", $est1), @("eleicao_camara", $cam), @("eleicao_presidente", $x.pres), @("eleicao_estaduais", $x.gov))) {
    $cfg.tse | Add-Member -NotePropertyName $par[0] -NotePropertyValue "$($par[1])" -Force
}
[IO.File]::WriteAllText($arqCfg, ($cfg | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
Write-Host ""
Write-Host "GRAVADO. Copia do anterior: config-graficos.ANTES-2T.json" -ForegroundColor Green
Write-Host "FECHE e ABRA de novo o GRAFICOS.bat e o ESTADOS.bat para valer." -ForegroundColor Yellow
