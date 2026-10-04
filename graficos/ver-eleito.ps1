<#
    gctse GRAFICOS - VER ELEITO: o que o TSE manda para um estado
    (Governador e Senador) e o que a tela recebeu (web\estados.js).
    Uso: VER-ELEITO.bat  (pergunta a sigla; padrao MT)
    Grava tudo tambem em VER-ELEITO.txt para mandar ao suporte.
#>
param([string] $Uf = "")
$ErrorActionPreference = "Continue"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
if (-not $Uf) { $Uf = Read-Host "Sigla do estado (Enter = MT)" }
if (-not $Uf) { $Uf = "mt" }
$Uf = $Uf.Trim().ToLower()
$saida = New-Object System.Collections.Generic.List[string]
function L([string] $t) { Write-Host $t; $saida.Add($t) }

$cfg = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$base = "$($cfg.tse.base_url)".TrimEnd('/'); $ciclo = "$($cfg.tse.ciclo)"; $ele = "$($cfg.tse.eleicao_estaduais)"
L ("gctse VER-ELEITO - {0} - {1}" -f $Uf.ToUpper(), (Get-Date -Format "dd/MM/yyyy HH:mm:ss"))
L ""

# 1) o que a TELA recebeu
try {
    $txt = [IO.File]::ReadAllText((Join-Path $Raiz "web\estados.js"), [Text.Encoding]::UTF8)
    $i = $txt.IndexOf("{"); $j = $txt.LastIndexOf("}")
    $e = $txt.Substring($i, $j - $i + 1) | ConvertFrom-Json
    L ("TELA (web\estados.js): coletor versao {0}, gravado {1}" -f $e.versao, $e.gravado_em)
    $u = $e.ufs.$Uf
    foreach ($q in @("gov", "sen")) {
        $c = $u.$q
        if (-not $c -or -not $c.tem) { L ("  {0}: sem boletim" -f $q); continue }
        L ("  {0}: urnas {1}%  andamento={2}" -f $q, $c.urnas_pct, $c.andamento)
        $cs = @($c.candidatos); if ($cs.Count -eq 1 -and $cs[0].PSObject.Properties["value"]) { $cs = @($cs[0].value) }
        foreach ($k in ($cs | Select-Object -First 4)) {
            $calc = ""
            if ($k.PSObject.Properties["calculado"] -and $k.calculado) {
                if ($k.segundo_turno) { $calc = "  (2o turno definido pela conta)" } else { $calc = "  (matematicamente eleito pela conta)" }
            }
            L ("     {0,-28} {1,6}%  eleito={2,-5} 2turno={3,-5} situacao='{4}'{5}" -f $k.nome, $k.pct, $k.eleito, $k.segundo_turno, $k.situacao, $calc)
        }
    }
} catch { L "TELA: nao consegui ler web\estados.js ($($_.Exception.Message))" }
L ""

# 2) o que o TSE MANDA agora
foreach ($cargo in @(3, 5)) {
    $url = "{0}/{1}/{2}/dados/{3}/{3}-c{4:0000}-e{5:000000}-u.json" -f $base, $ciclo, $ele, $Uf, $cargo, [int] $ele
    L ("TSE {0}: {1}" -f $(if ($cargo -eq 3) { "GOVERNADOR" } else { "SENADOR" }), $url)
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -Headers @{ "Cache-Control" = "no-cache" }
        $b = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json
        $topo = @()
        foreach ($p in $b.PSObject.Properties) { if ($p.Name -notin @("carg", "s", "e", "v")) { $topo += ("{0}={1}" -f $p.Name, ((ConvertTo-Json -InputObject $p.Value -Compress -Depth 3) -replace '^"|"$', '')) } }
        L ("  topo: " + ($topo -join "  "))
        if ($b.s) { L ("  urnas: pst={0}" -f $b.s.pst) }
        if ($b.e) { L ("  eleitorado: total={0}  em secoes apuradas={1}  FALTAM (secoes nao totalizadas)={2}  comparecimento={3}%" -f $b.e.te, $b.e.est, $b.e.esnt, $b.e.pc) }
        $lista = @()
        foreach ($cg in @($b.carg)) {
            $extra = @(); foreach ($p in $cg.PSObject.Properties) { if ($p.Name -notin @("agr", "fed")) { $extra += ("{0}={1}" -f $p.Name, ((ConvertTo-Json -InputObject $p.Value -Compress -Depth 2) -replace '^"|"$', '')) } }
            L ("  cargo: " + ($extra -join "  "))
            foreach ($agr in @($cg.agr)) { foreach ($pa in @($agr.par)) { foreach ($c in @($pa.cand)) {
                $lista += [pscustomobject]@{ nm = "$($c.nmu)"; e = "$($c.e)"; st = "$($c.st)"; pvap = "$($c.pvap)"; vap = [long] ("0" + ("$($c.vap)" -replace '\D', '')) }
            } } }
        }
        foreach ($k in ($lista | Sort-Object vap -Descending | Select-Object -First 4)) {
            L ("     {0,-28} {1,6}%  e='{2}'  st='{3}'" -f $k.nm, $k.pvap, $k.e, $k.st)
        }
    } catch { L ("  ERRO: " + $_.Exception.Message) }
    L ""
}
$saida | Set-Content -Path (Join-Path $Raiz "VER-ELEITO.txt") -Encoding UTF8
Write-Host "Gravado em VER-ELEITO.txt" -ForegroundColor Green
