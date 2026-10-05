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

# Tudo o que aparece na janela vai tambem para IMPORTAR-EVOLUCAO.txt (para
# mandar ao suporte se nao der certo).
$script:Diag = New-Object System.Collections.Generic.List[string]
function Anotar([string] $Texto, [string] $Cor = "Gray") { Write-Host $Texto -ForegroundColor $Cor; $script:Diag.Add($Texto) }
function Sair([string] $Msg, [int] $Codigo) {
    if ($Codigo -ne 0) { Anotar $Msg "Red" } else { Anotar $Msg "Green" }
    if ($Codigo -ne 0) { Write-Host ""; Write-Host "Mande a foto desta janela (ou o arquivo IMPORTAR-EVOLUCAO.txt desta pasta) para o suporte." -ForegroundColor Yellow }
    try { [IO.File]::WriteAllLines((Join-Path $Raiz "IMPORTAR-EVOLUCAO.txt"), $script:Diag, (New-Object System.Text.UTF8Encoding($true))) } catch { }
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

function Numero-Ponto([string] $Texto) {
    $v = 0.0
    if ([double]::TryParse("$Texto".Trim().TrimEnd('%'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref] $v)) { return $v }
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
    $m = [regex]::Match("$($d.br.geracao)", '(\d\d)/(\d\d)/(\d{4})\s*(\d\d)?')
    if ($m.Success) {
        $diaEleicao = Get-Date -Year ([int] $m.Groups[3].Value) -Month ([int] $m.Groups[2].Value) -Day ([int] $m.Groups[1].Value) -Hour 0 -Minute 0 -Second 0 -Millisecond 0
        # Boletim final gerado de madrugada (ex.: 05/10 02:59) e da eleicao
        # do dia anterior: a apuracao comeca as 17h.
        if ($m.Groups[4].Success -and [int] $m.Groups[4].Value -lt 12) { $diaEleicao = $diaEleicao.AddDays(-1) }
    }
}
if ($null -eq $diaEleicao) { Sair "nao sei o dia da eleicao: rode com -Dia AAAA-MM-DD" 1 }
# Apuracao comeca as 17h (Brasilia); vai ate a manha seguinte.
$janelaIni = $diaEleicao.Date.AddHours(16).AddMinutes(30); $janelaFim = $diaEleicao.Date.AddDays(1).AddHours(8)

# --------------------------------------------------------------- arquivos de log
# Arrastado sobre o .bat: aceita qualquer nome (copia de WhatsApp vira
# "gctse-2026-10-04 (1).log", o Windows esconde ".txt" etc.). Sem arrastar:
# procura log do gctse na pasta importar, nesta pasta, nas pastas "logs"
# vizinhas (gctse no mesmo computador), na Area de Trabalho e em Downloads.
$explicitos = ($null -ne $Caminhos -and @($Caminhos | Where-Object { $_ }).Count -gt 0)
$ondeProcurar = New-Object System.Collections.ArrayList
if ($explicitos) { foreach ($c in $Caminhos) { if ($c) { [void] $ondeProcurar.Add(@{ p = "$c".Trim('"'); fundo = $true }) } } }
else {
    [void] $ondeProcurar.Add(@{ p = (Join-Path $Raiz "importar"); fundo = $true })
    [void] $ondeProcurar.Add(@{ p = $Raiz; fundo = $false })
    [void] $ondeProcurar.Add(@{ p = (Join-Path $Raiz "logs"); fundo = $false })
    $pai = Split-Path -Parent $Raiz
    if ($pai) {
        foreach ($viz in @(Get-ChildItem -LiteralPath $pai -Directory -ErrorAction SilentlyContinue)) {
            [void] $ondeProcurar.Add(@{ p = (Join-Path $viz.FullName "logs"); fundo = $false })
        }
    }
    $pessoais = @()
    try { $pessoais += [Environment]::GetFolderPath("Desktop") } catch { }
    if ($env:USERPROFILE) { $pessoais += @((Join-Path $env:USERPROFILE "Desktop"), (Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "OneDrive\Desktop")) }
    foreach ($pp in ($pessoais | Where-Object { $_ } | Select-Object -Unique)) { [void] $ondeProcurar.Add(@{ p = $pp; fundo = $true }) }
}
$vistos = New-Object System.Collections.ArrayList     # para o diagnostico
# Duas fontes: gctse-*.log (TARJAS: 1o e 2o a cada mudanca) e graficos-*.log
# (este EXIBIDOR: so o 1o colocado a cada ciclo). Arrastado com outro nome
# conta como log das tarjas.
$arquivos = @(); $arquivosExib = @()
foreach ($o in $ondeProcurar) {
    if (Test-Path -LiteralPath $o.p -PathType Leaf) {
        $it = Get-Item -LiteralPath $o.p
        if ($it.Name -match '(?i)^graficos') { $arquivosExib += @($it) } else { $arquivos += @($it) }
        continue
    }
    if (-not (Test-Path -LiteralPath $o.p -PathType Container)) { continue }
    $achados = @()
    if ($o.fundo) { $achados = @(Get-ChildItem -LiteralPath $o.p -File -Recurse -Depth 2 -ErrorAction SilentlyContinue) }
    else { $achados = @(Get-ChildItem -LiteralPath $o.p -File -ErrorAction SilentlyContinue) }
    $arquivos += @($achados | Where-Object { $_.Name -match '(?i)^gctse.*\.(log|txt)$' })
    $arquivosExib += @($achados | Where-Object { $_.Name -match '(?i)^graficos.*\.(log|txt)$' })
}
# Dia pelo nome (AAAA-MM-DD); so o dia da eleicao e o seguinte. Sem data
# no nome, a hora decide (ver Quando-Foi).
function Filtrar-Dia($Lista) {
    $saida = @()
    foreach ($a in @($Lista | Sort-Object FullName -Unique)) {
        $m = [regex]::Match($a.Name, '(\d{4})-(\d\d)-(\d\d)')
        $dtA = $null
        if ($m.Success) {
            $dtA = Get-Date -Year ([int] $m.Groups[1].Value) -Month ([int] $m.Groups[2].Value) -Day ([int] $m.Groups[3].Value) -Hour 0 -Minute 0 -Second 0 -Millisecond 0
            if ($dtA.Date -ne $diaEleicao.Date -and $dtA.Date -ne $diaEleicao.Date.AddDays(1)) {
                [void] $vistos.Add(("   {0}  (outro dia - ignorado)" -f $a.FullName)); continue
            }
        }
        $saida += [pscustomobject]@{ Arquivo = $a; Dia = $dtA }
    }
    return $saida
}
function Quando-Foi($DiaArq, [string] $HoraTxt) {
    $h = [datetime]::ParseExact($HoraTxt, "HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
    if ($null -ne $DiaArq) { return $DiaArq.Date.Add($h.TimeOfDay) }
    if ($h.Hour -ge 12) { return $diaEleicao.Date.Add($h.TimeOfDay) }        # tarde/noite: dia da eleicao
    return $diaEleicao.Date.AddDays(1).Add($h.TimeOfDay)                     # madrugada: dia seguinte
}
$usar = @(Filtrar-Dia $arquivos)
$usarExib = @(Filtrar-Dia $arquivosExib)
if ($usar.Count -eq 0 -and $usarExib.Count -eq 0) {
    Anotar "Procurei em:" "Yellow"
    foreach ($o in $ondeProcurar) { Anotar ("   {0}{1}" -f $o.p, $(if (Test-Path -LiteralPath $o.p) { "" } else { "  (nao existe)" })) }
    if ($vistos.Count -gt 0) { Anotar "Logs encontrados:" "Yellow"; foreach ($v in $vistos) { Anotar $v } }
    if ($explicitos) { Anotar ("Recebi do arrastar: {0}" -f (($Caminhos | Where-Object { $_ }) -join " ; ")) "Yellow" }
    Sair ("nenhum log do dia {0}: nem das tarjas (gctse-{1}.log) nem deste exibidor (logs\graficos-{1}.log)." -f $diaEleicao.ToString("dd/MM/yyyy"), $diaEleicao.ToString("yyyy-MM-dd")) 1
}

# Nome do log -> candidato do boletim do TSE (sem acento; cortado; abreviado).
function Achar-Candidato([string] $NomeBruto) {
    $nome = Normalizar $NomeBruto
    if ($porNome.ContainsKey($nome)) { return $porNome[$nome] }
    $parecidos = @($porNome.Keys | Where-Object { $_.StartsWith($nome) -or $nome.StartsWith($_) })
    if ($parecidos.Count -eq 1) { return $porNome[$parecidos[0]] }
    # abreviado ("F. BOLSONARO"): o unico com uma palavra de 4+ letras igual
    $palavras = @($nome.Split(' ') | Where-Object { $_.Length -ge 4 })
    $porPalavra = @($porNome.Keys | Where-Object { $ks = @($_.Split(' ')); @($palavras | Where-Object { $ks -contains $_ }).Count -gt 0 })
    if ($porPalavra.Count -eq 1) { return $porNome[$porPalavra[0]] }
    return $null
}
# Ordem do tempo; urnas nunca voltam (copia velha); repeticao seguida sai.
function Limpar($Lista) {
    $res = New-Object System.Collections.ArrayList
    foreach ($p in @($Lista | Sort-Object t)) {
        if ($res.Count -gt 0) {
            $ant = $res[$res.Count - 1]
            if ($p.t -eq $ant.t) { $res[$res.Count - 1] = $p; continue }
            if ($p.u -lt $ant.u) { continue }
            if ($p.u -eq $ant.u -and (($p.c | ConvertTo-Json -Compress) -eq ($ant.c | ConvertTo-Json -Compress))) { continue }
        }
        [void] $res.Add($p)
    }
    return ,$res
}

$re = '^\W{0,3}(\d\d:\d\d:\d\d)\s+\S+\s+NO ARQUIVO\s+(.+?)\s+urnas\s+([\d.,]+)\s*%?\s*\|\s*(.+)$'
$reCand = '^\s*\d+o\s+(.+?)\s+([\d.,]+)%(.*)$'
$pontos = New-Object System.Collections.ArrayList
$semCandidato = @{}
$linhasLidas = 0
$motivos = [ordered]@{ "fora do horario da apuracao" = 0; "urnas 0%" = 0; "menos de 2 candidatos reconhecidos" = 0 }
foreach ($u0 in $usar) {
    $a = $u0.Arquivo; $dtArq = $u0.Dia; $nesteArquivo = 0
    $todas = [IO.File]::ReadAllLines($a.FullName, [Text.Encoding]::UTF8)
    $locais = [ordered]@{}; $amostraNoArq = @(); $amostraPres = @(); $nNoArq = 0
    Anotar ("lendo {0}  ({1} linhas, {2:dd/MM/yyyy HH:mm})" -f $a.FullName, $todas.Count, $a.LastWriteTime)
    foreach ($linha in $todas) {
        if ($linha -match 'NO ARQUIVO') { $nNoArq++; if ($amostraNoArq.Count -lt 3) { $amostraNoArq += $linha } }
        elseif ($linha -match '(?i)presidente' -and $amostraPres.Count -lt 3) { $amostraPres += $linha }
        $m = [regex]::Match($linha, $re)
        if (-not $m.Success) { continue }
        $onde = Normalizar $m.Groups[2].Value
        if ($locais.Contains($onde)) { $locais[$onde] = $locais[$onde] + 1 } else { $locais[$onde] = 1 }
        # PRESIDENTE (ou PRESIDENTE DA REPUBLICA) + BRASIL/BR/NACIONAL (ou nada)
        if (-not ($onde -match '^PRESIDENTE\b')) { continue }
        $resto = ($onde -replace '^PRESIDENTE( DA REPUBLICA)?', '').Trim()
        if (-not ($resto -eq "" -or $resto -match '\bBRASIL\b' -or $resto -eq "BR" -or $resto -eq "NACIONAL")) { continue }
        $linhasLidas++; $nesteArquivo++
        $quando = Quando-Foi $dtArq $m.Groups[1].Value
        if ($quando -lt $janelaIni -or $quando -ge $janelaFim) { $motivos["fora do horario da apuracao"]++; continue }
        $u = Numero-Br $m.Groups[3].Value
        if ($null -eq $u -or $u -le 0) { $motivos["urnas 0%"]++; continue }
        $porCand = [ordered]@{}
        foreach ($parte in ($m.Groups[4].Value -split '\s+\|\s+')) {
            $mc = [regex]::Match($parte, $reCand)
            if (-not $mc.Success) { continue }
            $alvo = Achar-Candidato $mc.Groups[1].Value
            if ($null -eq $alvo) { $semCandidato[$mc.Groups[1].Value] = $true; continue }
            $porCand["$($alvo.numero)"] = Numero-Br $mc.Groups[2].Value
        }
        if ($porCand.Count -lt 2) { $motivos["menos de 2 candidatos reconhecidos"]++; continue }
        [void] $pontos.Add([pscustomobject]@{ t = $quando.ToString("yyyy-MM-ddTHH:mm:ss"); u = $u; c = [pscustomobject] $porCand })
    }
    Anotar ("   {0} linha(s) 'NO ARQUIVO'; {1} de PRESIDENTE BRASIL" -f $nNoArq, $nesteArquivo)
    if ($nesteArquivo -eq 0) {
        foreach ($k in $locais.Keys) { Anotar ("      tarja no log: {0} ({1}x)" -f $k, $locais[$k]) }
        foreach ($l in $amostraNoArq) { Anotar ("      ex.: {0}" -f $l) }
        if ($nNoArq -eq 0) { foreach ($l in $amostraPres) { Anotar ("      linha com PRESIDENTE: {0}" -f $l) } }
    }
}
foreach ($k in $motivos.Keys) { if ($motivos[$k] -gt 0) { Anotar ("   ignoradas: {0} - {1}" -f $motivos[$k], $k) } }
Anotar ("   candidatos no boletim do TSE: {0}" -f (($cands | Where-Object { $_.votos -gt 0 } | Select-Object -First 4 | ForEach-Object { $_.nome }) -join ", "))
if ($semCandidato.Count -gt 0) {
    Anotar ("AVISO: nomes do log que nao achei no boletim do TSE (ignorados): {0}" -f (($semCandidato.Keys) -join ", ")) "Yellow"
}
$limpos = Limpar $pontos
$origem = "log das tarjas"
if ($limpos.Count -eq 0 -and $usar.Count -gt 0) {
    Anotar ("log das tarjas: {0} linha(s) PRESIDENTE BRASIL, nenhuma entre {1} e {2} com 2 candidatos." -f $linhasLidas, $janelaIni.ToString("dd/MM HH:mm"), $janelaFim.ToString("dd/MM HH:mm")) "Yellow"
}
# Plano B: o log deste EXIBIDOR (GRAFICOS.bat) - a cada ciclo de 20 s:
#   "18:42:10 INFO  Brasil: urnas 37.52% | 1o FULANO 48.12% | estados com boletim ..."
# So tem o 1o colocado: a linha do 2o fica so com o resultado final.
if ($limpos.Count -eq 0 -and $usarExib.Count -gt 0) {
    Anotar "sem log das tarjas: uso o log deste exibidor (so o 1o colocado a cada ciclo)." "Yellow"
    $reExib = '^\W{0,3}(\d\d:\d\d:\d\d)\s+\S+\s+Brasil: urnas ([\d.,]+)%\s*\|\s*1o (.+?) ([\d.,]+)%'
    $pontosExib = New-Object System.Collections.ArrayList
    foreach ($u0 in $usarExib) {
        $a = $u0.Arquivo; $nesteArquivo = 0
        $todas = [IO.File]::ReadAllLines($a.FullName, [Text.Encoding]::UTF8)
        Anotar ("lendo {0}  ({1} linhas)" -f $a.FullName, $todas.Count)
        foreach ($linha in $todas) {
            $m = [regex]::Match($linha, $reExib)
            if (-not $m.Success) { continue }
            $quando = Quando-Foi $u0.Dia $m.Groups[1].Value
            if ($quando -lt $janelaIni -or $quando -ge $janelaFim) { continue }
            $u = Numero-Ponto $m.Groups[2].Value
            if ($null -eq $u -or $u -le 0) { continue }
            $alvo = Achar-Candidato $m.Groups[3].Value
            if ($null -eq $alvo) { $semCandidato[$m.Groups[3].Value] = $true; continue }
            $nesteArquivo++
            [void] $pontosExib.Add([pscustomobject]@{ t = $quando.ToString("yyyy-MM-ddTHH:mm:ss"); u = $u; c = [pscustomobject]@{ "$($alvo.numero)" = (Numero-Ponto $m.Groups[4].Value) } })
        }
        Anotar ("   {0} ciclo(s) com o 1o colocado" -f $nesteArquivo)
    }
    $limpos = Limpar $pontosExib
    $origem = "log do exibidor"
    # Fecha com o boletim atual do TSE (dados.js), que tem os dois: e o unico
    # ponto do 2o colocado. Hora = a do TSE, ou logo depois do ultimo ciclo.
    if ($limpos.Count -gt 0) {
        $fimTse = @{}
        foreach ($c in @($cands | Where-Object { $_.votos -gt 0 } | Select-Object -First 2)) { $fimTse["$($c.numero)"] = [double] $c.pct }
        $ultT = [datetime]::ParseExact($limpos[$limpos.Count - 1].t, "yyyy-MM-ddTHH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
        $tTse = $null
        try { $tTse = [datetime]::ParseExact("$($d.br.geracao)".Trim(), "dd/MM/yyyy HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture) } catch { }
        $tFim = $ultT.AddSeconds(1)
        if ($null -ne $tTse -and $tTse -gt $tFim) { $tFim = $tTse }
        $uFim = [double] $d.br.secoes.pct
        if ($fimTse.Count -eq 2 -and $uFim -ge $limpos[$limpos.Count - 1].u) {
            $ordFim = [ordered]@{}; foreach ($k in $fimTse.Keys) { $ordFim[$k] = $fimTse[$k] }
            [void] $limpos.Add([pscustomobject]@{ t = $tFim.ToString("yyyy-MM-ddTHH:mm:ss"); u = $uFim; c = [pscustomobject] $ordFim })
            Anotar ("   + resultado do TSE ({0}): os dois candidatos" -f "$($d.br.geracao)")
        }
    }
}
if ($limpos.Count -eq 0) {
    Sair ("nada importado: nenhum registro de Presidente Brasil entre {0} e {1}." -f $janelaIni.ToString("dd/MM HH:mm"), $janelaFim.ToString("dd/MM HH:mm")) 1
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
# computador do log com a hora do TSE); do GRAFICOS.bat fica so o depois
# (o resultado final, com os dois candidatos).
$fim = $limpos[$limpos.Count - 1].t
$final = @($limpos) + @($existentes | Where-Object { "$($_.t)" -gt $fim })
$final = @($final | Sort-Object { "$($_.t)" })
$obj = [ordered]@{
    ciclo = $Ciclo; eleicao = $Eleicao; modo = "OFICIAL"
    origem = $origem
    nomes = [pscustomobject] $nomes; pontos = $final
}
$tmp = "$arqEv.tmp"
[IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 6 -Compress), (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $tmp -Destination $arqEv -Force

$p0 = $limpos[0]; $pf = $limpos[$limpos.Count - 1]
Write-Host ""
Anotar ("importados {0} pontos de {1} a {2} (urnas {3}% a {4}%)" -f $limpos.Count, $p0.t.Substring(11, 5), $pf.t.Substring(11, 5), $p0.u, $pf.u)
foreach ($k in $pf.c.PSObject.Properties) { Anotar ("   ultimo ponto: {0,-28} {1}%" -f $nomes[$k.Name].nome, $k.Value) }
Anotar ("gravado em {0}." -f (Split-Path -Leaf $arqEv))
# A tela recebeu? Quem poe a linha na tela e o GRAFICOS.bat (dados.js). Um
# GRAFICOS.bat aberto ANTES de atualizar para a 3.0 continua na versao velha,
# que nao rele o historico: a tela fica com 1 ponto.
$idade = ((Get-Date) - (Get-Item $arqDados).LastWriteTime).TotalSeconds
$aberto = $false
try { if ($d.PSObject.Properties["pid"] -and $d.pid) { $aberto = ($null -ne (Get-Process -Id ([int] $d.pid) -ErrorAction SilentlyContinue)) } } catch { }
if ($idade -gt 120 -or -not $aberto) {
    Sair "O GRAFICOS.bat NAO esta aberto: abra-o agora. A linha aparece na tela no primeiro ciclo (uns 20 s)." 0
}
Anotar "conferindo se a tela recebeu a linha (ate 60 s)..."
$recebeu = $false
for ($i = 0; $i -lt 30 -and -not $recebeu; $i++) {
    Start-Sleep -Seconds 2
    try { $recebeu = ([IO.File]::ReadAllText($arqDados, [Text.Encoding]::UTF8) -match ('"origem":"' + $origem + '"')) } catch { }
}
if ($recebeu) { Sair "PRONTO: a tela ja esta com a linha. (Na tela aberta, se precisar, aperte F5.)" 0 }
$versaoCol = "$($d.versao)"
Sair ("O GRAFICOS.bat aberto e da versao {0} e nao recarregou o historico. FECHE a janela do GRAFICOS.bat e abra de novo: a linha aparece no primeiro ciclo. (O historico importado ja esta salvo.)" -f $versaoCol) 1
