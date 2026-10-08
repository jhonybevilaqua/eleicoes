<#
    gctse GRAFICOS - GUARDAR DADOS DO TSE (GUARDAR-DADOS-TSE.bat)

    Copia para o disco, na pasta "tse-local", os boletins do 1o TURNO que o
    sistema usa no 2o turno (Presidente Brasil e 27 estados; Governador,
    Senador, Deputado Federal, Deputado Estadual/Distrital dos 27 estados),
    os de 2022 usados nas comparacoes e a lista de eleicoes do TSE.
    Com a opcao de fotos (padrao), guarda tambem em web\fotos-tse as fotos
    dos candidatos a Presidente, dos governadores e senadores eleitos (e dos
    que vao ao 2o turno) e dos deputados federais eleitos.

    No dia: se o TSE parar de entregar algum desses boletins (fora do ar,
    404, sem resposta), GRAFICOS.bat e ESTADOS.bat usam a copia daqui - e o
    gerenciador avisa "usando copia local". O 2o turno e sempre ao vivo.
    Os arquivos sao os do proprio TSE, sem nenhuma alteracao.
    Pode rodar de novo quantas vezes quiser (atualiza a copia).
#>
param([switch] $SemFotos, [switch] $SemPausa)
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
$Local = Join-Path $Raiz "tse-local"
$PastaFotos = Join-Path $Raiz "web\fotos-tse"
$script:Diag = New-Object System.Collections.Generic.List[string]
function Anotar([string] $T, [string] $Cor = "Gray") { Write-Host $T -ForegroundColor $Cor; $script:Diag.Add(("{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $T)) }
function Prop($o, [string] $n) { if ($null -eq $o) { return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

$cfg = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Base = "$($cfg.tse.base_url)".TrimEnd('/')
$Ciclo = "$($cfg.tse.ciclo)"
function Cod([string] $n, [string] $padrao) { $v = "$(Prop $cfg.tse $n)"; if ($v) { return $v }; return $padrao }
$Pres1T = Cod "eleicao_presidente_1turno" (Cod "eleicao_presidente" "")
$Est1T = Cod "eleicao_estaduais_1turno" (Cod "eleicao_estaduais" "")
$Camara = Cod "eleicao_camara" $Est1T
$E2022 = "544"; $E2022T2 = "545"
$c22 = Prop $cfg "comparar_2022"
if ($c22) { if ("$(Prop $c22 'eleicao')") { $E2022 = "$(Prop $c22 'eleicao')" }; if ("$(Prop $c22 'eleicao_2turno')") { $E2022T2 = "$(Prop $c22 'eleicao_2turno')" } }
$UFs = @("ac","al","ap","am","ba","ce","df","es","go","ma","mt","ms","mg","pa","pb","pr","pe","pi","rj","rn","rs","ro","rr","sc","sp","se","to")

Write-Host ""
Write-Host "  GUARDAR DADOS DO TSE (copia local do 1o turno e de 2022)" -ForegroundColor Yellow
Anotar "TSE: $Base | ciclo $Ciclo | Presidente 1o turno $Pres1T | estaduais 1o turno $Est1T | Camara/Assembleias $Camara | 2022: $E2022 e $E2022T2"
if (-not $Pres1T -or -not $Est1T) { Anotar "codigos do 1o turno vazios no config-graficos.json - nada a fazer." "Red"; exit 1 }

function Url([string] $ciclo, [string] $ele, [string] $abr, [int] $cargo, [string] $suf = "u", [string] $pasta = "dados") {
    $e6 = "{0:000000}" -f [int] $ele; $c4 = "{0:0000}" -f $cargo
    return "$Base/$ciclo/$ele/$pasta/$abr/$abr-c$c4-e$e6-$suf.json"
}
$script:Ok = 0; $script:Falhou = New-Object System.Collections.Generic.List[string]
function Baixar([string] $U, [string] $Destino) {
    Start-Sleep -Milliseconds 120   # respiro: bem abaixo do limite do TSE
    try {
        $r = Invoke-WebRequest -Uri $U -Headers @{ "User-Agent" = "gctse-graficos/1.0"; "Accept" = "*/*" } -TimeoutSec 30 -UseBasicParsing
        $bytes = $r.RawContentStream.ToArray()
        if ($bytes.Length -lt 20) { throw "arquivo vazio" }
        $dir = Split-Path -Parent $Destino
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $tmp = "$Destino.baixando"
        [IO.File]::WriteAllBytes($tmp, $bytes)
        Move-Item -LiteralPath $tmp -Destination $Destino -Force   # so troca a copia antiga se veio inteiro
        $script:Ok++
        return $bytes
    } catch {
        $cod = ""; try { $cod = " (HTTP " + [int] $_.Exception.Response.StatusCode + ")" } catch { }
        $script:Falhou.Add("$U$cod")
        return $null
    }
}
function Guardar([string] $U) {
    $rel = $U.Substring($Base.Length).TrimStart('/')
    $b = Baixar $U (Join-Path $Local ($rel -replace '/', [IO.Path]::DirectorySeparatorChar))
    if ($null -eq $b) { return $null }
    try { return [Text.Encoding]::UTF8.GetString($b) | ConvertFrom-Json } catch { return $null }
}
# candidatos de um boletim: sqcand, situacao
function Cands($obj) {
    $out = @()
    foreach ($cg in @(Prop $obj "carg")) { foreach ($agr in @(Prop $cg "agr")) { foreach ($pa in @(Prop $agr "par")) { foreach ($c in @(Prop $pa "cand")) {
        if ($null -eq $c) { continue }
        $st = "$(Prop $c 'st')"; $e = "$(Prop $c 'e')"
        $eleito = $(if ($st) { ($st -match 'eleit') -and -not ($st -match 'n\S{1,2}o\s+eleit') -and -not ($st -match 'turno') } else { $e -eq "s" })
        $out += [pscustomobject]@{ sq = "$(Prop $c 'sqcand')"; eleito = $eleito; turno2 = ($st -match 'turno') }
    } } } }
    return $out
}

$fotos = New-Object System.Collections.ArrayList   # @(ele, uf, sq)
Anotar "Presidente (1o turno): Brasil e 27 estados..." "Cyan"
foreach ($abr in @("br") + $UFs) {
    $o = Guardar (Url $Ciclo $Pres1T $abr 1)
    if ($abr -eq "br" -and $o) { foreach ($c in (Cands $o)) { [void] $fotos.Add(@($Pres1T, "br", $c.sq)) } }
}
Anotar "Governador e Senador (1o turno): 27 estados..." "Cyan"
foreach ($u in $UFs) {
    $g = Guardar (Url $Ciclo $Est1T $u 3); $s = Guardar (Url $Ciclo $Est1T $u 5)
    if ($g) { foreach ($c in (Cands $g)) { if ($c.eleito -or $c.turno2) { [void] $fotos.Add(@($Est1T, $u, $c.sq)) } } }
    if ($s) { foreach ($c in (Cands $s)) { if ($c.eleito) { [void] $fotos.Add(@($Est1T, $u, $c.sq)) } } }
}
Anotar "Deputados federais e estaduais/distritais: 27 estados (arquivos grandes, pode demorar)..." "Cyan"
foreach ($u in $UFs) {
    $d = Guardar (Url $Ciclo $Camara $u 6)
    if ($d) { foreach ($c in (Cands $d)) { if ($c.eleito) { [void] $fotos.Add(@($Camara, $u, $c.sq)) } } }
    [void] (Guardar (Url $Ciclo $Camara $u $(if ($u -eq "df") { 8 } else { 7 })))
}
Anotar "2022 (comparacoes) e lista de eleicoes..." "Cyan"
[void] (Guardar (Url "ele2022" $E2022 "br" 1 "r" "dados-simplificados"))
[void] (Guardar (Url "ele2022" $E2022 "br" 1))
foreach ($abr in @("br") + $UFs) { [void] (Guardar (Url "ele2022" $E2022T2 $abr 1)) }
[void] (Guardar "$Base/comum/config/ele-c.json")
$nDados = $script:Ok

$nFotos = 0
if (-not $SemFotos) {
    Anotar ("Fotos: {0} candidatos (presidente, governadores e senadores eleitos ou no 2o turno, deputados federais eleitos)..." -f $fotos.Count) "Cyan"
    $indice = [ordered]@{}
    if (Test-Path (Join-Path $PastaFotos "indice.js")) {   # mantem as que ja estavam guardadas
        try { $t = Get-Content (Join-Path $PastaFotos "indice.js") -Raw -Encoding UTF8; $j = $t.Substring($t.IndexOf("{"), $t.LastIndexOf("}") - $t.IndexOf("{") + 1) | ConvertFrom-Json
              foreach ($p in $j.PSObject.Properties) { if (Test-Path (Join-Path (Join-Path $Raiz "web") ($p.Value -replace '/', '\'))) { $indice[$p.Name] = "$($p.Value)" } } } catch { }
    }
    foreach ($f in $fotos) {
        if (-not $f[2]) { continue }
        $chave = "$($f[1])/$($f[2])"; $rel = "fotos-tse/$($f[1])/$($f[2]).jpeg"
        if ($indice.Contains($chave)) { $nFotos++; continue }
        $b = Baixar "$Base/$Ciclo/$($f[0])/fotos/$($f[1])/$($f[2]).jpeg" (Join-Path $PastaFotos "$($f[1])\$($f[2]).jpeg")
        if ($null -ne $b) { $indice[$chave] = $rel; $nFotos++ }
    }
    if (-not (Test-Path $PastaFotos)) { New-Item -ItemType Directory -Path $PastaFotos -Force | Out-Null }
    [IO.File]::WriteAllText((Join-Path $PastaFotos "indice.js"), "window.GCTSE_FOTOS_LOCAIS = " + ([pscustomobject] $indice | ConvertTo-Json -Compress) + ";", (New-Object Text.UTF8Encoding($false)))
}

$falhas = @($script:Falhou)
Anotar ""
Anotar ("GUARDADO: {0} boletins em tse-local" -f $nDados) "Green"
if (-not $SemFotos) { Anotar ("FOTOS: {0} em web\fotos-tse" -f $nFotos) "Green" }
if ($falhas.Count) {
    Anotar ("NAO VIERAM {0} arquivos (a copia antiga deles, se havia, foi mantida):" -f $falhas.Count) "Yellow"
    foreach ($x in ($falhas | Select-Object -First 40)) { Anotar "   $x" "Yellow" }
    Anotar "   (2022, assembleia ou foto que o TSE nao publica nao atrapalha; Presidente/Governador/Senador/Camara faltando: rode de novo mais tarde)" "Gray"
}
$info = [ordered]@{ guardado_em = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); base = $Base; ciclo = $Ciclo; presidente_1turno = $Pres1T; estaduais_1turno = $Est1T; camara = $Camara; boletins = $nDados; fotos = $nFotos; falhas = $falhas.Count }
if (-not (Test-Path $Local)) { New-Item -ItemType Directory -Path $Local -Force | Out-Null }
[IO.File]::WriteAllText((Join-Path $Local "guardado.json"), ($info | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
try { [IO.File]::WriteAllLines((Join-Path $Raiz "GUARDAR-DADOS-TSE.txt"), $script:Diag, (New-Object Text.UTF8Encoding($true))) } catch { }
Anotar "Pronto. Os coletores usam esta copia sozinhos se o TSE falhar. Dica: rode de novo no sabado 24/10 e leve junto na COPIA-DE-SEGURANCA." "Green"
if (-not $SemPausa) { Read-Host "ENTER para fechar" | Out-Null }
