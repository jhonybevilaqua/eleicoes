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
$PARTIDOS = @("PL", "PT", "MDB", "PSD", "UNIÃO", "PP", "REPUBLICANOS", "PSB", "PDT", "PSDB", "PODE")
$Inicio = Get-Date

function Rnd([string] $chave) {   # 0..1 fixo por chave (o ensaio e sempre igual)
    $h = 17; foreach ($ch in $chave.ToCharArray()) { $h = ($h * 31 + [int] $ch) % 1000003 }
    return (($h * 7919) % 10007) / 10007.0
}
function Br([double] $v) { return $v.ToString("0.00", [Globalization.CultureInfo]::InvariantCulture).Replace(".", ",") }
function Cand($n, $sq, $nome, $sg, $votos, $pct, $st, $e) {
    return [ordered]@{ sg = $sg; cand = @([ordered]@{ n = "$n"; sqcand = "$sq"; nm = $nome; nmu = $nome; e = $e; st = $st; dvt = "Valido"; vap = "$([long] $votos)"; pvap = (Br $pct) }) }
}
# abstencao, brancos e nulos FICTICIOS que variam por estado e por turno
# (para o ensaio exercitar os comparativos 1o x 2o). tur: 1, 2 ou 3 (2022).
function Taxas([string] $abr, [int] $tur) {
    if ($abr -eq "br") {   # Brasil = media dos estados pesada pelo eleitorado
        $ta = 0.0; $tb = 0.0; $tn = 0.0; $tt = 0.0
        foreach ($u in $ELEITORES.Keys) { $x = Taxas $u $tur; $w = [double] $ELEITORES[$u]; $ta += $x.a * $w; $tb += $x.b * $w; $tn += $x.n * $w; $tt += $w }
        return @{ a = $ta / $tt; b = $tb / $tt; n = $tn / $tt }
    }
    $a = 0.17 + 0.07 * (Rnd "a$abr"); $b = 0.015 + 0.015 * (Rnd "b$abr"); $n = 0.03 + 0.03 * (Rnd "n$abr")
    if ($tur -eq 2) { $a += 0.01 + 0.02 * (Rnd "a2$abr"); $b -= 0.004 + 0.004 * (Rnd "b2$abr"); $n += 0.004 + 0.012 * (Rnd "n2$abr") }
    if ($tur -eq 3) { $a += 0.005 * (Rnd "a3$abr") }
    return @{ a = $a; b = $b; n = $n }
}
function Boletim($cd, $nv, $cands, [double] $pst, $and, [long] $te, $dg, $hg, [string] $abr = "", [int] $tur = 0) {
    $vv = 0; foreach ($c in $cands) { $vv += [long] $c.cand[0].vap }
    $tx = $(if ($abr -and $tur) { Taxas $abr $tur } else { @{ a = 0.21; b = 0.02; n = 0.05 } })
    $est = [long] ($te * $pst / 100); $comp = [long] ($est * (1 - $tx.a))
    return [ordered]@{ f = "O"; and = $and; dg = $dg; hg = $hg
        s = [ordered]@{ ts = "1000"; st = "$([int] (10 * $pst))"; pst = (Br $pst) }
        e = [ordered]@{ te = "$te"; est = "$est"; esnt = "$($te - $est)"; c = "$comp"; pc = (Br (100 * (1 - $tx.a))); a = "$($est - $comp)"; pa = (Br (100 * $tx.a)) }
        v = [ordered]@{ vv = "$vv"; pvv = (Br (100 * (1 - $tx.b - $tx.n))); vb = "$([long] ($comp * $tx.b))"; pvb = (Br (100 * $tx.b)); tvn = "$([long] ($comp * $tx.n))"; ptvn = (Br (100 * $tx.n)) }
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
        return Boletim 1 1 $cs 100 "f" $te "04/10/2026" "23:50:00" $abr 1
    }
    $te = 0; $va = 0; $vb = 0; $est = 0; $ufs = $(if ($abr -eq "br") { @($ELEITORES.Keys) } else { @($abr) })
    foreach ($u in $ufs) { $x = Pres2T $u; $te += $x.te; $va += $x.va; $vb += $x.vb; $est += $x.te * $x.pst / 100 }
    $pst = $(if ($te) { 100 * $est / $te } else { 0 }); $fim = $pst -ge 99.99
    $tot = [math]::Max(1, $va + $vb); $pa = 100 * $va / $tot
    $stA = ""; $stB = ""; if ($fim) { if ($va -ge $vb) { $stA = "Eleito"; $stB = "Nao eleito" } else { $stB = "Eleito"; $stA = "Nao eleito" } }
    $cs = @((Cand 13 900013 "CANDIDATO A" "PT" $va $pa $stA $(if ($stA -eq "Eleito") { "s" } else { "n" })), (Cand 22 900022 "CANDIDATO B" "PL" $vb (100 - $pa) $stB $(if ($stB -eq "Eleito") { "s" } else { "n" })))
    return Boletim 1 1 $cs ([math]::Min(100, $pst)) $(if ($fim) { "f" } else { "p" }) $te "25/10/2026" (Relogio (FracGeral)) $abr 2
}
function Resp2022([string] $abr) {   # 2o turno de 2022 ficticio: A (PT) x B (PL)
    $ufs = $(if ($abr -eq "br") { @($ELEITORES.Keys) } else { @($abr) }); $va = 0; $vb = 0; $te = 0
    foreach ($u in $ufs) { $t = $ELEITORES[$u] * 1000 * 0.79 * 0.93; $l = (LulaFinal $u) - 0.02 + 0.04 * (Rnd "z$u"); $va += $t * $l; $vb += $t * (1 - $l); $te += $ELEITORES[$u] * 1000 }
    $tot = $va + $vb
    $cs = @((Cand 13 800013 "CANDIDATO X (2022)" "PT" $va (100 * $va / $tot) "Eleito" "s"), (Cand 22 800022 "CANDIDATO Y (2022)" "PL" $vb (100 * $vb / $tot) "Nao eleito" "n"))
    return Boletim 1 1 $cs 100 "f" ([long] $te) "30/10/2022" "20:00:00" $abr 3
}
# municipios do ensaio: as 27 capitais (codigos ficticios) e 12 cidades no exterior
$CAP = [ordered]@{ ac = "RIO BRANCO"; al = "MACEIÓ"; ap = "MACAPÁ"; am = "MANAUS"; ba = "SALVADOR"; ce = "FORTALEZA"; df = "BRASÍLIA"; es = "VITÓRIA"; go = "GOIÂNIA"
    ma = "SÃO LUÍS"; mt = "CUIABÁ"; ms = "CAMPO GRANDE"; mg = "BELO HORIZONTE"; pa = "BELÉM"; pb = "JOÃO PESSOA"; pr = "CURITIBA"; pe = "RECIFE"; pi = "TERESINA"
    rj = "RIO DE JANEIRO"; rn = "NATAL"; rs = "PORTO ALEGRE"; ro = "PORTO VELHO"; rr = "BOA VISTA"; sc = "FLORIANÓPOLIS"; sp = "SÃO PAULO"; se = "ARACAJU"; to = "PALMAS" }
