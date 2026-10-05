<#
    gctse GRAFICOS - IMPORTAR EVOLUCAO: monta o grafico "Evolucao minuto a
    minuto" com o que o SISTEMA DAS TARJAS gravou no log durante a apuracao.

    O TSE so publica o boletim mais recente, nao o historico. Mas o gctse das
    tarjas escreve no log, a cada mudanca, a linha que foi para o ar:
        18:42:10 OK    NO ARQUIVO  PRESIDENTE BRASIL  urnas 37,52%  |  1o FULANO 48,12%  |  2o BELTRANO 45,30%
    Esses numeros sao os do TSE naquele momento. Este programa le essas
    linhas (so PRESIDENTE + BRASIL) e grava os pontos no historico da
    evolucao (evolucao-<ciclo>-<eleicao>-oficial.json). Nada e inventado nem
    interpolado: um ponto por linha do log.

    Uso: copie logs\gctse-AAAA-MM-DD.log do computador das tarjas (o do dia
    da eleicao e, se passou da meia-noite, o do dia seguinte) e arraste os
    arquivos (ou a pasta logs inteira) sobre IMPORTAR-EVOLUCAO.bat. Sem
    arrastar nada, procura na pasta "importar" ao lado deste arquivo.
    Pode rodar com o GRAFICOS.bat aberto: ele recarrega sozinho.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $Dia = "",
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $Caminhos = @()
)
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz

function Sair([string] $Msg, [int] $Codigo) {
    if ($Codigo -ne 0) { Write-Host $Msg -ForegroundColor Red } else { Write-Host $Msg -ForegroundColor Green }
    exit $Codigo
}
# Nome sem acento, maiusculo e com espacos simples (a tarja pode ter o nome
# cortado ou sem acento; o dados.js tem o nome de urna do TSE).
function Normalizar([string] $Texto) {
    $d = "$Texto".Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void] $sb.Append($ch) }
    }
    return (($sb.ToString().ToUpperInvariant()) -replace '[^A-Z0-9 ]', ' ' -replace '\s+', ' ').Trim()
}
function Numero-Br([string] $Texto) {
    $t = "$Texto".Trim().TrimEnd('%').Replace(".", "").Replace(",", ".")
    $v = 0.0
    if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref] $v)) { return $v }
    return $null
}

# ------------------------------------------------ config e candidatos (dados.js)
if (-not (Test-Path "config-graficos.json")) { Sair "config-graficos.json nao encontrado nesta pasta." 1 }
$cfg = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Ciclo = "$($cfg.tse.ciclo)"; $Eleicao = "$($cfg.tse.eleicao_presidente)"
$arqDados = Join-Path $Raiz "web\dados.js"
if (-not (Test-Path $arqDados)) { Sair "web\dados.js nao existe: abra o GRAFICOS.bat uma vez (ele le o resultado do TSE) e rode de novo." 1 }
$txt = [IO.File]::ReadAllText($arqDados, [Text.Encoding]::UTF8)
$d = $txt.Substring($txt.IndexOf("{"), $txt.LastIndexOf("}") - $txt.IndexOf("{") + 1) | ConvertFrom-Json
if (-not $d.br -or -not $d.br.tem) { Sair "web\dados.js ainda sem o boletim do Brasil: deixe o GRAFICOS.bat rodar ate aparecer 'Brasil: urnas ...' e rode de novo." 1 }
$cands = @($d.br.candidatos); if ($cands.Count -eq 1 -and $cands[0].PSObject.Properties["value"]) { $cands = @($cands[0].value) }
$porNome = @{}
foreach ($c in $cands) { if ($c.numero) { $porNome[(Normalizar $c.nome)] = $c } }

