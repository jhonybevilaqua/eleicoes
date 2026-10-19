<#
    gctse GRAFICOS - COLETA DOS MUNICIPIOS (Presidente, 5.570 cidades)

    Le o boletim de Presidente de CADA municipio no TSE e grava
    web\municipios.js, para a tela "Mapa por municipio" (aba ANALISE POLITICA).

      - 1o turno (resultado final): lido UMA vez e guardado em
        municipios-1t-<ciclo>-<eleicao>.json (nao le de novo se reiniciar);
      - 2o turno: volta completa pelas cidades, de novo e de novo, devagar
        (municipios.req_por_segundo no config-graficos.json, padrao 8).

    Janela PROPRIA, separada do GRAFICOS.bat e do ESTADOS.bat: se esta coleta
    atrasar ou cair, Presidente, Governador e Senado seguem iguais.
    O TSE limita a 100 requisicoes por segundo por IP e avisa que muito 404
    bloqueia: cidade que responde 404 so e pedida de novo depois (recuo).
#>
param([switch] $UmaVolta)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$Versao = "3.28 - 19/10/2026"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
try { [Net.ServicePointManager]::DefaultConnectionLimit = 64 } catch { }
$ProgressPreference = "SilentlyContinue"

# Um clique na janela preta a poe em modo "Selecionar" e CONGELA o programa.
if ($env:OS -eq "Windows_NT") {
    try {
        Add-Type -Namespace GcTseMunicipios -Name JanelaConsole -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $entradaConsole = [GcTseMunicipios.JanelaConsole]::GetStdHandle(-10)
        [uint32] $modoConsole = 0
        if ([GcTseMunicipios.JanelaConsole]::GetConsoleMode($entradaConsole, [ref] $modoConsole)) {
            if (($modoConsole -band 0x40) -ne 0) { $modoConsole = $modoConsole - 0x40 }
            $modoConsole = $modoConsole -bor 0x80
            [void] [GcTseMunicipios.JanelaConsole]::SetConsoleMode($entradaConsole, $modoConsole)
        }
    } catch { }
}

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
$PastaWeb = Join-Path $Raiz "web"

