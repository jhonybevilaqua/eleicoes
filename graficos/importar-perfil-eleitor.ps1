<#
    gctse GRAFICOS - IMPORTAR PERFIL DO ELEITOR (telas do Jornalismo)

    Le dois arquivos oficiais do TSE (Portal de Dados Abertos) e grava
    web\perfil-eleitor.js:
      perfil_eleitorado_2026.zip ......... QUEM PODE VOTAR: eleitores aptos
                                           por sexo, faixa etaria,
                                           escolaridade e cor/raca (quando o
                                           arquivo trouxer). Ja publicado.
      perfil_comparecimento_abstencao_2026.zip
                                           QUEM FOI AS URNAS: aptos e
                                           comparecimento por perfil. O TSE
                                           publica DEPOIS da eleicao.
    Classe social/renda: o TSE NAO coleta - nao existe nestes arquivos.

    Sem o arquivo, tenta baixar do TSE para a pasta "importar"; se nao
    der, baixe em dadosabertos.tse.jus.br e ponha na pasta importar.
    As colunas sao achadas pelo nome (DS_GENERO, DS_FAIXA_ETARIA,
    DS_GRAU_ESCOLARIDADE, cor/raca, QT_...), entao serve para 2022 e 2026.
#>
[CmdletBinding(PositionalBinding = $false)]
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Caminhos = @())
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch { }
try { Add-Type -AssemblyName System.IO.Compression } catch { }

$script:Diag = New-Object System.Collections.Generic.List[string]
function Anotar([string] $Texto, [string] $Cor = "Gray") { Write-Host $Texto -ForegroundColor $Cor; $script:Diag.Add($Texto) }
function Sair([string] $Msg, [int] $Codigo) {
    if ($Codigo -ne 0) { Anotar $Msg "Red" } else { Anotar $Msg "Green" }
    try { [IO.File]::WriteAllLines((Join-Path $Raiz "IMPORTAR-PERFIL-ELEITOR.txt"), $script:Diag, (New-Object System.Text.UTF8Encoding($true))) } catch { }
    exit $Codigo
}
$Latin1 = [Text.Encoding]::GetEncoding(28591)   # os CSV do TSE vem em Latin-1
$Padrao = '(?i)^(perfil_eleitorado|perfil_comparecimento_abstencao)_(20\d\d).*\.(zip|csv|txt)$'

