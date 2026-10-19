<#
    gctse GRAFICOS - IMPORTAR 2022 (TSE - Portal de Dados Abertos)

    O site de resultados do TSE nao tem mais os arquivos de 2022 (resposta
    NoSuchKey). Os numeros oficiais de 2022 continuam no Portal de Dados
    Abertos do TSE (dadosabertos.tse.jus.br > Resultados - 2022):
      votacao_candidato_munzona_2022.zip ... "Votacao nominal por municipio e
                                             zona": votos de cada candidato
                                             (Presidente e Governador, 1o e
                                             2o turno) - o melhor
      votacao_partido_munzona_2022.zip ..... "Votacao em partido por municipio
                                             e zona": serve no lugar do
                                             nominal (sem o nome do governador)
      detalhe_votacao_munzona_2022.zip ..... "Detalhe da apuracao por
                                             municipio e zona": aptos,
                                             comparecimento, abstencao,
                                             brancos e nulos de cada estado
      Historico_Totalizacao_Presidente_BR_1T_2022 / _2T_2022 (zip ou csv)
                                             "BR - Historico totalizacao
                                             Presidente": abstencao, brancos
                                             e nulos do Brasil (sem o detalhe)
    Este programa soma por estado e Brasil e grava dados-2022.json, que o
    ESTADOS.bat le no lugar dos arquivos que o TSE tirou do ar. As telas que
    comparam com 2022 nao mudam.

    Sem os arquivos, tenta baixar do TSE para a pasta "importar". Se nao der,
    baixe em dadosabertos.tse.jus.br (Resultados > 2022) e ponha na pasta
    importar. As colunas sao achadas pelo nome.
#>
[CmdletBinding(PositionalBinding = $false)]
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Caminhos = @())
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch { }
try { Add-Type -AssemblyName System.IO.Compression } catch { }
$ProgressPreference = "SilentlyContinue"

$script:Diag = New-Object System.Collections.Generic.List[string]
function Anotar([string] $Texto, [string] $Cor = "Gray") { Write-Host $Texto -ForegroundColor $Cor; $script:Diag.Add($Texto) }
function Sair([string] $Msg, [int] $Codigo) {
    if ($Codigo -ne 0) { Anotar $Msg "Red" } else { Anotar $Msg "Green" }
    try { [IO.File]::WriteAllLines((Join-Path $Raiz "IMPORTAR-2022.txt"), $script:Diag, (New-Object System.Text.UTF8Encoding($true))) } catch { }
    exit $Codigo
}
$Latin1 = [Text.Encoding]::GetEncoding(28591)   # os CSV do TSE vem em Latin-1
$TIPOS = [ordered]@{
    votacao = @{ padrao = '(?i)^votacao_candidato_munzona_2022.*\.(zip|csv|txt)$'; url = "https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_candidato_munzona/votacao_candidato_munzona_2022.zip" }
    detalhe = @{ padrao = '(?i)^detalhe_votacao_munzona_2022.*\.(zip|csv|txt)$'; url = "https://cdn.tse.jus.br/estatistica/sead/odsele/detalhe_votacao_munzona/detalhe_votacao_munzona_2022.zip" }
    partido = @{ padrao = '(?i)^votacao_partido_munzona_2022.*\.(zip|csv|txt)$'; url = "" }
    hist1   = @{ padrao = '(?i)^Historico_Totalizacao_Presidente_BR_1T_2022.*\.(zip|csv|txt)$'; url = "" }
    hist2   = @{ padrao = '(?i)^Historico_Totalizacao_Presidente_BR_2T_2022.*\.(zip|csv|txt)$'; url = "" }
}

