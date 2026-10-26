<#
    gctse GRAFICOS - REPRISE DA NOITE (REPRISE-DA-NOITE.bat)

    Treino da equipe com a noite DE VERDADE: le o "BR - Historico totalizacao
    Presidente 2o Turno" do TSE (Portal de Dados Abertos; o mesmo arquivo do
    IMPORTAR-EVOLUCAO) e reproduz a apuracao do Presidente, acelerada, como
    se o site do TSE estivesse publicando: virada, eleito, 100% das urnas.

    - Roda numa COPIA SEPARADA (pasta "reprise", criada de novo a cada vez):
      nao mexe nos dados desta pasta, nem na copia extra em Documentos.
    - Um servidor local (http://127.0.0.1:8790) responde no formato do TSE;
      a copia do GRAFICOS le dele. So o Brasil (o historico do TSE e so do
      Brasil): telas de estado ficam "aguardando".
    - Telas com a marca REPRISE - NAO VAI AO AR. Gerenciador da reprise:
      http://localhost:8097/gerenciador.html (o de verdade continua na 8098).
    - Com o historico do 1o turno junto, o 1o turno tambem aparece (final).

    Uso: REPRISE-DA-NOITE.bat                (velocidade 10x: 5 h em 30 min)
         REPRISE-DA-NOITE.bat -Velocidade 30 (mais rapido)
         ou arraste o .zip do historico sobre o .bat
    Para parar: feche esta janela (ou Ctrl+C).
#>
[CmdletBinding(PositionalBinding = $false)]
param([int] $Velocidade = 10, [int] $PortaTse = 8790, [int] $PortaGerenciador = 8097, [switch] $SemAbrir, [int] $Segundos = 0,
      [Parameter(ValueFromRemainingArguments = $true)] [string[]] $Caminhos = @())
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch { }
try { Add-Type -AssemblyName System.IO.Compression } catch { }
$Latin1 = [Text.Encoding]::GetEncoding(28591)
$Velocidade = [math]::Max(1, [math]::Min(600, $Velocidade))

function Diz([string] $Texto, [string] $Cor = "Gray") { Write-Host $Texto -ForegroundColor $Cor }
function Parar([string] $Msg) { Diz $Msg "Red"; if (-not $SemAbrir) { Read-Host "Enter para fechar" | Out-Null }; exit 1 }
function Normalizar([string] $Texto) {
    $d = "$Texto".Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $d.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void] $sb.Append($ch) } }
    return (($sb.ToString().ToUpperInvariant()) -replace '[^A-Z0-9 ]', ' ' -replace '\s+', ' ').Trim()
}
function Numero-Br([string] $Texto) {
    $t = "$Texto".Trim().TrimEnd('%').Replace(".", "").Replace(",", ".")
    $v = 0.0
    if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref] $v)) { return $v }
    return $null
}
function Pct([double] $v) { return ([math]::Round($v, 2)).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture).Replace(".", ",") }

if (-not (Test-Path "config-graficos.json")) { Parar "config-graficos.json nao encontrado: rode na pasta dos GRAFICOS." }
$cfg = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Ciclo = "$($cfg.tse.ciclo)"; $Ele2 = "$($cfg.tse.eleicao_presidente)"; $Ele1 = "$($cfg.tse.eleicao_presidente_1turno)"

