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
param([switch] $SemFotos, [switch] $SemPausa, [switch] $Historico)
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
function Copia-Json([string] $U) {   # le da copia ja guardada
    $arq = Join-Path $Local (($U.Substring($Base.Length).TrimStart('/')) -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $arq)) { return $null }
    try { return [IO.File]::ReadAllText($arq, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return $null }
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

# municipios do TSE: capitais e cidades do exterior (ZZ)
function Municipios($obj) {
    $out = New-Object System.Collections.ArrayList
    function Vis($o, [string] $uf, $saida) {
        if ($null -eq $o) { return }
        if ($o -is [array]) { foreach ($x in $o) { Vis $x $uf $saida }; return }
        if ($o -isnot [System.Management.Automation.PSCustomObject]) { return }
        $n = @($o.PSObject.Properties | ForEach-Object { $_.Name })
        if ($n -contains "cd" -and $n -contains "mu") { Vis $o.mu ("$($o.cd)".ToLower()) $saida; return }
        if ($uf -and $n -contains "cd" -and $n -contains "nm") { [void] $saida.Add([pscustomobject]@{ uf = $uf; cd = "$($o.cd)"; nm = "$($o.nm)"; c = "$(Prop $o 'c')" }); return }
        foreach ($p in $o.PSObject.Properties) { if ($p.Value -is [array] -or $p.Value -is [System.Management.Automation.PSCustomObject]) { Vis $p.Value $uf $saida } }
    }
    Vis $obj "" $out
    return $out
}
$NomesCap = @{ ac = "RIO BRANCO"; al = "MACEIO"; ap = "MACAPA"; am = "MANAUS"; ba = "SALVADOR"; ce = "FORTALEZA"; df = "BRASILIA"; es = "VITORIA"; go = "GOIANIA"
    ma = "SAO LUIS"; mt = "CUIABA"; ms = "CAMPO GRANDE"; mg = "BELO HORIZONTE"; pa = "BELEM"; pb = "JOAO PESSOA"; pr = "CURITIBA"; pe = "RECIFE"; pi = "TERESINA"
    rj = "RIO DE JANEIRO"; rn = "NATAL"; rs = "PORTO ALEGRE"; ro = "PORTO VELHO"; rr = "BOA VISTA"; sc = "FLORIANOPOLIS"; sp = "SAO PAULO"; se = "ARACAJU"; to = "PALMAS" }
function SemAcento([string] $t) {
    $n = $t.Normalize([Text.NormalizationForm]::FormD); $sb = New-Object Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void] $sb.Append($ch) } }
    return $sb.ToString().ToUpper().Trim()
}
function Guardar-Municipios([string] $ele, [string] $rotulo) {
    $e6 = "{0:000000}" -f [int] $ele
    $cfgMun = Guardar "$Base/$Ciclo/$ele/config/mun-e$e6-cm.json"
    if ($null -eq $cfgMun) { Anotar "   $rotulo : lista de municipios do TSE nao veio - capitais e exterior por cidade ficam sem copia" "Yellow"; return }
    $ms = Municipios $cfgMun; $nCap = 0; $nExt = 0
    foreach ($u in $UFs) {
        $c = @($ms | Where-Object { $_.uf -eq $u -and $_.c -eq "S" }) | Select-Object -First 1
        if ($null -eq $c) { $c = @($ms | Where-Object { $_.uf -eq $u -and (SemAcento $_.nm) -eq $NomesCap[$u] }) | Select-Object -First 1 }
        if ($c -and (Guardar "$Base/$Ciclo/$ele/dados/$u/$u$($c.cd)-c0001-e$e6-u.json")) { $nCap++ }
    }
    foreach ($m in @($ms | Where-Object { $_.uf -eq "zz" })) { if (Guardar "$Base/$Ciclo/$ele/dados/zz/zz$($m.cd)-c0001-e$e6-u.json") { $nExt++ } }
    Anotar ("   {0}: capitais {1}/27 | cidades do exterior {2}" -f $rotulo, $nCap, $nExt)
}