# ------------------------------------------------------------- achar arquivos
$explicito = ($Caminhos -and @($Caminhos | Where-Object { $_ }).Count -gt 0)
$onde = @()
if ($explicito) { $onde = @($Caminhos | Where-Object { $_ } | ForEach-Object { "$_".Trim('"') }) }
else {
    $onde = @((Join-Path $Raiz "importar"), $Raiz)
    if ($env:USERPROFILE) { $onde += @((Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop")) }
}
function Procurar([string] $Padrao) {
    $achados = @()
    foreach ($o in ($onde | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $o -PathType Leaf) { $it = Get-Item -LiteralPath $o; if ($it.Name -match $Padrao) { $achados += @($it) }; continue }
        if (Test-Path -LiteralPath $o -PathType Container) {
            $achados += @(Get-ChildItem -LiteralPath $o -File -Recurse -Depth 1 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $Padrao })
        }
    }
    return @($achados | Sort-Object FullName -Unique | Select-Object -First 1)
}
$arq = @{}
foreach ($t in $TIPOS.Keys) {
    $a = Procurar $TIPOS[$t].padrao
    if (-not $a.Count -and -not $explicito -and $TIPOS[$t].url) {
        $pastaImp = Join-Path $Raiz "importar"; $nomeZ = Split-Path -Leaf $TIPOS[$t].url
        $destB = Join-Path $pastaImp $nomeZ; $tmpB = "$destB.baixando"
        Anotar "baixando do TSE: $($TIPOS[$t].url) (arquivo grande, pode levar varios minutos)..." "Cyan"
        try {
            if (-not (Test-Path $pastaImp)) { New-Item -ItemType Directory -Path $pastaImp | Out-Null }
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            Invoke-WebRequest -Uri $TIPOS[$t].url -OutFile $tmpB -UseBasicParsing -TimeoutSec 3600
            $zt = [IO.Compression.ZipFile]::OpenRead($tmpB); $zt.Dispose()
            Move-Item -LiteralPath $tmpB -Destination $destB -Force
            Anotar ("   baixado: {0} ({1} MB)" -f $nomeZ, [math]::Round((Get-Item $destB).Length / 1MB, 1)) "Green"
        } catch {
            Remove-Item -LiteralPath $tmpB -Force -ErrorAction SilentlyContinue
            Anotar "   nao consegui baixar ($($_.Exception.Message)). Baixe na mao em dadosabertos.tse.jus.br > Resultados > 2022 ($nomeZ) e ponha na pasta importar." "Yellow"
        }
        $a = Procurar $TIPOS[$t].padrao
    }
    if ($a.Count) { $arq[$t] = $a[0] }
}
# sem o nominal, a votacao em partido serve (mesmos votos; falta so o nome)
$fonteV = "votacao_candidato_munzona_2022"
if (-not $arq.ContainsKey("votacao") -and $arq.ContainsKey("partido")) {
    $arq["votacao"] = $arq["partido"]; $fonteV = "votacao_partido_munzona_2022"
    Anotar "sem a votacao nominal: uso a votacao em partido ($($arq['partido'].Name)) - os numeros sao os mesmos; so o nome do governador de 2022 fica em branco" "Yellow"
}
foreach ($t in $arq.Keys) { Anotar ("arquivo {0}: {1}" -f $t, $arq[$t].FullName) }
if (-not $arq.ContainsKey("votacao")) {
    Anotar "Procurei em:" "Yellow"; foreach ($o in $onde) { Anotar "   $o" }
    Sair "falta votacao_candidato_munzona_2022.zip (ou votacao_partido_munzona_2022.zip) do TSE Dados Abertos. Baixe em dadosabertos.tse.jus.br > Resultados - 2022 e ponha na pasta importar." 1
}

# ------------------------------------------------------------- leitura rapida
# Soma as linhas pela chave (colunas escolhidas), so dos cargos 1 e 3.
try {
    if (-not ("Gctse2022" -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.IO;
using System.Collections.Generic;
public static class Gctse2022 {
    static string[] Campos(string l) {
        var r = new List<string>(64); var sb = new System.Text.StringBuilder(); int i = 0, n = l.Length;
        while (true) {
            sb.Length = 0;
            if (i < n && l[i] == '"') {
                i++;
                while (i < n) { char c = l[i]; if (c == '"') { if (i + 1 < n && l[i + 1] == '"') { sb.Append('"'); i += 2; continue; } i++; break; } sb.Append(c); i++; }
                while (i < n && l[i] != ';') { sb.Append(l[i]); i++; }
            } else { while (i < n && l[i] != ';') { sb.Append(l[i]); i++; } }
            r.Add(sb.ToString()); if (i >= n) break; i++;
        }
        return r.ToArray();
    }
    static long Num(string[] p, int i) { long x; if (i >= 0 && i < p.Length && long.TryParse(p[i].Trim(), out x)) return x; return 0; }
    // chave = colunas kix unidas por |, so linhas com cargo (icargo) 1 ou 3; soma as colunas vix
    public static long Ler(TextReader rd, int icargo, int[] kix, int[] vix, Dictionary<string, long[]> agg) {
        long n = 0; string linha;
        while ((linha = rd.ReadLine()) != null) {
            n++;
            if (n % 2000000 == 0) Console.WriteLine("   " + n.ToString("N0") + " linhas...");
            string[] p = Campos(linha);
            if (icargo < 0 || icargo >= p.Length) continue;
            string cg = p[icargo].Trim(); if (cg != "1" && cg != "3") continue;
            var sb = new System.Text.StringBuilder();
            for (int k = 0; k < kix.Length; k++) { if (k > 0) sb.Append('|'); if (kix[k] >= 0 && kix[k] < p.Length) sb.Append(p[kix[k]].Trim()); }
            string key = sb.ToString(); long[] v;
            if (!agg.TryGetValue(key, out v)) { v = new long[vix.Length]; agg[key] = v; }
            for (int k = 0; k < vix.Length; k++) v[k] += Num(p, vix[k]);
        }
        return n;
    }
}
"@
    }
} catch { Sair "nao consegui preparar a leitura do arquivo: $($_.Exception.Message)" 1 }

function Fontes($Arq) {
    $lista = @()
    if ($Arq.Extension -match '(?i)\.zip$') {
        $zip = [IO.Compression.ZipFile]::OpenRead($Arq.FullName)
        $csvs = @($zip.Entries | Where-Object { $_.Name -match '(?i)\.(csv|txt)$' })
        # _BRASIL = todos os estados juntos num arquivo so: com os arquivos
        # de cada estado no zip, fica de fora (senao tudo conta duas vezes).
        # _BR = Presidente do Brasil todo: fica marcado (ver Juntar)
        if (@($csvs | Where-Object { $_.Name -notmatch '(?i)_BRASIL\.(csv|txt)$' }).Count -gt 0) { $csvs = @($csvs | Where-Object { $_.Name -notmatch '(?i)_BRASIL\.(csv|txt)$' }) }
        foreach ($e in $csvs) { $lista += [pscustomobject]@{ nome = "$($Arq.Name) > $($e.FullName)"; entrada = $e; caminho = ""; br = ($e.Name -match '(?i)_BR\.(csv|txt)$') } }
    } else { $lista += [pscustomobject]@{ nome = $Arq.Name; entrada = $null; caminho = $Arq.FullName; br = ($Arq.Name -match '(?i)_BR\.(csv|txt)$') } }
    return $lista
}
function Abrir($F) {
    if ($F.entrada) { return New-Object IO.StreamReader($F.entrada.Open(), $Latin1) }
    return New-Object IO.StreamReader($F.caminho, $Latin1)
}
function Indices([string] $Cab) {
    $ix = @{}; $c = $Cab.Split(';'); for ($i = 0; $i -lt $c.Count; $i++) { $ix[$c[$i].Trim().Trim('"').ToUpper()] = $i }; return $ix
}
function Achar($Ix, [string[]] $Nomes) { foreach ($nm in $Nomes) { if ($Ix.ContainsKey($nm)) { return $Ix[$nm] } }; return -1 }

# Juntar: Governador vem dos arquivos dos estados; Presidente vem do arquivo
# do BRASIL quando ele traz Presidente (senao, da soma dos estados). Assim
# nenhum voto entra duas vezes, qualquer que seja o jeito que o TSE dividiu.
function Juntar($PorArq) {
    $temBr1 = @($PorArq | Where-Object { $_.br -and @($_.d.Keys | Where-Object { $_.Split('|')[2] -eq "1" }).Count -gt 0 }).Count -gt 0
    $out = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
    foreach ($pa in $PorArq) {
        foreach ($kv in $pa.d.GetEnumerator()) {
            $cg = $kv.Key.Split('|')[2]
            if ($cg -eq "1" -and $temBr1 -and -not $pa.br) { continue }
            if ($cg -eq "3" -and $pa.br) { continue }
            $v = $null
            if (-not $out.TryGetValue($kv.Key, [ref] $v)) { $v = (New-Object long[] $kv.Value.Length); $out[$kv.Key] = $v }
            for ($i = 0; $i -lt $v.Length; $i++) { $v[$i] += $kv.Value[$i] }
        }
    }
    return ,$out
}
# ---------------------------------------------------- votos dos candidatos
# chave: turno|uf|cargo|numero|partido|nome|situacao|destinacao  -> votos
$porArqV = @()
foreach ($f in (Fontes $arq["votacao"])) {
    $rd = Abrir $f
    try {
        $ix = Indices ($rd.ReadLine())
        $k = [int[]] @((Achar $ix @("NR_TURNO")), (Achar $ix @("SG_UF")), (Achar $ix @("CD_CARGO")), (Achar $ix @("NR_CANDIDATO", "NR_PARTIDO")), (Achar $ix @("SG_PARTIDO")),
                       (Achar $ix @("NM_URNA_CANDIDATO", "NM_CANDIDATO")), (Achar $ix @("DS_SIT_TOT_TURNO")), (Achar $ix @("NM_TIPO_DESTINACAO_VOTOS")))
        $iv = Achar $ix @("QT_VOTOS_NOMINAIS_VALIDOS", "QT_VOTOS_NOMINAIS", "QT_VOTOS")
        if ($k[0] -lt 0 -or $k[1] -lt 0 -or $k[2] -lt 0 -or $k[3] -lt 0 -or $iv -lt 0) { Anotar "$($f.nome): colunas NR_TURNO/SG_UF/CD_CARGO/NR_CANDIDATO/QT_VOTOS nao encontradas - pulei" "Yellow"; continue }
        if ($f.nome -match '(?i)leiame') { continue }
        Anotar "lendo $($f.nome) ..." "Cyan"
        $t0 = Get-Date
        $dA = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
        $n = [Gctse2022]::Ler($rd, $k[2], $k, [int[]] @($iv), $dA)
        $porArqV += [pscustomobject]@{ br = $f.br; d = $dA }
        Anotar ("   {0:N0} linhas em {1:N0} s" -f $n, ((Get-Date) - $t0).TotalSeconds)
    } finally { $rd.Dispose() }
}
$votos = Juntar $porArqV
# ---------------------------------------------- aptos, comparecimento etc.
# chave: turno|uf|cargo -> aptos, comparecimento, abstencoes, brancos, nulos
$det = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
$porArqD = @()
if ($arq.ContainsKey("detalhe")) {
    foreach ($f in (Fontes $arq["detalhe"])) {
        $rd = Abrir $f
        try {
            $ix = Indices ($rd.ReadLine())
            $k = [int[]] @((Achar $ix @("NR_TURNO")), (Achar $ix @("SG_UF")), (Achar $ix @("CD_CARGO")))
            $vv = [int[]] @((Achar $ix @("QT_APTOS")), (Achar $ix @("QT_COMPARECIMENTO")), (Achar $ix @("QT_ABSTENCOES", "QT_ABSTENCAO")),
                            (Achar $ix @("QT_VOTOS_BRANCOS")), (Achar $ix @("QT_TOTAL_VOTOS_NULOS", "QT_VOTOS_NULOS")))
            if ($k[2] -lt 0 -or $vv[0] -lt 0 -or $vv[1] -lt 0) { Anotar "$($f.nome): colunas QT_APTOS/QT_COMPARECIMENTO nao encontradas - pulei" "Yellow"; continue }
            Anotar "lendo $($f.nome) ..." "Cyan"
            $dD = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
            $n = [Gctse2022]::Ler($rd, $k[2], $k, $vv, $dD)
            $porArqD += [pscustomobject]@{ br = $f.br; d = $dD }
            Anotar ("   {0:N0} linhas" -f $n)
        } finally { $rd.Dispose() }
    }
    $det = Juntar $porArqD
} else { Anotar "sem detalhe_votacao_munzona_2022: as telas de abstencao/brancos/nulos de 2022 ficam sem 2022" "Yellow" }
if ($votos.Count -eq 0) { Sair "nenhum voto de Presidente/Governador lido do arquivo de 2022." 1 }

# ------------------------------------------------------------------ somar
$UFs = @("ac","al","ap","am","ba","ce","df","es","go","ma","mt","ms","mg","pa","pb","pr","pe","pi","rj","rn","rs","ro","rr","sc","sp","se","to")
# cand[turno][cargo][uf][numero] = @{ v; sg; nome; sit }
$C = @{}
foreach ($kv in $votos.GetEnumerator()) {
    $p = $kv.Key.Split('|'); $tu = $p[0]; $u = $p[1].ToLower(); $cg = $p[2]; $num = $p[3]
    if ($p[7] -and $p[7] -notmatch '(?i)^v') { continue }       # so voto VALIDO (nao anulado)
    foreach ($alvo in @($u, $(if ($cg -eq "1") { "br" } else { $null }))) {
        if (-not $alvo) { continue }
        $ch = "$tu|$cg|$alvo"
        if (-not $C.ContainsKey($ch)) { $C[$ch] = @{} }
        if (-not $C[$ch].ContainsKey($num)) { $C[$ch][$num] = @{ v = [int64] 0; sg = $p[4]; nome = $p[5]; sit = $p[6] } }
        $C[$ch][$num].v += $kv.Value[0]
        if ($alvo -ne "br" -and $p[6]) { $C[$ch][$num].sit = $p[6] }
    }
}
$Dt = @{}
foreach ($kv in $det.GetEnumerator()) {
    $p = $kv.Key.Split('|'); $tu = $p[0]; $u = $p[1].ToLower(); $cg = $p[2]
    foreach ($alvo in @($u, $(if ($cg -eq "1") { "br" } else { $null }))) {
        if (-not $alvo) { continue }
        $ch = "$tu|$cg|$alvo"
        if (-not $Dt.ContainsKey($ch)) { $Dt[$ch] = (New-Object long[] 5) }
        for ($i = 0; $i -lt 5; $i++) { $Dt[$ch][$i] += $kv.Value[$i] }
    }
}
function R2([double] $x) { return [math]::Round($x, 2) }
function Partidos([string] $Ch) {
    # mesmo formato do ESTADOS.bat: % dos validos por partido + _nome_, _votos_, _pc, _pa, _pvb, _pvn, _aptos
    if (-not $C.ContainsKey($Ch)) { return $null }
    $cs = $C[$Ch]; $tot = [double] 0; foreach ($n in $cs.Keys) { $tot += $cs[$n].v }
    if ($tot -le 0) { return $null }
    $r = [ordered]@{}
    foreach ($n in ($cs.Keys | Sort-Object { -$cs[$_].v })) {
        $sg = $cs[$n].sg; if (-not $sg -or $r.Contains($sg)) { continue }
        $r[$sg] = R2 (100.0 * $cs[$n].v / $tot); $r["_nome_$sg"] = $cs[$n].nome; $r["_votos_$sg"] = $cs[$n].v
    }
    if ($Dt.ContainsKey($Ch)) {
        $d = $Dt[$Ch]; $ap = [double] $d[0]; $co = [double] $d[1]
        if ($ap -gt 0) { $r["_pc"] = R2 (100.0 * $co / $ap); $r["_pa"] = R2 (100.0 * $d[2] / $ap); $r["_aptos"] = [int64] $ap }
        if ($co -gt 0) { $r["_pvb"] = R2 (100.0 * $d[3] / $co); $r["_pvn"] = R2 (100.0 * $d[4] / $co) }
    }
    return [pscustomobject] $r
}
# ------------------------------- historico de totalizacao (Presidente, Brasil)
# A ultima linha (100% das secoes) traz aptos, votos (= comparecimento),
# brancos, nulos e os votos de cada candidato. Serve quando falta o detalhe.
function Ler-Historico($Arq) {
    if (-not $Arq) { return $null }
    $f = @(Fontes $Arq | Where-Object { $_.nome -notmatch '(?i)leiame' }) | Select-Object -First 1
    if (-not $f) { return $null }
    $rd = Abrir $f; $melhor = $null; $cab = $null
    try {
        $ix = Indices ($rd.ReadLine()); $cab = $ix
        $iUe = Achar $ix @("SG_UE_UF"); $iVt = Achar $ix @("QT_VOTOS_TOTAL_ACUMULADO")
        if ($iVt -lt 0) { return $null }
        while ($null -ne ($l = $rd.ReadLine())) {
            $p = $l.Split(';'); if ($p.Count -le $iVt) { continue }
            if ($iUe -ge 0 -and $p[$iUe].Trim() -ne "BR") { continue }
            $vt = [int64] 0; if (-not [int64]::TryParse($p[$iVt].Trim(), [ref] $vt)) { continue }
            if ($null -eq $melhor -or $vt -ge $melhor.vt) { $melhor = @{ vt = $vt; p = $p } }
        }
    } finally { $rd.Dispose() }
    if ($null -eq $melhor) { return $null }
    $p = $melhor.p
    function Nx([string] $Col, $Ix, [string[]] $P) { $i = Achar $Ix @($Col); if ($i -lt 0) { return $null }; $x = [int64] 0; if ([int64]::TryParse($P[$i].Trim(), [ref] $x)) { return $x }; return $null }
    $r = @{ aptos = (Nx "QT_APTOS_TOTAL" $cab $p); votos = $melhor.vt; brancos = (Nx "BRANCO_QT_VOTOS_TOT_ACUMULADO" $cab $p); nulos = (Nx "NULO_QT_VOTOS_TOT_ACUMULADO" $cab $p); secoes = $null; cands = @{}; fonte = $f.nome }
    $iS = Achar $cab @("PE_SECOES_TOT_ACUMULADO"); if ($iS -ge 0) { $d = 0.0; if ([double]::TryParse($p[$iS].Trim().Replace(",", "."), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref] $d)) { $r.secoes = R2 (100.0 * $d) } }
    foreach ($nm in $cab.Keys) {
        if ($nm -notmatch '_QT_VOTOS_TOT_ACUMULADO$' -or $nm -match '^(BRANCO|NULO)_') { continue }
        $x = Nx $nm $cab $p; if ($null -ne $x) { $r.cands[(($nm -replace '_QT_VOTOS_TOT_ACUMULADO$', '') -replace '_', ' ')] = $x }
    }
    Anotar ("historico {0}: {1:N0} aptos, {2:N0} votos, {3:N0} brancos, {4:N0} nulos ({5}% das secoes)" -f $f.nome, $r.aptos, $r.votos, $r.brancos, $r.nulos, $r.secoes)
    return $r
}
$H1 = Ler-Historico $arq["hist1"]; $H2 = Ler-Historico $arq["hist2"]
function Do-Historico($H) {
    # aptos, comparecimento, abstencao, brancos e nulos - como o detalhe
    if (-not $H -or -not $H.aptos -or -not $H.votos -or $null -eq $H.brancos -or $null -eq $H.nulos) { return $null }
    return [int64[]] @($H.aptos, $H.votos, ($H.aptos - $H.votos), $H.brancos, $H.nulos)
}
foreach ($par in @(@("1|1|br", $H1), @("2|1|br", $H2))) {
    $x = Do-Historico $par[1]
    if ($x -and -not $Dt.ContainsKey($par[0])) { $Dt[$par[0]] = $x; Anotar "Brasil (turno $($par[0].Substring(0,1))): comparecimento, abstencao, brancos e nulos do historico de totalizacao" }
}
# Presidente 1o turno (Brasil): abstencao, brancos, nulos, comparecimento
$ref1 = $null
if ($Dt.ContainsKey("1|1|br")) {
    $d = $Dt["1|1|br"]; $ap = [double] $d[0]; $co = [double] $d[1]
    if ($ap -gt 0 -and $co -gt 0) {
        $ref1 = [ordered]@{ pct_comparec = R2 (100.0 * $co / $ap); pct_abstencao = R2 (100.0 * $d[2] / $ap); pct_brancos = R2 (100.0 * $d[3] / $co); pct_nulos = R2 (100.0 * $d[4] / $co); urnas_pct = 100; fonte = $(if ($arq.ContainsKey("detalhe")) { "TSE Dados Abertos - detalhe_votacao_munzona_2022" } else { "TSE Dados Abertos - Historico_Totalizacao_Presidente_BR_1T_2022" }) }
        if (-not $arq.ContainsKey("detalhe") -and $H1 -and $null -ne $H1.secoes) { $ref1.urnas_pct = $H1.secoes }
    }
}
# Presidente 2o turno: Brasil + estados + exterior
$ufs2 = [ordered]@{}
foreach ($u in ($UFs + @("zz"))) { $x = Partidos "2|1|$u"; if ($x) { $ufs2[$u] = $x } }
$br2 = Partidos "2|1|br"
# sem o nominal: nome do candidato do historico, achado pelos votos (iguais)
if ($br2 -and $H2) {
    foreach ($pr in @($br2.PSObject.Properties | Where-Object { $_.Name -notmatch '^_' })) {
        $sg = $pr.Name
        if ("$($br2.("_nome_$sg"))") { continue }
        $vv = [double] $br2.("_votos_$sg")
        foreach ($nm in $H2.cands.Keys) { if ($vv -gt 0 -and [math]::Abs($H2.cands[$nm] - $vv) -le [math]::Max(1, 0.001 * $vv)) { $br2.("_nome_$sg") = $nm } }
    }
}
$ref2 = $null
if ($br2) { $ref2 = [ordered]@{ eleicao = "545"; br = $br2; ufs = [pscustomobject] $ufs2; completo = (@($ufs2.Keys | Where-Object { $_ -ne "zz" }).Count -ge 27); fonte = "TSE Dados Abertos - $fonteV" } }
# Governadores eleitos em 2022 (1o ou 2o turno)
$gov = [ordered]@{}
foreach ($u in $UFs) {
    foreach ($tu in @("1", "2")) {
        $ch = "$tu|3|$u"; if (-not $C.ContainsKey($ch)) { continue }
        $cs = $C[$ch]; $tot = [double] 0; foreach ($n in $cs.Keys) { $tot += $cs[$n].v }
        $el = @($cs.Keys | Where-Object { "$($cs[$_].sit)" -match '(?i)^\s*eleit' } | Sort-Object { -$cs[$_].v }) | Select-Object -First 1
        # sem a situacao (votacao em partido): a regra da eleicao - no 1o turno,
        # eleito com mais da metade dos validos; no 2o, o mais votado
        if (-not $el -and -not @($cs.Keys | Where-Object { "$($cs[$_].sit)" }).Count -and $tot -gt 0) {
            $top = @($cs.Keys | Sort-Object { -$cs[$_].v }) | Select-Object -First 1
            if ($tu -eq "2" -or $cs[$top].v -gt $tot / 2) { $el = $top }
        }
        if ($el -and $tot -gt 0) { $gov[$u] = [ordered]@{ partido = $cs[$el].sg; nome = $cs[$el].nome; pct = R2 (100.0 * $cs[$el].v / $tot); turno = [int] $tu }; break }
    }
}
$refG = $null
if ($gov.Count) { $refG = [ordered]@{ eleicao = "546"; eleicao_2turno = "547"; ufs = [pscustomobject] $gov; completo = ($gov.Count -ge 27); fonte = "TSE Dados Abertos - $fonteV" } }

$saida = [ordered]@{
    gerado_em = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    fonte = "TSE - Portal de Dados Abertos (Resultados 2022)"
    ref2022 = $ref1; ref2022_2t = $ref2; ref2022_gov = $refG
}
$destino = Join-Path $Raiz "dados-2022.json"
[IO.File]::WriteAllText($destino, ($saida | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
if ($ref1) { Anotar ("2022 Presidente 1o turno (Brasil): abstencao {0}% | brancos {1}% | nulos {2}%" -f $ref1.pct_abstencao, $ref1.pct_brancos, $ref1.pct_nulos) "Green" } else { Anotar "2022 Presidente 1o turno: sem o detalhe (abstencao/brancos/nulos)" "Yellow" }
if ($br2) { $top = @($br2.PSObject.Properties | Where-Object { $_.Name -notmatch '^_' } | Select-Object -First 2 | ForEach-Object { "$($_.Name) $($_.Value)%" }) -join " x "; Anotar ("2022 Presidente 2o turno: Brasil {0} | {1} estados" -f $top, @($ufs2.Keys | Where-Object { $_ -ne "zz" }).Count) "Green" } else { Anotar "2022 Presidente 2o turno: nao encontrado no arquivo" "Yellow" }
Anotar ("2022 Governador: {0} de 27 eleitos encontrados" -f $gov.Count) $(if ($gov.Count -ge 27) { "Green" } else { "Yellow" })
$semG = @($UFs | Where-Object { -not $gov.Contains($_) })
if ($semG.Count) { Anotar ("   sem o eleito de 2022 em: {0} - {1}" -f ($semG -join ", ").ToUpper(), $(if ($fonteV -match 'partido') { "a votacao em partido nao diz quem foi eleito (votos anulados depois da eleicao mudam a conta); com a votacao nominal (votacao_candidato_munzona_2022) o TSE diz" } else { "o arquivo nao marca eleito nesse estado" })) "Yellow" }
Sair "gravado dados-2022.json. O ESTADOS.bat passa a usar estes numeros de 2022 (reabra o ESTADOS.bat ou espere ate 30 min)." 0