function Escrever-Log {
    param([string] $Texto, [string] $Nivel = "INFO")
    $linha = "{0} {1,-5} {2}" -f (Get-Date -Format "HH:mm:ss"), $Nivel, $Texto
    switch ($Nivel) {
        "ERRO"  { Write-Host $linha -ForegroundColor Red }
        "AVISO" { Write-Host $linha -ForegroundColor Yellow }
        "OK"    { Write-Host $linha -ForegroundColor Green }
        default { Write-Host $linha }
    }
    try {
        if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" | Out-Null }
        Add-Content -Path (Join-Path "logs" ("municipios-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))) -Value $linha -Encoding UTF8
    } catch { }
}
function Tem-Propriedade($Objeto, [string] $Nome) {
    if ($null -eq $Objeto) { return $false }
    return @($Objeto.PSObject.Properties | Where-Object { $_.Name -eq $Nome }).Count -gt 0
}
function Campo($Objeto, [string[]] $Nomes, $Padrao = $null) {
    # (objeto do JSON vira "" quando convertido em texto: so texto vazio e descartado)
    foreach ($n in $Nomes) { if (Tem-Propriedade $Objeto $n) { $v = $Objeto.$n; if ($null -ne $v -and -not ($v -is [string] -and $v -eq "")) { return $v } } }
    return $Padrao
}
function Inteiro($x) { $n = [int64] 0; if ([int64]::TryParse("$x".Trim(), [ref] $n)) { return $n }; return [int64] 0 }
function Decimal($x) {
    $d = 0.0
    if ([double]::TryParse("$x".Trim().Replace(",", "."), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref] $d)) { return $d }
    return 0.0
}

# ------------------------------------------------------------------ config
try { $cfg = Get-Content (Join-Path $Raiz "config-graficos.json") -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Escrever-Log "config-graficos.json com erro: $($_.Exception.Message)" "ERRO"; exit 1 }
$Base = "$($cfg.tse.base_url)".TrimEnd('/')
$Ciclo = "$($cfg.tse.ciclo)"
$Eleicao = "$($cfg.tse.eleicao_presidente)"
$Eleicao1T = ""
if ((Tem-Propriedade $cfg.tse "eleicao_presidente_1turno") -and "$($cfg.tse.eleicao_presidente_1turno)" -ne $Eleicao) { $Eleicao1T = "$($cfg.tse.eleicao_presidente_1turno)" }
$PorSegundo = 8.0
$Ativo = $true
if (Tem-Propriedade $cfg "municipios") {
    if (Tem-Propriedade $cfg.municipios "req_por_segundo") { $PorSegundo = [math]::Max(1.0, [math]::Min(40.0, [double] $cfg.municipios.req_por_segundo)) }
    if (Tem-Propriedade $cfg.municipios "ativo") { $Ativo = [bool] $cfg.municipios.ativo }
}
if (-not $Ativo) { Escrever-Log "municipios.ativo = false no config-graficos.json: esta coleta fica parada." "AVISO"; while ($true) { Start-Sleep -Seconds 3600 } }
$GapMs = [int] (1000.0 / $PorSegundo)
$UFs = @("ac","al","ap","am","ba","ce","df","es","go","ma","mt","ms","mg","pa","pb","pr","pe","pi","rj","rn","rs","ro","rr","sc","sp","se","to")

# ------------------------------------------------------------------ TSE
$script:Etag = @{}       # url -> ETag
$script:Ausente = @{}    # url -> @{ vezes; ate }  (recuo depois de 404)
$script:UltimoOk = $null
$script:Pedidos = 0

function Pedir([string] $Url) {
    # -> objeto do JSON, "SEM-MUDANCA" (304) ou $null (falha/404)
    if ($script:Ausente.ContainsKey($Url) -and (Get-Date) -lt $script:Ausente[$Url].ate) { return $null }
    Start-Sleep -Milliseconds $GapMs
    $script:Pedidos++
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Method = "GET"; $req.Timeout = 15000; $req.ReadWriteTimeout = 15000
    $req.UserAgent = "gctse-municipios/1.0"; $req.Accept = "application/json,*/*"
    $req.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    if ($script:Etag.ContainsKey($Url)) { $req.Headers["If-None-Match"] = $script:Etag[$Url] }
    $resp = $null
    try {
        $resp = $req.GetResponse()
        $et = $resp.Headers["ETag"]; if ($et) { $script:Etag[$Url] = "$et" }
        $rd = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $txt = $rd.ReadToEnd(); $rd.Dispose()
        if ($script:Ausente.ContainsKey($Url)) { $script:Ausente.Remove($Url) }
        $script:UltimoOk = Get-Date
        try { return ($txt | ConvertFrom-Json) } catch { if ($script:Etag.ContainsKey($Url)) { $script:Etag.Remove($Url) }; return $null }
    } catch [Net.WebException] {
        $r = $_.Exception.Response
        $cod = 0; if ($r) { try { $cod = [int] $r.StatusCode } catch { } ; try { $r.Close() } catch { } }
        if ($cod -eq 304) { $script:UltimoOk = Get-Date; return "SEM-MUDANCA" }
        if ($cod -eq 404) {
            $v = 1; if ($script:Ausente.ContainsKey($Url)) { $v = $script:Ausente[$Url].vezes + 1 }
            $script:Ausente[$Url] = @{ vezes = $v; ate = (Get-Date).AddMinutes([math]::Min(30, [math]::Pow(2, $v))) }
        }
        return $null
    } catch { return $null }
    finally { if ($resp) { try { $resp.Close() } catch { } } }
}

# ------------------------------------------------- lista de municipios
function Ler-Lista([string] $Ele) {
    $e6 = "{0:000000}" -f ([int] $Ele)
    $o = Pedir "$Base/$Ciclo/$Ele/config/mun-e$e6-cm.json"
    if ($null -eq $o -or "$o" -eq "SEM-MUDANCA" -or -not (Tem-Propriedade $o "abr")) { return $null }
    $lista = New-Object System.Collections.ArrayList
    foreach ($a in @($o.abr)) {
        $uf = "$(Campo $a @('cd') '')".ToLower()
        if ($UFs -notcontains $uf -or -not (Tem-Propriedade $a "mu")) { continue }
        foreach ($m in @($a.mu)) {
            $cd = "$(Campo $m @('cd') '')"; if (-not $cd) { continue }
            if ($cd -match '^\d{1,4}$') { $cd = $cd.PadLeft(5, '0') }   # o TSE exige 5 digitos
            [void] $lista.Add([pscustomobject]@{ uf = $uf; cd = $cd; cdi = "$(Campo $m @('cdi') '')"; nome = "$(Campo $m @('nm') '')" })
        }
    }
    return ,$lista
}
function Url-Mun($m, [string] $Ele) {
    $e6 = "{0:000000}" -f ([int] $Ele)
    return "$Base/$Ciclo/$Ele/dados/$($m.uf)/$($m.uf)$($m.cd)-c0001-e$e6-u.json"
}
function Resumir($o) {
    # -> @{ urnas; votos = @{ numero = votos } } ou $null (simulado/teste/sem candidato)
    $f = "$(Campo $o @('f') '')".ToUpper()
    if ($f -eq "S" -or $f -eq "T") { return $null }
    $urnas = 0.0
    if (Tem-Propriedade $o "s") { $urnas = Decimal (Campo $o.s @('pst') 0) }
    $v = @{}
    foreach ($cg in @(Campo $o @('carg') @())) {
        foreach ($agr in @(Campo $cg @('agr') @())) {
            foreach ($pa in @(Campo $agr @('par') @())) {
                foreach ($c in @(Campo $pa @('cand') @())) {
                    if ("$(Campo $c @('dvt') '')" -match '^\s*[Aa]nula') { continue }   # voto anulado nao conta
                    $n = "$(Campo $c @('n') '')"; if ($n) { $v[$n] = Inteiro (Campo $c @('vap') 0) }
                }
            }
        }
    }
    if ($v.Count -eq 0) { return $null }
    return @{ urnas = $urnas; votos = $v }
}

# ------------------------------------------------------------- gravar
$script:R2 = @{}     # "uf-cd" -> @{ urnas; votos }
$script:R1 = @{}     # "uf-cd" -> @{ urnas; votos }   (1o turno, final)
$script:Lista = $null
$script:Volta = 0
$script:Lidos = 0
$Arq1T = Join-Path $Raiz ("municipios-1t-{0}-{1}.json" -f $Ciclo, $Eleicao1T)

function Gravar {
    $ufs = [ordered]@{}
    $numeros = @{}
    foreach ($m in $script:Lista) {
        $k = "$($m.uf)-$($m.cd)"
        $r2 = $null; if ($script:R2.ContainsKey($k)) { $r2 = $script:R2[$k] }
        $r1 = $null; if ($script:R1.ContainsKey($k)) { $r1 = $script:R1[$k] }
        if ($null -eq $r2 -and $null -eq $r1) { continue }
        if (-not $ufs.Contains($m.uf)) { $ufs[$m.uf] = [ordered]@{} }
        $v2 = [ordered]@{}; $u2 = $null
        if ($null -ne $r2) { $u2 = $r2.urnas; foreach ($n in $r2.votos.Keys) { $v2[$n] = $r2.votos[$n]; $numeros[$n] = $true } }
        $l1 = ""; $p1 = $null
        if ($null -ne $r1) {
            $tot = [double] 0; foreach ($n in $r1.votos.Keys) { $tot += $r1.votos[$n] }
            $top = @($r1.votos.GetEnumerator() | Sort-Object Value -Descending) | Select-Object -First 1
            if ($null -ne $top -and $tot -gt 0) { $l1 = "$($top.Key)"; $p1 = [math]::Round(100.0 * $top.Value / $tot, 2) }
        }
        $ufs[$m.uf][$m.cd] = @($m.cdi, $m.nome, $u2, [pscustomobject] $v2, $l1, $p1)
    }
    $obj = [ordered]@{
        versao = $Versao; gravado_em = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        eleicao = $Eleicao; eleicao_1t = $Eleicao1T
        total = $(if ($script:Lista) { $script:Lista.Count } else { 0 }); lidos_2t = $script:R2.Count; lidos_1t = $script:R1.Count
        volta = $script:Volta; ultimo_tse = $(if ($script:UltimoOk) { $script:UltimoOk.ToString("HH:mm:ss") } else { "" })
        campos = "cdi (IBGE), nome, % urnas 2o turno, votos por numero no 2o turno, lider no 1o turno, % do lider no 1o turno"
        ufs = $ufs
    }
    $json = $obj | ConvertTo-Json -Depth 6 -Compress
    $dest = Join-Path $PastaWeb "municipios.js"
    $tmp = "$dest.tmp"
    [IO.File]::WriteAllText($tmp, "window.GCTSE_MUN = $json;", (New-Object System.Text.UTF8Encoding($false)))
    try { Move-Item -LiteralPath $tmp -Destination $dest -Force } catch { try { Copy-Item -LiteralPath $tmp -Destination $dest -Force; Remove-Item $tmp -Force } catch { } }
}

# ------------------------------------------------------------- execucao
Escrever-Log "gctse MUNICIPIOS versao $Versao | 2o turno $Eleicao$(if ($Eleicao1T) { " | 1o turno $Eleicao1T" }) | $PorSegundo req/s" "OK"
while ($null -eq $script:Lista) {
    foreach ($ele in @($Eleicao, $Eleicao1T) | Where-Object { $_ }) {
        $l = Ler-Lista $ele
        if ($null -ne $l -and $l.Count -gt 1000) { $script:Lista = $l; Escrever-Log ("lista de municipios do TSE (eleicao {0}): {1} cidades" -f $ele, $l.Count) "OK"; break }
    }
    if ($null -eq $script:Lista) { Escrever-Log "lista de municipios do TSE ainda nao disponivel - tento de novo em 2 min" "AVISO"; Start-Sleep -Seconds 120 }
}
$semIbge = @($script:Lista | Where-Object { -not $_.cdi }).Count
if ($semIbge -gt 0) { Escrever-Log ("{0} cidades sem codigo IBGE (cdi) na lista do TSE: o mapa liga essas pelo NOME" -f $semIbge) "AVISO" }

# 1o turno: do arquivo guardado, ou do TSE (uma vez so)
if ($Eleicao1T) {
    if (Test-Path $Arq1T) {
        try {
            $g = Get-Content $Arq1T -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $g.PSObject.Properties) { $vv = @{}; foreach ($q in $p.Value.votos.PSObject.Properties) { $vv[$q.Name] = [int64] $q.Value }; $script:R1[$p.Name] = @{ urnas = [double] $p.Value.urnas; votos = $vv } }
            Escrever-Log ("1o turno por cidade: {0} cidades do arquivo guardado" -f $script:R1.Count) "OK"
        } catch { Escrever-Log "nao li $Arq1T - leio o 1o turno do TSE de novo" "AVISO" }
    }
    if ($script:R1.Count -lt [math]::Floor($script:Lista.Count * 0.98)) {
        Escrever-Log "lendo o 1o turno de cada cidade (uma vez so, alguns minutos)..."
        $i = 0
        foreach ($m in $script:Lista) {
            $i++; $k = "$($m.uf)-$($m.cd)"
            if ($script:R1.ContainsKey($k)) { continue }
            $o = Pedir (Url-Mun $m $Eleicao1T)
            if ($null -ne $o -and "$o" -ne "SEM-MUDANCA") { $r = Resumir $o; if ($r) { $script:R1[$k] = $r } }
            if ($i % 500 -eq 0) { Escrever-Log ("  1o turno: {0} de {1} cidades" -f $i, $script:Lista.Count); Gravar }
        }
        try {
            $sv = [ordered]@{}; foreach ($k in $script:R1.Keys) { $sv[$k] = [ordered]@{ urnas = $script:R1[$k].urnas; votos = [pscustomobject] $script:R1[$k].votos } }
            [IO.File]::WriteAllText($Arq1T, ($sv | ConvertTo-Json -Depth 4 -Compress), (New-Object System.Text.UTF8Encoding($false)))
        } catch { }
        Escrever-Log ("1o turno por cidade: {0} de {1} cidades lidas e guardadas" -f $script:R1.Count, $script:Lista.Count) "OK"
    }
    Gravar
}