# ------------------------------------------------------------- achar arquivos
$explicito = ($Caminhos -and @($Caminhos | Where-Object { $_ }).Count -gt 0)
$onde = @()
if ($explicito) { $onde = @($Caminhos | Where-Object { $_ } | ForEach-Object { "$_".Trim('"') }) }
else {
    $onde = @((Join-Path $Raiz "importar"), $Raiz)
    if ($env:USERPROFILE) { $onde += @((Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop")) }
}
function Procurar() {
    $achados = @()
    foreach ($o in ($onde | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $o -PathType Leaf) { $achados += @(Get-Item -LiteralPath $o); continue }
        if (Test-Path -LiteralPath $o -PathType Container) {
            $achados += @(Get-ChildItem -LiteralPath $o -File -Recurse -Depth 1 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $Padrao })
        }
    }
    return @($achados | Sort-Object FullName -Unique)
}
$arquivos = Procurar

# Sem o arquivo de 2026: baixa do TSE (endereco oficial dos Dados Abertos).
if (-not $explicito) {
    $pastaImp = Join-Path $Raiz "importar"
    foreach ($tipoB in @("perfil_eleitorado", "perfil_comparecimento_abstencao")) {
        if (@($arquivos | Where-Object { $_.Name -match "(?i)^$($tipoB)_2026" }).Count -gt 0) { continue }
        $urlB = "https://cdn.tse.jus.br/estatistica/sead/odsele/$tipoB/$($tipoB)_2026.zip"
        $destB = Join-Path $pastaImp "$($tipoB)_2026.zip"
        $tmpB = "$destB.baixando"
        Anotar "baixando do TSE: $urlB (arquivo grande, pode levar varios minutos)..." "Cyan"
        try {
            if (-not (Test-Path $pastaImp)) { New-Item -ItemType Directory -Path $pastaImp | Out-Null }
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            $pp = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
            try { Invoke-WebRequest -Uri $urlB -OutFile $tmpB -UseBasicParsing -TimeoutSec 1800 } finally { $ProgressPreference = $pp }
            $zt = [IO.Compression.ZipFile]::OpenRead($tmpB); $zt.Dispose()
            Move-Item -LiteralPath $tmpB -Destination $destB -Force
            Anotar ("   baixado: {0}_2026.zip ({1} MB)" -f $tipoB, [math]::Round((Get-Item $destB).Length / 1MB, 1)) "Green"
        } catch {
            Remove-Item -LiteralPath $tmpB -Force -ErrorAction SilentlyContinue
            if ($tipoB -eq "perfil_comparecimento_abstencao") { Anotar "   ainda nao disponivel ($($_.Exception.Message)). O TSE publica o comparecimento por perfil DEPOIS da eleicao; rode de novo nos dias seguintes." "Yellow" }
            else { Anotar "   nao consegui baixar ($($_.Exception.Message)). Baixe na mao em dadosabertos.tse.jus.br > Eleitorado > Perfil do eleitorado 2026 e ponha na pasta importar." "Yellow" }
        }
    }
    $arquivos = Procurar
}
if ($arquivos.Count -eq 0) {
    Anotar "Procurei em:" "Yellow"; foreach ($o in $onde) { Anotar "   $o" }
    Sair "nenhum perfil_eleitorado_2026.zip nem perfil_comparecimento_abstencao_2026.zip. Baixe em dadosabertos.tse.jus.br e ponha na pasta importar." 1
}

# ---------------------------------------------------------------- ler o CSV
# Do zip, usa o arquivo do BRASIL se existir; senao, todos os estados.
function Fontes($Arq) {
    $lista = @()
    if ($Arq.Extension -match '(?i)\.zip$') {
        $zip = [IO.Compression.ZipFile]::OpenRead($Arq.FullName)
        $csvs = @($zip.Entries | Where-Object { $_.Name -match '(?i)\.(csv|txt)$' })
        $br = @($csvs | Where-Object { $_.Name -match '(?i)BRASIL' })
        if ($br.Count -gt 0) { $csvs = $br }
        foreach ($e in $csvs) { $lista += [pscustomobject]@{ nome = "$($Arq.Name) > $($e.FullName)"; entrada = $e; caminho = "" } }
    } else {
        $lista += [pscustomobject]@{ nome = $Arq.Name; entrada = $null; caminho = $Arq.FullName }
    }
    return $lista
}
function Abrir($F) {
    if ($F.entrada) { return New-Object IO.StreamReader($F.entrada.Open(), $Latin1) }
    return New-Object IO.StreamReader($F.caminho, $Latin1)
}
function Campos([string] $L) {
    if ($L.StartsWith('"')) { return $L.Substring(1, [Math]::Max(0, $L.Length - 2)).Split(@('";"'), [StringSplitOptions]::None) }
    return $L.Split(';')
}
function Achar($Ix, [string[]] $Nomes) { foreach ($nm in $Nomes) { if ($Ix.ContainsKey($nm)) { return $Ix[$nm] } }; return -1 }

# agregado: tipo|ano|turno -> @{ total = long[2]; dims = @{ dim = @{ rotulo = long[2] } } }
# long[0] = eleitores (eleitorado) ou aptos (comparecimento); long[1] = comparecimento
$Agg = @{}

# Leitura rapida: o laco das linhas em C# (compilado pelo proprio Windows na
# hora); o arquivo do TSE tem milhoes de linhas e o PowerShell puro levaria
# dezenas de minutos. Se a compilacao falhar, usa o laco em PowerShell.
$script:Rapido = $false
try {
    if (-not ("GctsePerfil" -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.IO;
using System.Collections.Generic;
public static class GctsePerfil {
    static string[] Campos(string l) {
        if (l.Length > 1 && l[0] == '"') return l.Substring(1, l.Length - 2).Split(new string[] { "\";\"" }, StringSplitOptions.None);
        return l.Split(';');
    }
    static string Pega(string[] p, int i, string padrao) { return (i >= 0 && i < p.Length) ? p[i] : padrao; }
    static long Num(string[] p, int i) { long x; if (i >= 0 && i < p.Length && long.TryParse(p[i], out x)) return x; return 0; }
    // ix: ano, turno, sexo, idade, escolaridade, cor, qt0, qt1, abstencao
    public static long Ler(TextReader rd, int[] ix, string anoArq, Dictionary<string, long[]> combo) {
        long n = 0; string linha;
        while ((linha = rd.ReadLine()) != null) {
            n++;
            if (n % 1000000 == 0) Console.WriteLine("   " + n.ToString("N0") + " linhas...");
            string[] p = Campos(linha);
            long q0 = Num(p, ix[6]), q1 = Num(p, ix[7]);
            if (ix[6] < 0 && ix[8] >= 0) q0 = q1 + Num(p, ix[8]);
            string k = Pega(p, ix[0], anoArq) + "|" + Pega(p, ix[1], "") + "\t" + Pega(p, ix[2], "") + "\t" + Pega(p, ix[3], "") + "\t" + Pega(p, ix[4], "") + "\t" + Pega(p, ix[5], "");
            long[] v;
            if (!combo.TryGetValue(k, out v)) { v = new long[2]; combo[k] = v; }
            v[0] += q0; v[1] += q1;
        }
        return n;
    }
}
"@
    }
    $script:Rapido = $true
} catch { Anotar "aviso: leitura rapida indisponivel ($($_.Exception.Message)); usando a lenta (pode demorar)." "Yellow" }
function Ler-Lento($Rd, [int[]] $Ix, [string] $AnoArq, $Combo) {
    $n = 0
    while ($null -ne ($linha = $Rd.ReadLine())) {
        $n++
        if ($n % 500000 -eq 0) { Write-Host ("   {0:N0} linhas..." -f $n) -ForegroundColor DarkGray }
        $p = Campos $linha
        $v = New-Object string[] 6
        for ($j = 0; $j -lt 6; $j++) { $v[$j] = $(if ($Ix[$j] -ge 0 -and $Ix[$j] -lt $p.Count) { $p[$Ix[$j]] } else { "" }) }
        if (-not $v[0]) { $v[0] = $AnoArq }
        $q0 = [long] 0; $q1 = [long] 0; $x = [long] 0
        if ($Ix[6] -ge 0 -and [long]::TryParse($p[$Ix[6]], [ref] $x)) { $q0 = $x }
        if ($Ix[7] -ge 0 -and [long]::TryParse($p[$Ix[7]], [ref] $x)) { $q1 = $x }
        if ($Ix[6] -lt 0 -and $Ix[8] -ge 0 -and [long]::TryParse($p[$Ix[8]], [ref] $x)) { $q0 = $q1 + $x }
        $k = $v[0] + "|" + $v[1] + "`t" + $v[2] + "`t" + $v[3] + "`t" + $v[4] + "`t" + $v[5]
        $cv = $null
        if (-not $Combo.TryGetValue($k, [ref] $cv)) { $cv = (New-Object long[] 2); $Combo[$k] = $cv }
        $cv[0] += $q0; $cv[1] += $q1
    }
    return $n
}
foreach ($a in $arquivos) {
    $mA = [regex]::Match($a.Name, $Padrao)
    $tipo = $(if ($mA.Groups[1].Value -match '(?i)compar') { "comparecimento" } else { "eleitorado" })
    $anoArq = $mA.Groups[2].Value
    foreach ($f in (Fontes $a)) {
        $rd = Abrir $f
        try {
            $cab = Campos ($rd.ReadLine())
            $ix = @{}; for ($i = 0; $i -lt $cab.Count; $i++) { $ix[$cab[$i].Trim().Trim('"').ToUpper()] = $i }
            $iGen = Achar $ix @("DS_GENERO", "DS_SEXO")
            $iIda = Achar $ix @("DS_FAIXA_ETARIA")
            $iEsc = Achar $ix @("DS_GRAU_ESCOLARIDADE", "DS_GRAU_INSTRUCAO")
            $iRac = -1; foreach ($k in $ix.Keys) { if ($k -match '^DS_.*(RACA|COR_RACA)') { $iRac = $ix[$k] } }
            $iTur = Achar $ix @("NR_TURNO")
            $iAno = Achar $ix @("ANO_ELEICAO")
            if ($tipo -eq "eleitorado") {
                $iQ0 = Achar $ix @("QT_ELEITORES_PERFIL", "QT_ELEITORES"); $iQ1 = -1; $iAbs = -1
                if ($iQ0 -lt 0) { throw "coluna QT_ELEITORES_PERFIL nao encontrada" }
            } else {
                $iQ0 = Achar $ix @("QT_APTOS"); $iQ1 = Achar $ix @("QT_COMPARECIMENTO"); $iAbs = Achar $ix @("QT_ABSTENCAO")
                if ($iQ1 -lt 0) { throw "coluna QT_COMPARECIMENTO nao encontrada" }
                if ($iQ0 -lt 0 -and $iAbs -lt 0) { throw "colunas QT_APTOS / QT_ABSTENCAO nao encontradas" }
            }
            $dimsIx = [ordered]@{ genero = $iGen; idade = $iIda; escolaridade = $iEsc; raca = $iRac }
            Anotar ("lendo {0} ({1}) - colunas: sexo {2}, idade {3}, escolaridade {4}, cor/raca {5}" -f $f.nome, $tipo,
                $(if ($iGen -ge 0) { "sim" } else { "NAO" }), $(if ($iIda -ge 0) { "sim" } else { "NAO" }), $(if ($iEsc -ge 0) { "sim" } else { "NAO" }), $(if ($iRac -ge 0) { "sim" } else { "NAO (o arquivo nao traz)" })) "Cyan"
            $ixs = [int[]] @($iAno, $iTur, $iGen, $iIda, $iEsc, $iRac, $iQ0, $iQ1, $iAbs)
            $combo = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
            $t0 = Get-Date
            if ($script:Rapido) { $n = [GctsePerfil]::Ler($rd, $ixs, $anoArq, $combo) }
            else { $n = Ler-Lento $rd $ixs $anoArq $combo }
            # junta no agregado: chave "ano|turno<TAB>sexo<TAB>idade<TAB>escol.<TAB>cor"
            foreach ($kv in $combo.GetEnumerator()) {
                $tab = $kv.Key.IndexOf("`t")
                $chave = "$tipo|" + $kv.Key.Substring(0, $tab)
                if (-not $Agg.ContainsKey($chave)) { $Agg[$chave] = @{ total = (New-Object long[] 2); combo = @{}; dimsIx = $dimsIx } }
                $ag = $Agg[$chave]; $resto = $kv.Key.Substring($tab + 1)
                $ag.total[0] += $kv.Value[0]; $ag.total[1] += $kv.Value[1]
                $cv = $ag.combo[$resto]
                if ($null -eq $cv) { $cv = (New-Object long[] 2); $ag.combo[$resto] = $cv }
                $cv[0] += $kv.Value[0]; $cv[1] += $kv.Value[1]
            }
            Anotar ("   {0:N0} linhas lidas em {1:N0} s" -f $n, ((Get-Date) - $t0).TotalSeconds)
        } catch { Anotar ("{0}: {1}" -f $f.nome, $_.Exception.Message) "Yellow" }
        finally { $rd.Dispose() }
    }
}
if ($Agg.Count -eq 0) { Sair "nenhuma linha lida dos arquivos de perfil." 1 }

# ------------------------------------------------------------------ resumir
# Para cada tipo: o ano mais novo; no comparecimento, cada turno separado.
$saida = [ordered]@{
    gerado_em = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    fonte = "TSE - Portal de Dados Abertos (perfil do eleitorado / comparecimento e abstencao por perfil)"
}
foreach ($tipoS in @("eleitorado", "comparecimento")) {
    $chs = @($Agg.Keys | Where-Object { $_.StartsWith("$tipoS|") })
    if (-not $chs.Count) { continue }
    $anoS = ($chs | ForEach-Object { ($_ -split '\|')[1] } | Sort-Object | Select-Object -Last 1)
    $turnos = [ordered]@{}
    foreach ($ch in ($chs | Where-Object { ($_ -split '\|')[1] -eq $anoS } | Sort-Object)) {
        $ag = $Agg[$ch]; $tur = ($ch -split '\|')[2]; if (-not $tur) { $tur = "0" }
        $ag.dims = @{}
        $nomesD = @("genero", "idade", "escolaridade", "raca")
        foreach ($kv0 in $ag.combo.GetEnumerator()) {
            $partes = $kv0.Key.Split("`t")
            for ($di = 0; $di -lt 4; $di++) {
                if ($ag.dimsIx[$nomesD[$di]] -lt 0) { continue }
                $rot = $partes[$di].Trim(); if (-not $rot) { $rot = "NAO INFORMADO" }
                $dn = $nomesD[$di]
                if (-not $ag.dims.ContainsKey($dn)) { $ag.dims[$dn] = @{} }
                if (-not $ag.dims[$dn].ContainsKey($rot)) { $ag.dims[$dn][$rot] = (New-Object long[] 2) }
                $ag.dims[$dn][$rot][0] += $kv0.Value[0]; $ag.dims[$dn][$rot][1] += $kv0.Value[1]
            }
        }
        $dims = [ordered]@{}
        foreach ($d in @("genero", "idade", "escolaridade", "raca")) {
            if (-not $ag.dims.ContainsKey($d)) { continue }
            $m = [ordered]@{}; foreach ($kv in ($ag.dims[$d].GetEnumerator() | Sort-Object Name)) { $m[$kv.Key] = @($kv.Value[0], $kv.Value[1]) }
            $dims[$d] = [pscustomobject] $m
        }
        $turnos[$tur] = [ordered]@{ total = @($ag.total[0], $ag.total[1]); dims = [pscustomobject] $dims }
        $txtT = $(if ($tur -ne "0") { " $($tur)o turno" } else { "" })
        if ($tipoS -eq "eleitorado") { Anotar ("eleitorado {0}{1}: {2:N0} eleitores; cor/raca: {3}" -f $anoS, $txtT, $ag.total[0], $(if ($ag.dims.ContainsKey("raca")) { "sim" } else { "nao vem no arquivo" })) "Green" }
        else { Anotar ("comparecimento {0}{1}: {2:N0} aptos, {3:N0} compareceram ({4:N1}%)" -f $anoS, $txtT, $ag.total[0], $ag.total[1], $(if ($ag.total[0]) { 100.0 * $ag.total[1] / $ag.total[0] } else { 0 })) "Green" }
    }
    $saida[$tipoS] = [ordered]@{ ano = $anoS; turnos = [pscustomobject] $turnos }
}
$destino = Join-Path $Raiz "web\perfil-eleitor.js"
$json = $saida | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText($destino, "window.GCTSE_PERFIL = $json;", (New-Object System.Text.UTF8Encoding($false)))
Sair "gravado web\perfil-eleitor.js. No gerenciador (aba JORNALISMO), clique de novo nas telas 'Perfil do eleitorado' e 'Quem foi as urnas'." 0