# ------------------------------------------------------ achar os historicos
function Cabecalho($Arq) {
    try {
        if ($Arq.Extension -match '(?i)\.zip$') {
            $z = [IO.Compression.ZipFile]::OpenRead($Arq.FullName)
            try { $e = @($z.Entries | Where-Object { $_.Name -match '(?i)\.(csv|txt)$' }) | Select-Object -First 1; if (-not $e) { return "" }
                  $r0 = New-Object IO.StreamReader($e.Open(), $Latin1); try { return $r0.ReadLine() } finally { $r0.Dispose() } } finally { $z.Dispose() }
        }
        $r0 = New-Object IO.StreamReader($Arq.FullName, $Latin1); try { return $r0.ReadLine() } finally { $r0.Dispose() }
    } catch { return "" }
}
function Turno-Historico($Arq) {
    $c0 = Cabecalho $Arq
    if ("$c0" -notmatch '(?i)DT_TOTALIZACAO') { return 0 }
    $nC = @([regex]::Matches("$c0", '(?i)([A-Z0-9_]+)_PE_VOTOS_TOT_ACUMULADO') | Where-Object { $_.Groups[1].Value.Trim() -notmatch '(?i)^(BRANCO|NULO)$' }).Count
    if ($nC -lt 2) { return 0 }
    return $(if ($nC -eq 2) { 2 } else { 1 })
}
function Achar([int] $Turno) {
    $lug = @($Caminhos | Where-Object { $_ } | ForEach-Object { "$_".Trim('"') }) + @((Join-Path $Raiz "importar"), $Raiz)
    if ($env:USERPROFILE) { $lug += @((Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop")) }
    $ach = @()
    foreach ($l in $lug) {
        if (Test-Path -LiteralPath $l -PathType Leaf) { $it = Get-Item -LiteralPath $l; if ((Turno-Historico $it) -eq $Turno) { $ach += @($it) }; continue }
        if (Test-Path -LiteralPath $l -PathType Container) {
            $ach += @(Get-ChildItem -LiteralPath $l -File -Recurse -Depth 1 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^Historico_Totalizacao_Presidente_BR_[12]T_.*\.(zip|csv|txt)$' -and (Turno-Historico $_) -eq $Turno })
        }
    }
    return @($ach | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}
function Ler-Linhas($Arq) {
    $zip = $null
    if ($Arq.Extension -match '(?i)\.zip$') {
        $zip = [IO.Compression.ZipFile]::OpenRead($Arq.FullName)
        $ent = @($zip.Entries | Where-Object { $_.Name -match '(?i)\.(csv|txt)$' }) | Select-Object -First 1
        $rd = New-Object IO.StreamReader($ent.Open(), $Latin1)
    } else { $rd = New-Object IO.StreamReader($Arq.FullName, $Latin1) }
    $lin = New-Object System.Collections.Generic.List[object]
    try {
        $cab = @($rd.ReadLine().Split(';') | ForEach-Object { $_.Trim().ToUpper() })
        $ix = @{}; for ($i = 0; $i -lt $cab.Count; $i++) { $ix[$cab[$i]] = $i }
        function Col($Ix, [string] $N) { if ($Ix.ContainsKey($N)) { return $Ix[$N] }; return -1 }
        $iT = Col $ix "DT_TOTALIZACAO"; $iUe = Col $ix "SG_UE_UF"
        $nomes = @($cab | Where-Object { $_ -match '_QT_VOTOS_TOT_ACUMULADO$' -and $_ -notmatch '^(BRANCO|NULO)_' } | ForEach-Object { $_ -replace '_QT_VOTOS_TOT_ACUMULADO$', '' })
        $iC = @{}; foreach ($n in $nomes) { $iC[$n] = Col $ix ($n + "_QT_VOTOS_TOT_ACUMULADO") }
        $cols = @{ ts = (Col $ix "QT_SECOES_TOTAL"); sa = (Col $ix "QT_SECOES_TOT_ACUMULADO"); pst = (Col $ix "PE_SECOES_TOT_ACUMULADO"); at = (Col $ix "QT_APTOS_TOTAL"); aa = (Col $ix "QT_APTOS_TOT_ACUMULADO")
                   vt = (Col $ix "QT_VOTOS_TOTAL_ACUMULADO"); vc = (Col $ix "QT_VOTOS_CONCORRENTES_ACUMULADO"); vb = (Col $ix "BRANCO_QT_VOTOS_TOT_ACUMULADO"); vn = (Col $ix "NULO_QT_VOTOS_TOT_ACUMULADO") }
        while ($null -ne ($l = $rd.ReadLine())) {
            $p = $l.Split(';'); if ($p.Count -lt $cab.Count) { continue }
            if ($iUe -ge 0 -and $p[$iUe].Trim() -ne "BR") { continue }
            $q = $null; try { $q = [datetime]::ParseExact($p[$iT].Trim(), "dd/MM/yyyy HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture) } catch { continue }
            $o = @{ t = $q }
            foreach ($k in $cols.Keys) { $o[$k] = $(if ($cols[$k] -ge 0) { Numero-Br $p[$cols[$k]] } else { $null }) }
            if ($null -ne $o.pst -and $o.pst -le 1.0001) { $o.pst = 100 * $o.pst }
            $cv = [ordered]@{}; foreach ($n in $nomes) { $cv[$n] = [int64] (Numero-Br $p[$iC[$n]]) }
            $o.c = $cv
            $lin.Add([pscustomobject] $o)
        }
    } finally { $rd.Dispose(); if ($zip) { $zip.Dispose() } }
    return ,$lin
}

$h2 = @(Achar 2)
if (-not $h2.Count) { Parar "nao achei o 'BR - Historico totalizacao Presidente 2o Turno' (Historico_Totalizacao_Presidente_BR_2T_AAAA.zip) na pasta importar, Downloads ou Area de Trabalho. Baixe em dadosabertos.tse.jus.br ou arraste o .zip sobre o REPRISE-DA-NOITE.bat." }
Diz ("historico do 2o turno: {0}" -f $h2[0].FullName) "Cyan"
$L2 = Ler-Linhas $h2[0]
if ($L2.Count -lt 2) { Parar "historico do 2o turno sem linhas do Brasil." }
$L1 = $null; $h1 = @(Achar 1)
if ($h1.Count -and $Ele1) { Diz ("historico do 1o turno: {0} (o 1o turno aparece com o resultado final)" -f $h1[0].FullName) "Cyan"; $L1 = Ler-Linhas $h1[0] }
Diz ("{0} totalizacoes de {1:HH:mm} a {2:HH:mm} - velocidade {3}x: {4:N0} minutos de reprise" -f $L2.Count, $L2[0].t, $L2[$L2.Count - 1].t, $Velocidade, (($L2[$L2.Count - 1].t - $L2[0].t).TotalMinutes / $Velocidade))

# ------------------------- candidatos: numero, partido e foto do boletim de verdade
$meta = @{}
$arqD = Join-Path $Raiz "web\dados.js"
if (Test-Path $arqD) {
    try {
        $tx = [IO.File]::ReadAllText($arqD, [Text.Encoding]::UTF8); $dd = $tx.Substring($tx.IndexOf("{"), $tx.LastIndexOf("}") - $tx.IndexOf("{") + 1) | ConvertFrom-Json
        $fontes = @(); if ($dd.br -and $dd.br.candidatos) { $fontes += @($dd.br.candidatos) }
        if ($dd.turno1 -and $dd.turno1.br -and $dd.turno1.br.candidatos) { $fontes += @($dd.turno1.br.candidatos) }
        foreach ($c in $fontes) { if ($c -and $c.nome -and -not $meta.ContainsKey((Normalizar $c.nome))) { $meta[(Normalizar $c.nome)] = $c } }
    } catch { }
}
$numLivre = 90
function Meta-De([string] $NomeCol) {
    $n = Normalizar ($NomeCol -replace '_', ' ')
    if ($meta.ContainsKey($n)) { return $meta[$n] }
    $par = @($meta.Keys | Where-Object { $_.StartsWith($n) -or $n.StartsWith($_) })
    if ($par.Count -eq 1) { return $meta[$par[0]] }
    $pal = @($n.Split(' ') | Where-Object { $_.Length -ge 4 })
    $porP = @($meta.Keys | Where-Object { $ks = @($_.Split(' ')); @($pal | Where-Object { $ks -contains $_ }).Count -gt 0 })
    if ($porP.Count -eq 1) { return $meta[$porP[0]] }
    $script:numLivre++
    $novo = [pscustomobject]@{ numero = "$($script:numLivre)"; nome = ($NomeCol -replace '_', ' '); partido = ""; sqcand = "" }
    $meta[$n] = $novo
    return $novo
}

# ----------------------------------------------- boletim no formato do TSE
function Boletim($Row, [bool] $Segundo, [bool] $Final) {
    $conc = [double] $(if ($Row.vc) { $Row.vc } else { ($Row.c.Values | Measure-Object -Sum).Sum })
    $ordem = @($Row.c.Keys | Sort-Object { - $Row.c[$_] })
    $agr = @(); $pos = 0
    foreach ($nm in $ordem) {
        $pos++; $m = Meta-De $nm; $v = [int64] $Row.c[$nm]
        $st = ""
        if ($Final) { if ($Segundo) { $st = $(if ($pos -eq 1) { "Eleito" } else { "Não eleito" }) } else { $st = $(if ($pos -le 2) { "2º turno" } else { "Não eleito" }) } }
        $cand = [ordered]@{ n = "$($m.numero)"; sqcand = "$($m.sqcand)"; nm = "$($m.nome)"; nmu = "$($m.nome)"; vap = "$v"; pvap = (Pct $(if ($conc -gt 0) { 100.0 * $v / $conc } else { 0 })); st = $st; e = $(if ($st -eq "Eleito") { "s" } else { "n" }); dvt = "Válido" }
        $agr += [ordered]@{ nm = ""; par = @([ordered]@{ sg = "$($m.partido)"; nm = "$($m.partido)"; cand = @($cand) }) }
    }
    $at = [double] $Row.at; $aa = [double] $Row.aa; $vt = [double] $Row.vt; $vb = [double] $Row.vb; $vn = [double] $Row.vn
    $tot = $conc + $vb + $vn
    return [ordered]@{
        f = "O"; and = $(if ($Final) { "f" } else { "p" }); dg = $Row.t.ToString("dd/MM/yyyy"); hg = $Row.t.ToString("HH:mm:ss")
        s = [ordered]@{ ts = "$([int64] $Row.ts)"; st = "$([int64] $Row.sa)"; pst = (Pct $Row.pst) }
        e = [ordered]@{ te = "$([int64] $at)"; est = "$([int64] $aa)"; esnt = "$([int64] ($at - $aa))"; c = "$([int64] $vt)"; pc = (Pct $(if ($aa -gt 0) { 100 * $vt / $aa } else { 0 })); a = "$([int64] ($aa - $vt))"; pa = (Pct $(if ($aa -gt 0) { 100 * ($aa - $vt) / $aa } else { 0 })) }
        v = [ordered]@{ vv = "$([int64] $conc)"; vb = "$([int64] $vb)"; tvn = "$([int64] $vn)"; pvv = (Pct $(if ($tot -gt 0) { 100 * $conc / $tot } else { 0 })); pvb = (Pct $(if ($tot -gt 0) { 100 * $vb / $tot } else { 0 })); ptvn = (Pct $(if ($tot -gt 0) { 100 * $vn / $tot } else { 0 })) }
        carg = @([ordered]@{ cd = "1"; nm = "Presidente"; agr = $agr })
    }
}

# ------------------------------------------------- copia separada (reprise)
$Pasta = Join-Path $Raiz "reprise"
if (Test-Path -LiteralPath $Pasta) { Remove-Item -LiteralPath $Pasta -Recurse -Force }
New-Item -ItemType Directory -Path $Pasta | Out-Null
foreach ($a in @("graficos.ps1", "gerenciador.ps1")) { Copy-Item -LiteralPath (Join-Path $Raiz $a) -Destination $Pasta }
$webR = Join-Path $Pasta "web"
Copy-Item -LiteralPath (Join-Path $Raiz "web") -Destination $webR -Recurse
foreach ($a in @("dados.js", "estados.js", "municipios.js")) { $x = Join-Path $webR $a; if (Test-Path $x) { Remove-Item -LiteralPath $x -Force } }
$cfgR = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$cfgR.tse.base_url = "http://127.0.0.1:$PortaTse/oficial"
foreach ($par in @(@("porta_gerenciador", $PortaGerenciador), @("reabrir_coletas", $false), @("atualizar_dados_ao_abrir", $false), @("abrir_monitor", $false),
                   @("copia_extra", "nao"), @("reprise", $true), @("intervalo_segundos", 10))) { $cfgR | Add-Member -NotePropertyName $par[0] -NotePropertyValue $par[1] -Force }
if ($cfgR.PSObject.Properties["municipios"]) { $cfgR.municipios | Add-Member -NotePropertyName ativo -NotePropertyValue $false -Force }
[IO.File]::WriteAllText((Join-Path $Pasta "config-graficos.json"), ($cfgR | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
Diz ("copia da reprise: {0}" -f $Pasta)

# ------------------------------------------------------------- servidor
$lst = New-Object System.Net.HttpListener
$lst.Prefixes.Add("http://127.0.0.1:$PortaTse/")
try { $lst.Start() } catch { Parar "a porta $PortaTse esta em uso (outra reprise aberta?): $($_.Exception.Message)" }
$psExe = "powershell"
if ($env:WINDIR -and (Test-Path (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"))) { $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe" }
elseif (-not (Get-Command "powershell" -ErrorAction SilentlyContinue)) { $psExe = "pwsh" }
$procs = @()
try {
    $aG = @{ FilePath = $psExe; WorkingDirectory = $Pasta; ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + (Join-Path $Pasta "graficos.ps1") + '"')); PassThru = $true }
    $aM = @{ FilePath = $psExe; WorkingDirectory = $Pasta; ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + (Join-Path $Pasta "gerenciador.ps1") + '"')); PassThru = $true }
    if ($SemAbrir) { $aG.NoNewWindow = $true; $aG.RedirectStandardOutput = (Join-Path $Pasta "graficos-saida.txt"); $aM.NoNewWindow = $true; $aM.RedirectStandardOutput = (Join-Path $Pasta "gerenciador-saida.txt") }
    elseif ($env:OS -eq "Windows_NT") { $aG.WindowStyle = "Minimized"; $aM.WindowStyle = "Minimized" }
    $procs += @(Start-Process @aG)
    $procs += @(Start-Process @aM)
    if (-not $SemAbrir) { Start-Sleep -Seconds 3; try { Start-Process ("http://localhost:{0}/gerenciador.html" -f $PortaGerenciador) } catch { } }
    Diz ""
    Diz ("REPRISE RODANDO - gerenciador da reprise: http://localhost:{0}/gerenciador.html" -f $PortaGerenciador) "Green"
    Diz "Telas com a marca REPRISE - NAO VAI AO AR. Para parar: feche esta janela." "Yellow"

    $t0 = Get-Date; $h0 = $L2[0].t; $fim1 = $(if ($L1 -and $L1.Count) { $L1[$L1.Count - 1] } else { $null })
    $reBr = '^/oficial/[^/]+/(\d+)/dados/br/br-c0001-e\d+-u\.json$'
    $idx = -1; $ultMsg = [datetime]::MinValue
    $tarefa = $lst.GetContextAsync()
    while ($true) {
        $vt = $h0.AddSeconds(((Get-Date) - $t0).TotalSeconds * $Velocidade)
        while ($idx + 1 -lt $L2.Count -and $L2[$idx + 1].t -le $vt) { $idx++ }
        if (((Get-Date) - $ultMsg).TotalSeconds -ge 5) {
            $ultMsg = Get-Date
            $rw = $(if ($idx -ge 0) { $L2[$idx] } else { $L2[0] })
            Diz ("  reprise: {0:HH:mm:ss} (hora do TSE) - urnas {1}%{2}" -f $vt, (Pct $rw.pst), $(if ($idx -eq $L2.Count - 1) { " - FIM (resultado final)" } else { "" }))
        }
        if ($Segundos -gt 0 -and ((Get-Date) - $t0).TotalSeconds -ge $Segundos) { break }
        if (-not $tarefa.Wait(500)) { continue }
        $ctx = $tarefa.Result; $tarefa = $lst.GetContextAsync()
        try {
            $cam = $ctx.Request.Url.AbsolutePath; $m = [regex]::Match($cam, $reBr); $corpo = $null; $etag = ""
            if ($m.Success -and $m.Groups[1].Value -eq $Ele2 -and $idx -ge 0) { $etag = "`"r$idx`""; if ($ctx.Request.Headers["If-None-Match"] -ne $etag) { $corpo = Boletim $L2[$idx] $true ($idx -eq $L2.Count - 1) } }
            elseif ($m.Success -and $m.Groups[1].Value -eq $Ele1 -and $fim1) { $etag = "`"t1`""; if ($ctx.Request.Headers["If-None-Match"] -ne $etag) { $corpo = Boletim $fim1 $false $true } }
            $res = $ctx.Response
            if ($etag -and $null -eq $corpo) { $res.StatusCode = 304 }
            elseif ($null -ne $corpo) {
                $b = [Text.Encoding]::UTF8.GetBytes(($corpo | ConvertTo-Json -Depth 12 -Compress))
                $res.StatusCode = 200; $res.ContentType = "application/json; charset=utf-8"; $res.Headers["ETag"] = $etag; $res.ContentLength64 = $b.Length; $res.OutputStream.Write($b, 0, $b.Length)
            } else { $res.StatusCode = 404 }
            $res.Close()
        } catch { try { $ctx.Response.Abort() } catch { } }
    }
} finally {
    try { $lst.Stop() } catch { }
    foreach ($p in $procs) { try { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force } } catch { } }
    Diz "reprise encerrada." "Cyan"
}