$EXT = @("LISBOA", "PORTO", "MIAMI", "BOSTON", "NOVA YORK", "TÓQUIO", "NAGOIA", "LONDRES", "MADRI", "BUENOS AIRES", "ASSUNÇÃO", "ZURIQUE")
function RespMunConfig {
    $abr = @()
    $k = 0; foreach ($u in $CAP.Keys) { $k++; $abr += [ordered]@{ cd = $u.ToUpper(); ds = "UF $($u.ToUpper())"; mu = @([ordered]@{ cd = "{0:00000}" -f (90000 + $k); cdi = ""; nm = $CAP[$u]; c = "S"; z = @() }, [ordered]@{ cd = "{0:00000}" -f (91000 + $k); cdi = ""; nm = "INTERIOR $($u.ToUpper())"; c = "N"; z = @() }) } }
    # maiores cidades fora as capitais (nomes reais, codigos e votos ficticios)
    $GC = @(@("sp", "GUARULHOS"), @("sp", "CAMPINAS"), @("sp", "SÃO BERNARDO DO CAMPO"), @("sp", "SANTO ANDRÉ"), @("sp", "OSASCO"), @("sp", "SOROCABA"), @("sp", "RIBEIRÃO PRETO"),
        @("sp", "SÃO JOSÉ DOS CAMPOS"), @("rj", "SÃO GONÇALO"), @("rj", "DUQUE DE CAXIAS"), @("rj", "NOVA IGUAÇU"), @("mg", "UBERLÂNDIA"), @("mg", "CONTAGEM"), @("mg", "JUIZ DE FORA"),
        @("pe", "JABOATÃO DOS GUARARAPES"), @("ba", "FEIRA DE SANTANA"), @("pr", "LONDRINA"), @("sc", "JOINVILLE"), @("go", "APARECIDA DE GOIÂNIA"))
    $g = 0; foreach ($par in $GC) { $g++; $ab0 = @($abr | Where-Object { $_.cd -eq $par[0].ToUpper() })[0]; $ab0.mu += [ordered]@{ cd = "{0:00000}" -f (92000 + $g); cdi = ""; nm = $par[1]; c = "N"; z = @() } }
    $i = 0; $abr += [ordered]@{ cd = "ZZ"; ds = "EXTERIOR"; mu = @($EXT | ForEach-Object { $i++; [ordered]@{ cd = "{0:00000}" -f (29000 + $i); cdi = ""; nm = $_; c = "N"; z = @() } }) }
    return [ordered]@{ dg = "04/10/2026"; abr = $abr }
}
function RespMunicipio([string] $uf, [string] $cd, [bool] $turno2) {
    $chave = "$uf$cd"; $te = [long] (40000 + 400000 * (Rnd "t$chave")); if ($uf -ne "zz") { $te = [long] ($ELEITORES[$uf] * 1000 * (0.15 + 0.2 * (Rnd "c$chave"))) }
    $base = $(if ($uf -eq "zz") { 0.30 + 0.35 * (Rnd "e$chave") } else { (LulaFinal $uf) + 0.08 * (Rnd "m$chave") - 0.04 })
    if (-not $turno2) {
        $t = $te * 0.75; $va = $t * $base * 0.9; $vb = $t * (1 - $base) * 0.9; $vc = $t * 0.06; $vd = $t * 0.04; $tot = $va + $vb + $vc + $vd
        $cs = @((Cand 13 900013 "CANDIDATO A" "PT" $va (100 * $va / $tot) "" "n"), (Cand 22 900022 "CANDIDATO B" "PL" $vb (100 * $vb / $tot) "" "n"), (Cand 30 900030 "CANDIDATO C" "NOVO" $vc (100 * $vc / $tot) "" "n"), (Cand 15 900015 "CANDIDATO D" "MDB" $vd (100 * $vd / $tot) "" "n"))
        return Boletim 1 1 $cs 100 "f" $te "04/10/2026" "23:50:00"
    }
    $p = $(if ($cd -eq "22022") { 1.0 } elseif ($uf -eq "zz") { [math]::Min(1.0, (FracGeral) * 1.6) } else { Progresso $uf }); $pst = 100 * [math]::Pow($p, 0.8); $vv = $te * 0.75 * $pst / 100
    $a = $base - 0.05 * (1 - $p)
    $cs = @((Cand 13 900013 "CANDIDATO A" "PT" ($vv * $a) (100 * $a) "" "n"), (Cand 22 900022 "CANDIDATO B" "PL" ($vv * (1 - $a)) (100 - 100 * $a) "" "n"))
    return Boletim 1 1 $cs $pst $(if ($pst -ge 99.99) { "f" } else { "p" }) $te "25/10/2026" (Relogio (FracGeral))
}
function Resp2022Gov([string] $uf, [bool] $turno2) {   # governadores de 2022 ficticios
    $te = [long] ($ELEITORES[$uf] * 1000); $t = $te * 0.79 * 0.93; $sgA = $PARTIDOS[[int] (10 * (Rnd "x1$uf"))]; $sgB = $PARTIDOS[[int] (10 * (Rnd "x2$uf"))]
    $vai2 = (Rnd "x3$uf") -lt 0.4
    if (-not $turno2 -and $vai2) { $cs = @((Cand 11 1 "GOV 2022 A ($($uf.ToUpper()))" $sgA ($t * 0.45) 45 "2o turno" "n"), (Cand 22 2 "GOV 2022 B ($($uf.ToUpper()))" $sgB ($t * 0.40) 40 "2o turno" "n")) }
    elseif (-not $turno2) { $cs = @((Cand 11 1 "GOV 2022 A ($($uf.ToUpper()))" $sgA ($t * 0.58) 58 "Eleito" "s"), (Cand 22 2 "GOV 2022 B ($($uf.ToUpper()))" $sgB ($t * 0.30) 30 "Nao eleito" "n")) }
    elseif ($vai2) { $cs = @((Cand 11 1 "GOV 2022 A ($($uf.ToUpper()))" $sgA ($t * 0.48) 48 "Nao eleito" "n"), (Cand 22 2 "GOV 2022 B ($($uf.ToUpper()))" $sgB ($t * 0.52) 52 "Eleito" "s")) }
    else { return $null }
    return Boletim 3 1 $cs 100 "f" $te "30/10/2022" "20:00:00"
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

# 2022 no formato daquele ano (dados-simplificados ...-r.json): campos no
# topo e a lista "cand" sem sigla - o numero do candidato diz o partido.
$NUM22 = @{ "PL" = 22; "PT" = 13; "MDB" = 15; "PSD" = 55; "UNIÃO" = 44; "PP" = 11; "REPUBLICANOS" = 10; "PSB" = 40; "PDT" = 12; "PSDB" = 45; "PODE" = 19 }
function Simplificar($b) {
    $o = [ordered]@{ ele = "545"; t = "1"; pst = $b.s.pst; e = $b.e.te; c = $b.e.c; pc = $b.e.pc; a = $b.e.a; pa = $b.e.pa; vb = $b.v.vb; pvb = $b.v.pvb; tvn = $b.v.tvn; ptvn = $b.v.ptvn; cand = @() }
    $seq = 0
    foreach ($cg in @($b.carg)) { foreach ($agr in @($cg.agr)) { foreach ($pa in @($agr.par)) { foreach ($c in @($pa.cand)) {
        $seq++; $num = $(if ($NUM22.ContainsKey("$($pa.sg)")) { "$($NUM22["$($pa.sg)"])" } else { "$($c.n)" })
        $o.cand += [ordered]@{ seq = "$seq"; sqcand = $c.sqcand; n = $num; nm = $c.nm; cc = "COLIGACAO FICTICIA"; e = $c.e; st = $c.st; dvt = "Valido"; vap = $c.vap; pvap = $c.pvap }
    } } } }
    return $o
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
            if ($ciclo -eq "ele2022") { $ele = "nao-existe" }   # 2022 nao tem o formato novo (-u): so dados-simplificados (abaixo)
            $ok = ($abr -eq "br" -or $ELEITORES.Contains($abr))
            if ($abr -eq "zz" -and $cargo -eq 1 -and $ele -eq "x545") { $obj = RespMunicipio "zz" "22022" $true }   # exterior 2022
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 3 -and $ele -eq "x546") { $obj = Resp2022Gov $abr $false }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 3 -and $ele -eq "x547") { $obj = Resp2022Gov $abr $true }
            elseif ($abr -eq "zz" -and $cargo -eq 1 -and ($ele -eq "9257" -or $ele -eq "9262")) { $obj = RespMunicipio "zz" "00000" ($ele -eq "9262") }   # exterior (total)
            elseif ($ok -and $cargo -eq 1 -and $ele -eq "x545") { $obj = Resp2022 $abr }
            elseif ($ok -and $cargo -eq 1 -and $ele -eq "9257") { $obj = RespPresidente $abr $false }
            elseif ($ok -and $cargo -eq 1 -and $ele -eq "9262") { $obj = RespPresidente $abr $true }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 3 -and $ele -eq "9259") { $obj = RespGovernador $abr $false }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 3 -and $ele -eq "9263") { $obj = RespGovernador $abr $true }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 5 -and $ele -eq "9259") { $obj = RespSenador $abr }
            elseif ($abr -ne "br" -and $ok -and $cargo -eq 6 -and $ele -eq "9259") { $obj = RespDeputados $abr }
            elseif ($abr -ne "br" -and $ok -and (($cargo -eq 7 -and $abr -ne "df") -or ($cargo -eq 8 -and $abr -eq "df")) -and $ele -eq "9259") { $obj = RespDeputados $abr $cargo }
        }
        $m22 = [regex]::Match($ctx.Request.Url.AbsolutePath, '/ele2022/(\d+)/dados-simplificados/(\w+)/\w+-c(\d{4})-e\d{6}-r\.json$')
        if ($m22.Success) {
            $e22 = $m22.Groups[1].Value; $a22 = $m22.Groups[2].Value.ToLower(); $c22 = [int] $m22.Groups[3].Value; $ok22 = ($a22 -eq "br" -or $ELEITORES.Contains($a22)); $b22 = $null
            if ($a22 -eq "zz" -and $c22 -eq 1 -and $e22 -eq "545") { $b22 = RespMunicipio "zz" "22022" $true }
            elseif ($ok22 -and $c22 -eq 1 -and $e22 -eq "545") { $b22 = Resp2022 $a22 }
            elseif ($a22 -ne "br" -and $ok22 -and $c22 -eq 3 -and $e22 -eq "546") { $b22 = Resp2022Gov $a22 $false }
            elseif ($a22 -ne "br" -and $ok22 -and $c22 -eq 3 -and $e22 -eq "547") { $b22 = Resp2022Gov $a22 $true }
            if ($null -ne $b22) { $obj = Simplificar $b22 }
        }
        $mm = [regex]::Match($ctx.Request.Url.AbsolutePath, '/ele2026/(\d+)/config/mun-e\d{6}-cm\.json$')
        if ($mm.Success -and @("9257", "9262") -contains $mm.Groups[1].Value) { $obj = RespMunConfig }
        $mb = [regex]::Match($ctx.Request.Url.AbsolutePath, '/ele2026/(\d+)/dados/(\w\w)/(\w\w)(\d{5})-c0001-e\d{6}-u\.json$')
        if ($mb.Success -and @("9257", "9262") -contains $mb.Groups[1].Value) { $obj = RespMunicipio $mb.Groups[3].Value.ToLower() $mb.Groups[4].Value ($mb.Groups[1].Value -eq "9262") }
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