$fotos = New-Object System.Collections.ArrayList   # @(ele, uf, sq)
Anotar "Presidente (1o turno): Brasil e 27 estados..." "Cyan"
foreach ($abr in @("br") + $UFs + @("zz")) {
    $o = Guardar (Url $Ciclo $Pres1T $abr 1)
    if ($abr -eq "br" -and $o) { foreach ($c in (Cands $o)) { [void] $fotos.Add(@($Pres1T, "br", $c.sq)) } }
}
Anotar "Presidente (1o turno): capitais e cidades do exterior..." "Cyan"
Guardar-Municipios $Pres1T "1o turno"
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
$n22 = 0; foreach ($abr in @("br") + $UFs + @("zz")) { if (Guardar (Url "ele2022" $E2022T2 $abr 1)) { $n22++ } }
Anotar ("   2022 Presidente 2o turno (eleicao {0}): {1} de 29 (Brasil, 27 estados, exterior)" -f $E2022T2, $n22)
$G22 = "546"; $G22T2 = "547"
if ($c22) { if ("$(Prop $c22 'eleicao_estaduais')") { $G22 = "$(Prop $c22 'eleicao_estaduais')" }; if ("$(Prop $c22 'eleicao_estaduais_2turno')") { $G22T2 = "$(Prop $c22 'eleicao_estaduais_2turno')" } }
$ng = 0; $ng2 = 0
foreach ($u in $UFs) {
    $bol22 = Guardar (Url "ele2022" $G22 $u 3)
    if ($bol22) { $ng++; if (@(Cands $bol22 | Where-Object { $_.turno2 }).Count) { if (Guardar (Url "ele2022" $G22T2 $u 3)) { $ng2++ } } }
}
Anotar ("   2022 Governador (eleicoes {0}/{1}): 1o turno {2} de 27 | 2o turno {3} estados" -f $G22, $G22T2, $ng, $ng2) $(if ($ng -lt 27) { "Yellow" } else { "Gray" })
if ($ng -eq 0) { Anotar "   (governadores de 2022 nao vieram: confira o codigo com a engenharia e ponha em comparar_2022.eleicao_estaduais no config)" "Yellow" }
[void] (Guardar "$Base/comum/config/ele-c.json")
# ARQUIVO HISTORICO (ARQUIVO-HISTORICO-2026.bat, depois do 2o turno): o 2o
# turno final tambem, e um .zip com tudo para 2028/2030.
$Pres2T = Cod "eleicao_presidente" ""; $Est2T = Cod "eleicao_estaduais" ""
if ($Historico) {
    if ($Pres2T -and $Pres2T -ne $Pres1T) {
        Anotar "ARQUIVO: Presidente 2o turno ($Pres2T) - Brasil, estados, exterior, capitais e cidades do exterior..." "Cyan"
        foreach ($abr in @("br") + $UFs + @("zz")) { $o2 = Guardar (Url $Ciclo $Pres2T $abr 1); if ($abr -eq "br" -and $o2) { foreach ($c in (Cands $o2)) { [void] $fotos.Add(@($Pres2T, "br", $c.sq)) } } }
        Guardar-Municipios $Pres2T "2o turno"
    } else { Anotar "ARQUIVO: o config ainda esta no 1o turno - so o 1o turno vai para o arquivo." "Yellow" }
    if ($Est2T -and $Est2T -ne $Est1T) {
        Anotar "ARQUIVO: Governador 2o turno ($Est2T)..." "Cyan"
        foreach ($u in $UFs) { $g1 = Copia-Json (Url $Ciclo $Est1T $u 3); if ($g1 -and @(Cands $g1 | Where-Object { $_.turno2 }).Count) { $g2 = Guardar (Url $Ciclo $Est2T $u 3); if ($g2) { foreach ($c in (Cands $g2)) { if ($c.eleito) { [void] $fotos.Add(@($Est2T, $u, $c.sq)) } } } } }
    }
}
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
if ($Historico) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $pastaArq = Join-Path $Raiz "arquivo-historico"; if (-not (Test-Path $pastaArq)) { New-Item -ItemType Directory -Path $pastaArq | Out-Null }
        $tmpArq = Join-Path $env:TEMP ("gctse-arquivo-" + (Get-Date -Format "yyyyMMddHHmmss"))
        New-Item -ItemType Directory -Path $tmpArq | Out-Null
        foreach ($item in @("tse-local", "web\fotos-tse", "logs")) { $o3 = Join-Path $Raiz $item; if (Test-Path $o3) { Copy-Item -LiteralPath $o3 -Destination (Join-Path $tmpArq ($item -replace '\\', '_')) -Recurse -Force } }
        foreach ($arqX in @(Get-ChildItem -Path $Raiz -Filter "evolucao-*.json" -File) + @(Get-Item (Join-Path $Raiz "config-graficos.json")) + @(Get-ChildItem -Path (Join-Path $Raiz "web") -Include "dados.js", "estados.js", "candidatos-genero.js", "perfil-eleitor.js" -File -Recurse -Depth 0 -ErrorAction SilentlyContinue)) { Copy-Item -LiteralPath $arqX.FullName -Destination $tmpArq -Force }
        $zipArq = Join-Path $pastaArq ("GCTSE-ARQUIVO-ELEICOES-{0}.zip" -f (Get-Date -Format "yyyy-MM-dd_HH'h'mm"))
        [IO.Compression.ZipFile]::CreateFromDirectory($tmpArq, $zipArq)
        Remove-Item -LiteralPath $tmpArq -Recurse -Force
        Anotar ("ARQUIVO HISTORICO: {0}  ({1:N1} MB) - guarde fora desta maquina (rede, nuvem, HD externo)." -f $zipArq, ((Get-Item $zipArq).Length / 1MB)) "Green"
    } catch { Anotar "ARQUIVO HISTORICO: falhou ao montar o .zip: $($_.Exception.Message)" "Red" }
}
Anotar "Pronto. Os coletores usam esta copia sozinhos se o TSE falhar. Dica: rode de novo no sabado 24/10 e leve junto na COPIA-DE-SEGURANCA." "Green"
if (-not $SemPausa) { Read-Host "ENTER para fechar" | Out-Null }
