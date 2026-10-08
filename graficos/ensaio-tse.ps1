<#
    gctse GRAFICOS - TSE SIMULADO PARA ENSAIO (so para treino; NAO e dado real)

    Servidor local (http://localhost:8799/) que responde no MESMO formato do
    site de resultados do TSE, com uma noite de 2o turno em tempo acelerado:
      - 1o turno (codigos 9257/9259): resultado final ficticio
      - 2o turno (9262 Presidente, 9263 Governador): a apuracao anda de 0 a
        100% em -Minutos minutos (padrao 20), com virada no meio e ELEITO
        no fim; Sul e Sudeste apuram mais rapido que o Nordeste.
    Nomes ficticios ("CANDIDATO A", "GOVERNADOR B (SP)"...). Quem usa e o
    ENSAIO.bat, numa COPIA separada da pasta: as telas saem marcadas
    "ENSAIO - NAO VAI AO AR" e o gerenciador do ensaio nao fala com o OBS.
#>
param([int] $Porta = 8799, [double] $Minutos = 20)
$ErrorActionPreference = "Stop"

# eleitores aproximados (mil) - so para as proporcoes do ensaio
$ELEITORES = [ordered]@{ sp = 34600; mg = 16300; rj = 12800; ba = 11300; rs = 8600; pr = 8400; pe = 7000; ce = 6800; pa = 6000; sc = 5500
    ma = 5000; go = 4900; pb = 3100; es = 2900; am = 2700; pi = 2600; rn = 2600; mt = 2500; al = 2300; df = 2200; ms = 2000
    se = 1700; ro = 1200; to = 1100; ac = 600; ap = 550; rr = 370 }
$NE = @("al", "ba", "ce", "ma", "pb", "pe", "pi", "rn", "se")
$RAPIDOS = @("sp", "mg", "rj", "es", "pr", "rs", "sc", "df", "go")
$SEG2 = @("ac", "am", "df", "es", "go", "pb", "pe", "rj", "rs", "sp")
$VAGAS = @{ sp = 70; mg = 53; rj = 46; ba = 39; rs = 31; pr = 30; pe = 25; ce = 22; ma = 18; go = 17; pa = 17; sc = 16; pb = 12; es = 10; pi = 10; al = 9 }
$PARTIDOS = @("PL", "PT", "MDB", "PSD", "UNIAO", "PP", "REPUBLICANOS", "PSB", "PDT", "PSDB", "PODE")
$Inicio = Get-Date

function Rnd([string] $chave) {   # 0..1 fixo por chave (o ensaio e sempre igual)
    $h = 17; foreach ($ch in $chave.ToCharArray()) { $h = ($h * 31 + [int] $ch) % 1000003 }
    return (($h * 7919) % 10007) / 10007.0
}
function Br([double] $v) { return $v.ToString("0.00", [Globalization.CultureInfo]::InvariantCulture).Replace(".", ",") }
function Cand($n, $sq, $nome, $sg, $votos, $pct, $st, $e) {
    return [ordered]@{ sg = $sg; cand = @([ordered]@{ n = "$n"; sqcand = "$sq"; nm = $nome; nmu = $nome; e = $e; st = $st; dvt = "Valido"; vap = "$([long] $votos)"; pvap = (Br $pct) }) }
}
function Boletim($cd, $nv, $cands, [double] $pst, $and, [long] $te, $dg, $hg) {
    $vv = 0; foreach ($c in $cands) { $vv += [long] $c.cand[0].vap }
    $est = [long] ($te * $pst / 100); $comp = [long] ($est * 0.79)
    return [ordered]@{ f = "O"; and = $and; dg = $dg; hg = $hg
        s = [ordered]@{ ts = "1000"; st = "$([int] (10 * $pst))"; pst = (Br $pst) }
        e = [ordered]@{ te = "$te"; est = "$est"; esnt = "$($te - $est)"; c = "$comp"; pc = "79,00"; a = "$($est - $comp)"; pa = "21,00" }
        v = [ordered]@{ vv = "$vv"; pvv = "93,00"; vb = "$([long] ($vv * 0.02))"; pvb = "2,00"; tvn = "$([long] ($vv * 0.05))"; ptvn = "5,00" }
        carg = @([ordered]@{ cd = "$cd"; nv = "$nv"; agr = @([ordered]@{ par = $cands }) }) }
}
function Progresso([string] $uf) {   # 0..1 de quanto a apuracao do estado andou
    $f = ((Get-Date) - $Inicio).TotalMinutes / $Minutos   # sem teto: o estado lento chega a 100% um pouco depois
    $vel = $(if ($RAPIDOS -contains $uf) { 1.35 } elseif ($NE -contains $uf) { 0.95 } else { 1.1 }) + 0.2 * (Rnd "v$uf")
    return [math]::Min(1.0, $f * $vel)
}
function Relogio([double] $f) { $m = 17 * 60 + [int] ($f * 300); return "{0:00}:{1:00}:{2:00}" -f [int][math]::Floor($m / 60), ($m % 60), [int] (59 * (Rnd "$m")) }
function FracGeral { return [math]::Min(1.0, ((Get-Date) - $Inicio).TotalMinutes / $Minutos) }

# Presidente: parcela de A (PT) entre os dois, por estado
function LulaFinal([string] $uf) { if ($NE -contains $uf) { return 0.62 + 0.08 * (Rnd "l$uf") } return 0.40 + 0.12 * (Rnd "l$uf") }
function Pres2T([string] $uf) {
    $p = Progresso $uf; $te = [long] ($ELEITORES[$uf] * 1000)
    # comeco da apuracao: B sai na frente em todo lugar e o Nordeste apura
    # mais devagar -> A vira no meio da noite (a diferenca some ate o fim)
    $a = (LulaFinal $uf) - 0.06 * (1 - $p)
    $pst = 100 * [math]::Pow($p, 0.8); $vv = $te * 0.79 * 0.93 * $pst / 100
    return @{ p = $p; pst = $pst; te = $te; va = $vv * $a; vb = $vv * (1 - $a) }
}
function RespPresidente([string] $abr, [bool] $turno2) {
    if (-not $turno2) {   # 1o turno: final
        $te = 0; $va = 0; $vb = 0; $vc = 0; $vd = 0; $ufs = $(if ($abr -eq "br") { @($ELEITORES.Keys) } else { @($abr) })
        foreach ($u in $ufs) { $t = $ELEITORES[$u] * 1000 * 0.79 * 0.93; $l = LulaFinal $u; $te += $ELEITORES[$u] * 1000
            $va += $t * ($l * 0.9); $vb += $t * ((1 - $l) * 0.9); $vc += $t * 0.06; $vd += $t * 0.04 }
        $tot = $va + $vb + $vc + $vd
        $cs = @((Cand 13 900013 "CANDIDATO A" "PT" $va (100 * $va / $tot) "Concorrente ao 2o turno" "n"), (Cand 22 900022 "CANDIDATO B" "PL" $vb (100 * $vb / $tot) "Concorrente ao 2o turno" "n"),
            (Cand 30 900030 "CANDIDATO C" "NOVO" $vc (100 * $vc / $tot) "Nao eleito" "n"), (Cand 15 900015 "CANDIDATO D" "MDB" $vd (100 * $vd / $tot) "Nao eleito" "n"))
        return Boletim 1 1 $cs 100 "f" $te "04/10/2026" "23:50:00"
    }
    $te = 0; $va = 0; $vb = 0; $est = 0; $ufs = $(if ($abr -eq "br") { @($ELEITORES.Keys) } else { @($abr) })
    foreach ($u in $ufs) { $x = Pres2T $u; $te += $x.te; $va += $x.va; $vb += $x.vb; $est += $x.te * $x.pst / 100 }
    $pst = $(if ($te) { 100 * $est / $te } else { 0 }); $fim = $pst -ge 99.99
    $tot = [math]::Max(1, $va + $vb); $pa = 100 * $va / $tot
    $stA = ""; $stB = ""; if ($fim) { if ($va -ge $vb) { $stA = "Eleito"; $stB = "Nao eleito" } else { $stB = "Eleito"; $stA = "Nao eleito" } }
    $cs = @((Cand 13 900013 "CANDIDATO A" "PT" $va $pa $stA $(if ($stA -eq "Eleito") { "s" } else { "n" })), (Cand 22 900022 "CANDIDATO B" "PL" $vb (100 - $pa) $stB $(if ($stB -eq "Eleito") { "s" } else { "n" })))
    return Boletim 1 1 $cs ([math]::Min(100, $pst)) $(if ($fim) { "f" } else { "p" }) $te "25/10/2026" (Relogio (FracGeral))
}
function Resp2022([string] $abr) {   # 2o turno de 2022 ficticio: A (PT) x B (PL)
    $ufs = $(if ($abr -eq "br") { @($ELEITORES.Keys) } else { @($abr) }); $va = 0; $vb = 0; $te = 0
    foreach ($u in $ufs) { $t = $ELEITORES[$u] * 1000 * 0.79 * 0.93; $l = (LulaFinal $u) - 0.02 + 0.04 * (Rnd "z$u"); $va += $t * $l; $vb += $t * (1 - $l); $te += $ELEITORES[$u] * 1000 }
    $tot = $va + $vb
    $cs = @((Cand 13 800013 "CANDIDATO X (2022)" "PT" $va (100 * $va / $tot) "Eleito" "s"), (Cand 22 800022 "CANDIDATO Y (2022)" "PL" $vb (100 * $vb / $tot) "Nao eleito" "n"))
    return Boletim 1 1 $cs 100 "f" ([long] $te) "30/10/2022" "20:00:00"
}
function RespGovernador([string] $uf, [bool] $turno2) {
    $te = [long] ($ELEITORES[$uf] * 1000); $sg1 = $PARTIDOS[[int] (10 * (Rnd "g1$uf"))]; $sg2 = $(if ($sg1 -eq "PT") { "PL" } else { "PT" })
    $nA = "GOVERNADOR A ($($uf.ToUpper()))"; $nB = "GOVERNADOR B ($($uf.ToUpper()))"; $sqA = 70000 + 2 * [array]::IndexOf(@($ELEITORES.Keys), $uf); $sqB = $sqA + 1
    $t = $te * 0.79 * 0.93
    if (-not $turno2) {
        if ($SEG2 -contains $uf) { $cs = @((Cand 11 $sqA $nA $sg1 ($t * 0.44) 44 "2o turno" "n"), (Cand 22 $sqB $nB $sg2 ($t * 0.38) 38 "2o turno" "n")) }
        else { $cs = @((Cand 11 $sqA $nA $sg1 ($t * 0.56) 56 "Eleito" "s"), (Cand 22 $sqB $nB $sg2 ($t * 0.30) 30 "Nao eleito" "n")) }
        return Boletim 3 1 $cs 100 "f" $te "04/10/2026" "23:50:00"
    }
    if ($SEG2 -notcontains $uf) { return $null }
    $p = Progresso $uf; $pst = 100 * [math]::Pow($p, 0.8); $a = 0.47 + 0.07 * (Rnd "g2$uf"); $vv = $t * $pst / 100; $fim = $pst -ge 99.99
    $stA = ""; $stB = ""; if ($fim) { if ($a -ge 0.5) { $stA = "Eleito"; $stB = "Nao eleito" } else { $stB = "Eleito"; $stA = "Nao eleito" } }
    $cs = @((Cand 11 $sqA $nA $sg1 ($vv * $a) (100 * $a) $stA $(if ($stA -eq "Eleito") { "s" } else { "n" })), (Cand 22 $sqB $nB $sg2 ($vv * (1 - $a)) (100 - 100 * $a) $stB $(if ($stB -eq "Eleito") { "s" } else { "n" })))
    return Boletim 3 1 $cs $pst $(if ($fim) { "f" } else { "p" }) $te "25/10/2026" (Relogio (FracGeral))
}
function RespSenador([string] $uf) {
    $te = [long] ($ELEITORES[$uf] * 1000); $t = $te * 0.79 * 0.93; $i = [array]::IndexOf(@($ELEITORES.Keys), $uf)
    $cs = @(); foreach ($j in 0, 1, 2) {
        $sg = $PARTIDOS[[int] (10 * (Rnd "s$j$uf"))]; $pc = @(34, 30, 20)[$j]
        $cs += Cand (100 + $j) (80000 + 3 * $i + $j) ("SENADOR " + "ABC"[$j] + " ($($uf.ToUpper()))") $sg ($t * $pc / 100) $pc $(if ($j -lt 2) { "Eleito" } else { "Nao eleito" }) $(if ($j -lt 2) { "s" } else { "n" })
    }
    return Boletim 5 2 $cs 100 "f" $te "04/10/2026" "23:50:00"
}
function RespDeputados([string] $uf, [int] $cargo = 6) {
    $te = [long] ($ELEITORES[$uf] * 1000); $nv = $(if ($VAGAS.ContainsKey($uf)) { $VAGAS[$uf] } else { 8 }); $i = [array]::IndexOf(@($ELEITORES.Keys), $uf)
    # estaduais: o triplo da bancada federal ate 36, depois +1 por deputado federal acima de 12
    if ($cargo -ne 6) { $nv = $(if ($nv -le 12) { 3 * $nv } else { 36 + $nv - 12 }); $i += 100 * $cargo }
    $par = @{}
    for ($j = 0; $j -lt $nv + 6; $j++) {
        $sg = $PARTIDOS[[int] (10 * (Rnd "d$j$uf"))]; $votos = [long] (300000 * [math]::Pow(0.93, $j) * (0.5 + (Rnd "dv$j$uf")))
        $st = $(if ($j -lt $nv) { if ($j % 5 -eq 4) { "Eleito por media" } else { "Eleito por QP" } } else { "Suplente" })
        if (-not $par.ContainsKey($sg)) { $par[$sg] = New-Object System.Collections.ArrayList }
        [void] $par[$sg].Add([ordered]@{ n = "$(1000 + $j)"; sqcand = "$(500000 + 1000 * $i + $j)"; nm = ("{2} {0:00} ({1})" -f ($j + 1), $uf.ToUpper(), $(if ($cargo -eq 6) { "DEPUTADO" } else { "DEP. ESTADUAL" })); nmu = ("{2} {0:00} ({1})" -f ($j + 1), $uf.ToUpper(), $(if ($cargo -eq 6) { "DEPUTADO" } else { "DEP. ESTADUAL" })); e = $(if ($j -lt $nv) { "s" } else { "n" }); st = $st; vap = "$votos"; pvap = "1,00" })
    }
    $cs = @(); foreach ($k in $par.Keys) { $cs += [ordered]@{ sg = $k; cand = @($par[$k]) } }
    return Boletim $cargo $nv $cs 100 "f" $te "04/10/2026" "23:50:00"
}

$ouvinte = New-Object System.Net.HttpListener
$ouvinte.Prefixes.Add("http://localhost:$Porta/"); $ouvinte.Prefixes.Add("http://127.0.0.1:$Porta/")
$ouvinte.Start()
Write-Host "TSE SIMULADO DO ENSAIO em http://localhost:$Porta/  (apuracao do 2o turno em $Minutos min)" -ForegroundColor Yellow
Write-Host "NAO E DADO REAL. Feche esta janela para encerrar o ensaio." -ForegroundColor Yellow
$re = [regex] '/(ele20\d\d)/(\d+)/dados/(\w+)/\w+-c(\d{4})-e\d{6}-u\.json$'
while ($ouvinte.IsListening) {
    $ctx = $ouvinte.GetContext(); $resp = $ctx.Response
    try {
        $m = $re.Match($ctx.Request.Url.AbsolutePath); $obj = $null
        if ($m.Success) {
            $ciclo = $m.Groups[1].Value; $ele = $m.Groups[2].Value; $abr = $m.Groups[3].Value.ToLower(); $cargo = [int] $m.Groups[4].Value
            if ($ciclo -eq "ele2022") { $ele = "x$ele" }   # 2022: so o 2o turno de Presidente (545)
            $ok = ($abr -eq "br" -or $ELEITORES.Contains($abr))
            if ($ok -and $cargo -eq 1 -and $ele -eq "x545") { $obj = Resp2022 $abr }
            elseif ($ok -and $cargo -eq 1 -and $ele -eq "9257") { $obj = RespPresidente $abr $false }
            elseif ($ok -and $cargo -eq 1 -and $ele -eq "9262") { $obj = RespPresidente $abr $true }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 3 -and $ele -eq "9259") { $obj = RespGovernador $abr $false }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 3 -and $ele -eq "9263") { $obj = RespGovernador $abr $true }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 5 -and $ele -eq "9259") { $obj = RespSenador $abr }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 6 -and $ele -eq "9259") { $obj = RespDeputados $abr }
            elseif ($abr -ne "br" -and $ok -and (($cargo -eq 7 -and $abr -ne "df") -or ($cargo -eq 8 -and $abr -eq "df")) -and $ele -eq "9259") { $obj = RespDeputados $abr $cargo }
        }
        if ($ctx.Request.Url.AbsolutePath -match '/comum/config/ele-c\.json$') {   # lista de eleicoes (CODIGOS-2-TURNO.bat)
            function Ele($cd, $nm, $cargos) { return [ordered]@{ cd = $cd; nm = $nm; abr = @([ordered]@{ cd = "BR"; cp = @($cargos | ForEach-Object { [ordered]@{ cd = "$_" } }) }) } }
            $obj = [ordered]@{ c = "ele2026"; pl = @(
                [ordered]@{ cd = "9001"; dt = "04/10/2026"; e = @((Ele "9257" "ENSAIO - Presidente 1o turno" @(1)), (Ele "9259" "ENSAIO - Estaduais 1o turno" @(3, 5, 6))) },
                [ordered]@{ cd = "9002"; dt = "25/10/2026"; e = @((Ele "9262" "ENSAIO - Presidente 2o turno" @(1)), (Ele "9263" "ENSAIO - Governador 2o turno" @(3))) }) }
        }
        if ($null -eq $obj) { $resp.StatusCode = 404; $b = [Text.Encoding]::UTF8.GetBytes("nao publicado") }
        else { $resp.ContentType = "application/json; charset=utf-8"; $b = (New-Object System.Text.UTF8Encoding($false)).GetBytes(($obj | ConvertTo-Json -Depth 10 -Compress)) }
        $resp.OutputStream.Write($b, 0, $b.Length)
    } catch { try { $resp.StatusCode = 500 } catch { } }
    finally { try { $resp.OutputStream.Close() } catch { } }
}