# Dia da eleicao: o do boletim do TSE (dd/MM/yyyy), ou -Dia AAAA-MM-DD.
$diaEleicao = $null
if ($Dia) { $diaEleicao = [datetime]::ParseExact($Dia, "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture) }
else {
    $m = [regex]::Match("$($d.br.geracao)", '(\d\d)/(\d\d)/(\d{4})')
    if ($m.Success) { $diaEleicao = Get-Date -Year ([int] $m.Groups[3].Value) -Month ([int] $m.Groups[2].Value) -Day ([int] $m.Groups[1].Value) -Hour 0 -Minute 0 -Second 0 -Millisecond 0 }
}
if ($null -eq $diaEleicao) { Sair "nao sei o dia da eleicao: rode com -Dia AAAA-MM-DD" 1 }
# Apuracao comeca as 17h (Brasilia); vai ate a manha seguinte.
$janelaIni = $diaEleicao.Date.AddHours(16).AddMinutes(30); $janelaFim = $diaEleicao.Date.AddDays(1).AddHours(8)

# --------------------------------------------------------------- arquivos de log
if ($null -eq $Caminhos -or $Caminhos.Count -eq 0) { $Caminhos = @((Join-Path $Raiz "importar"), $Raiz) }
$arquivos = @()
foreach ($c in $Caminhos) {
    if (-not $c) { continue }
    if (Test-Path -LiteralPath $c -PathType Container) { $arquivos += @(Get-ChildItem -LiteralPath $c -Filter "gctse-*.log" -File -ErrorAction SilentlyContinue) }
    elseif (Test-Path -LiteralPath $c -PathType Leaf) { $arquivos += @(Get-Item -LiteralPath $c) }
}
$arquivos = @($arquivos | Sort-Object FullName -Unique)
$arquivos = @($arquivos | Where-Object {
    $m = [regex]::Match($_.Name, 'gctse-(\d{4}-\d\d-\d\d)\.log$')
    if (-not $m.Success) { return $false }
    $dt = [datetime]::ParseExact($m.Groups[1].Value, "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture)
    return ($dt -eq $diaEleicao.Date -or $dt -eq $diaEleicao.Date.AddDays(1))
})
if ($arquivos.Count -eq 0) {
    Sair ("nenhum log das tarjas do dia {0} (gctse-{1}.log). Copie da pasta logs do computador das tarjas e arraste sobre o IMPORTAR-EVOLUCAO.bat." -f $diaEleicao.ToString("dd/MM/yyyy"), $diaEleicao.ToString("yyyy-MM-dd")) 1
}

$re = '^(\d\d:\d\d:\d\d)\s+\S+\s+NO ARQUIVO\s+(.+?)\s+urnas\s+([\d.,]+)%?\s*\|\s*(.+)$'
$reCand = '^\s*\d+o\s+(.+?)\s+([\d.,]+)%(.*)$'
$pontos = New-Object System.Collections.ArrayList
$semCandidato = @{}
$linhasLidas = 0
foreach ($a in $arquivos) {
    $dtArq = [datetime]::ParseExact(([regex]::Match($a.Name, '(\d{4}-\d\d-\d\d)').Value), "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture)
    Write-Host ("lendo {0}" -f $a.FullName)
    foreach ($linha in [IO.File]::ReadAllLines($a.FullName, [Text.Encoding]::UTF8)) {
        $m = [regex]::Match($linha, $re)
        if (-not $m.Success) { continue }
        $onde = Normalizar $m.Groups[2].Value
        if (-not ($onde -match '^PRESIDENTE\b' -and $onde -match '\bBRASIL$')) { continue }
        $linhasLidas++
        $hora = [datetime]::ParseExact($m.Groups[1].Value, "HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
        $quando = $dtArq.Date.Add($hora.TimeOfDay)
        if ($quando -lt $janelaIni -or $quando -ge $janelaFim) { continue }
        $u = Numero-Br $m.Groups[3].Value
        if ($null -eq $u -or $u -le 0) { continue }
        $porCand = [ordered]@{}
        foreach ($parte in ($m.Groups[4].Value -split '\s+\|\s+')) {
            $mc = [regex]::Match($parte, $reCand)
            if (-not $mc.Success) { continue }
            $nome = Normalizar $mc.Groups[1].Value
            $alvo = $null
            if ($porNome.ContainsKey($nome)) { $alvo = $porNome[$nome] }
            else {
                # nome cortado na tarja: o unico candidato cujo nome comeca igual
                $parecidos = @($porNome.Keys | Where-Object { $_.StartsWith($nome) -or $nome.StartsWith($_) })
                if ($parecidos.Count -eq 1) { $alvo = $porNome[$parecidos[0]] }
            }
            if ($null -eq $alvo) { $semCandidato[$mc.Groups[1].Value] = $true; continue }
            $porCand["$($alvo.numero)"] = Numero-Br $mc.Groups[2].Value
        }
        if ($porCand.Count -lt 2) { continue }
        [void] $pontos.Add([pscustomobject]@{ t = $quando.ToString("yyyy-MM-ddTHH:mm:ss"); u = $u; c = [pscustomobject] $porCand })
    }
}
if ($semCandidato.Count -gt 0) {
    Write-Host ("AVISO: nomes do log que nao achei no boletim do TSE (ignorados): {0}" -f (($semCandidato.Keys) -join ", ")) -ForegroundColor Yellow
}
# Ordem do tempo; urnas nunca voltam (copia velha); repeticao seguida sai.
$ordenados = @($pontos | Sort-Object t)
$limpos = New-Object System.Collections.ArrayList
foreach ($p in $ordenados) {
    if ($limpos.Count -gt 0) {
        $ant = $limpos[$limpos.Count - 1]
        if ($p.t -eq $ant.t) { $limpos[$limpos.Count - 1] = $p; continue }
        if ($p.u -lt $ant.u) { continue }
        if ($p.u -eq $ant.u -and (($p.c | ConvertTo-Json -Compress) -eq ($ant.c | ConvertTo-Json -Compress))) { continue }
    }
    [void] $limpos.Add($p)
}
if ($limpos.Count -eq 0) {
    Sair ("{0} linha(s) PRESIDENTE BRASIL no log, nenhuma entre {1} e {2} com 2 candidatos. Nada importado." -f $linhasLidas, $janelaIni.ToString("dd/MM HH:mm"), $janelaFim.ToString("dd/MM HH:mm")) 1
}

# ------------------------------------------- junta com o historico que ja existe
$arqEv = Join-Path $Raiz ("evolucao-{0}-{1}-oficial.json" -f $Ciclo, $Eleicao)
$existentes = @(); $nomes = [ordered]@{}
if (Test-Path $arqEv) {
    try {
        $lido = Get-Content $arqEv -Raw -Encoding UTF8 | ConvertFrom-Json
        $existentes = @($lido.pontos | Where-Object { $null -ne $_ })
        # PowerShell 7 transforma "2026-10-04T18:00:00" em data: volta a texto.
        foreach ($pt in $existentes) { if ($pt.t -is [datetime]) { $pt.t = $pt.t.ToString("yyyy-MM-ddTHH:mm:ss") } }
        if ($lido.PSObject.Properties["nomes"]) { foreach ($pn in $lido.nomes.PSObject.Properties) { $nomes[$pn.Name] = $pn.Value } }
        Copy-Item $arqEv "$arqEv.antes-da-importacao" -Force
    } catch { }
}
foreach ($c in $cands) { if ($c.numero -and $c.votos -gt 0) { $nomes["$($c.numero)"] = [pscustomobject]@{ nome = $c.nome; partido = $c.partido } } }
# O log manda em tudo ate o seu ultimo ponto (nao mistura o relogio do
# computador das tarjas com a hora do TSE); do GRAFICOS.bat fica so o depois.
$fim = $limpos[$limpos.Count - 1].t
$final = @($limpos) + @($existentes | Where-Object { "$($_.t)" -gt $fim })
$final = @($final | Sort-Object { "$($_.t)" })
$obj = [ordered]@{
    ciclo = $Ciclo; eleicao = $Eleicao; modo = "OFICIAL"
    origem = "log das tarjas"
    nomes = [pscustomobject] $nomes; pontos = $final
}
$tmp = "$arqEv.tmp"
[IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 6 -Compress), (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $tmp -Destination $arqEv -Force

$p0 = $limpos[0]; $pf = $limpos[$limpos.Count - 1]
Write-Host ""
Write-Host ("importados {0} pontos de {1} a {2} (urnas {3}% a {4}%)" -f $limpos.Count, $p0.t.Substring(11, 5), $pf.t.Substring(11, 5), $p0.u, $pf.u)
foreach ($k in $pf.c.PSObject.Properties) { Write-Host ("   ultimo ponto: {0,-28} {1}%" -f $nomes[$k.Name].nome, $k.Value) }
Sair ("gravado em {0}. Com o GRAFICOS.bat aberto, a tela atualiza em ate 20 s." -f (Split-Path -Leaf $arqEv)) 0