# 2o turno: voltas completas, sem parar
do {
    $script:Volta++
    $ini = Get-Date; $novos = 0; $i = 0
    foreach ($m in $script:Lista) {
        $i++
        $o = Pedir (Url-Mun $m $Eleicao)
        if ($null -ne $o -and "$o" -ne "SEM-MUDANCA") { $r = Resumir $o; if ($r) { $script:R2["$($m.uf)-$($m.cd)"] = $r; $novos++ } }
        if ($i % 400 -eq 0) { Gravar }
    }
    Gravar
    $fim = 0; foreach ($k in $script:R2.Keys) { if ($script:R2[$k].urnas -ge 100) { $fim++ } }
    Escrever-Log ("volta {0}: {1} cidades lidas ({2} com numero novo) | {3} com 100% das urnas | {4:N0} s | TSE: {5}" -f $script:Volta, $script:R2.Count, $novos, $fim, ((Get-Date) - $ini).TotalSeconds, $(if ($script:UltimoOk) { "ultima resposta " + $script:UltimoOk.ToString("HH:mm:ss") } else { "SEM RESPOSTA" })) $(if ($script:UltimoOk) { "INFO" } else { "AVISO" })
    if ($UmaVolta) { break }
    if ($fim -ge $script:Lista.Count) { Escrever-Log "todas as cidades com 100% das urnas: volta so a cada 10 min" "OK"; Start-Sleep -Seconds 600 }
} while ($true)
