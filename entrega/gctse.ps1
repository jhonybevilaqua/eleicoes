<#
    gctse - Apuracao do TSE para o gerador de caracteres
    ------------------------------------------------------------------
    Roda direto no Windows. Nao instala nada, nao precisa de Python e nao
    precisa de internet alem do proprio TSE.

    Escrito para Windows PowerShell 5.1 (o que ja vem no Windows), sem
    recursos de versoes mais novas.

        .\gctse.ps1 -Preencher    enche TARJAS com exemplos, para montar a cena
        .\gctse.ps1 -Descobrir    mostra os codigos do pleito
        .\gctse.ps1 -Ensaio       dados ficticios, nao consulta o TSE
        .\gctse.ps1 -Teste        aceita o simulado do TSE (fase S)
        .\gctse.ps1               no ar: so boletim oficial
#>

[CmdletBinding()]
param(
    [switch] $Descobrir,
    [switch] $Preencher,
    [switch] $Ensaio,
    [switch] $Teste,
    [switch] $UmaVez,
    [int]    $DuracaoEnsaio = 600,
    [string] $Config = "config.json"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# TLS 1.2: o Windows PowerShell 5.1 ainda negocia TLS 1.0 por padrao em
# maquina antiga, e o TSE recusa. Sem esta linha a coleta falha sem explicar.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Trabalha sempre a partir da pasta do proprio script: duplo clique herda um
# diretorio qualquer, e ai os caminhos relativos apontam para o lugar errado.
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz

# ---------------------------------------------------------------- utilidades

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
        Add-Content -Path ("logs\gctse-{0}.log" -f (Get-Date -Format "yyyy-MM-dd")) -Value $linha
    } catch { }
}

function Converter-Inteiro {
    # "12.345.678" -> 12345678 (o TSE manda numero como texto pt-BR)
    param($Valor)
    if ($null -eq $Valor) { return 0 }
    $limpo = ([string] $Valor) -replace '[^\d\-]', ''
    if ($limpo -eq '' -or $limpo -eq '-') { return 0 }
    try { return [int64] $limpo } catch { return 0 }
}

function Converter-Decimal {
    # "49,10" -> 49.10   |   "1.234,56" -> 1234.56
    param($Valor)
    if ($null -eq $Valor) { return 0.0 }
    $texto = ([string] $Valor).Trim().Replace('%', '').Replace(' ', '')
    if ($texto -eq '') { return 0.0 }
    if ($texto.Contains(',')) { $texto = $texto.Replace('.', '').Replace(',', '.') }
    try { return [double]::Parse($texto, [Globalization.CultureInfo]::InvariantCulture) }
    catch { return 0.0 }
}

function Formatar-Inteiro {
    param([int64] $Valor)
    return $Valor.ToString("N0", [Globalization.CultureInfo]::GetCultureInfo("pt-BR"))
}

function Formatar-Percentual {
    param([double] $Valor)
    return ($Valor.ToString("N2", [Globalization.CultureInfo]::GetCultureInfo("pt-BR")) + "%")
}

function Limitar-Texto {
    # Corta no limite sem quebrar palavra no meio.
    param([string] $Texto, [int] $Limite)
    if ($null -eq $Texto) { return "" }
    $t = ($Texto -replace '\s+', ' ').Trim().ToUpper()
    if ($Limite -le 0 -or $t.Length -le $Limite) { return $t }
    $corte = $t.Substring(0, $Limite)
    if ($corte.Contains(' ')) { $corte = $corte.Substring(0, $corte.LastIndexOf(' ')) }
    return $corte.TrimEnd()
}

function Escrever-Arquivo {
    # Escrita atomica: o GC pode ler a qualquer instante, e um arquivo lido
    # pela metade vira placar truncado no ar. Grava em .tmp e promove.
    param([string] $Caminho, [string] $Conteudo)
    $pasta = Split-Path -Parent $Caminho
    if ($pasta -and -not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    $temporario = "$Caminho.tmp"
    $utf8 = New-Object System.Text.UTF8Encoding($false)   # sem BOM
    [IO.File]::WriteAllText($temporario, $Conteudo, $utf8)
    Move-Item -Path $temporario -Destination $Caminho -Force
}

function Tem-Propriedade {
    # $obj.PSObject.Properties.Name quebra sob StrictMode quando o objeto nao
    # tem propriedade nenhuma (ex.: "cores_partido": {} no config).
    param($Objeto, [string] $Nome)
    if ($null -eq $Objeto) { return $false }
    foreach ($prop in $Objeto.PSObject.Properties) {
        if ($prop.Name -eq $Nome) { return $true }
    }
    return $false
}

function Obter-Hash {
    param([string] $Texto)
    $sha = [Security.Cryptography.SHA1]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Texto))
    return -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

# ------------------------------------------------------------------- config

if (-not (Test-Path $Config)) {
    Escrever-Log "Arquivo $Config nao encontrado nesta pasta." "ERRO"
    exit 1
}
$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json

$PastaSaida = $cfg.pasta_saida
$LimiteNome = $cfg.texto.limite_nome
$LimitePartido = $cfg.texto.limite_partido
$SeloNaoOficial = $cfg.texto.selo_nao_oficial
$PadraoFoto = $cfg.texto.padrao_foto
$CorPadrao = $cfg.texto.cor_padrao

function Obter-Cor {
    param([string] $Partido)
    $sigla = ([string] $Partido).Trim().ToUpper()
    if ($sigla -and (Tem-Propriedade $cfg.texto.cores_partido $sigla)) {
        return $cfg.texto.cores_partido.$sigla
    }
    return $CorPadrao
}

function Montar-Url {
    param([string] $Abrangencia, [int] $Cargo)
    $dir = $Abrangencia
    if ($Abrangencia.Length -gt 2) { $dir = $Abrangencia.Substring(0, 2) }
    $c = "{0:0000}" -f $Cargo
    $e = "{0:000000}" -f ([int] $cfg.tse.eleicao)
    return "{0}/{1}/{2}/dados-simplificados/{3}/{4}-c{5}-e{6}-r.json" -f `
        $cfg.tse.base_url.TrimEnd('/'), $cfg.tse.ciclo, $cfg.tse.pleito, $dir, $Abrangencia, $c, $e
}

# ------------------------------------------------------------------- coleta

$Cache = @{}    # url -> ETag, para nao rebaixar a origem do TSE

function Obter-Boletim {
    param([string] $Url)
    $cabecalhos = @{ "User-Agent" = "gctse/1.0" }
    if ($Cache.ContainsKey($Url)) { $cabecalhos["If-None-Match"] = $Cache[$Url] }
    try {
        $resposta = Invoke-WebRequest -Uri $Url -Headers $cabecalhos -TimeoutSec 15 -UseBasicParsing
    } catch {
        $codigo = 0
        try { $codigo = [int] $_.Exception.Response.StatusCode } catch { }
        if ($codigo -eq 304) { return "SEM-MUDANCA" }
        if ($codigo -eq 404) { return $null }        # ainda nao publicado
        Escrever-Log "falha em $Url : $($_.Exception.Message)" "AVISO"
        return $null
    }
    try { $Cache[$Url] = $resposta.Headers["ETag"] } catch { }
    return ($resposta.Content | ConvertFrom-Json)
}

function Obter-Campo {
    # O TSE usa chaves abreviadas e ja as renomeou entre pleitos: tenta varias.
    param($Objeto, [string[]] $Chaves, $Padrao = $null)
    if ($null -eq $Objeto) { return $Padrao }
    foreach ($chave in $Chaves) {
        if (Tem-Propriedade $Objeto $chave) {
            $valor = $Objeto.$chave
            if ($null -ne $valor -and "$valor" -ne "") { return $valor }
        }
    }
    return $Padrao
}

function Normalizar-Boletim {
    # JSON do TSE -> objeto simples, com o que as tarjas usam.
    param($Bruto, [string] $Praca)

    $secoes = Obter-Campo $Bruto @("s")
    $pct = Converter-Decimal (Obter-Campo $secoes @("pst") (Obter-Campo $Bruto @("pst")))
    $validos = Converter-Inteiro (Obter-Campo $Bruto @("vv", "vvc"))

    $lista = Obter-Campo $Bruto @("cand", "candidatos")
    $candidatos = @()
    if ($lista) {
        foreach ($c in $lista) {
            $votos = Converter-Inteiro (Obter-Campo $c @("vap", "votos"))
            $perc = Converter-Decimal (Obter-Campo $c @("pvap"))
            if ($perc -eq 0 -and $validos -gt 0) { $perc = [math]::Round(100.0 * $votos / $validos, 2) }
            $eleito = "0"
            if ("$(Obter-Campo $c @('e'))".ToLower() -eq "s") { $eleito = "1" }
            $candidatos += [pscustomobject]@{
                Numero     = "$(Obter-Campo $c @('n') '')"
                Nome       = "$(Obter-Campo $c @('nm','nmurna') '')"
                Partido    = "$(Obter-Campo $c @('cc') '')"
                Votos      = $votos
                Percentual = $perc
                Eleito     = $eleito
            }
        }
    }
    $candidatos = @($candidatos | Sort-Object -Property @{Expression = "Votos"; Descending = $true}, Numero)

    $fase = "$(Obter-Campo $Bruto @('f') '')".ToUpper()
    $nome = "$(Obter-Campo $Bruto @('nmabr') $Praca)"
    if ($Praca) { $nome = $Praca }

    return [pscustomobject]@{
        Fase        = $fase
        Oficial     = ($fase -eq "O")
        Praca       = $nome
        PctUrnas    = $pct
        Geracao     = "$(Obter-Campo $Bruto @('dg') '') $(Obter-Campo $Bruto @('hg') '')"
        Candidatos  = $candidatos
    }
}

# ------------------------------------------------------------------ simulador

$ScriptInicio = Get-Date
function Gerar-Simulado {
    param([string] $Abrangencia, [int] $Cargo, [string] $Praca)
    if ($DuracaoEnsaio -le 0) {
        $pct = 63.0    # retrato de meia apuracao, para montar a cena
    } else {
        $decorrido = ((Get-Date) - $ScriptInicio).TotalSeconds / $DuracaoEnsaio
        $pct = [math]::Round(100.0 * [math]::Min(1.0, $decorrido), 2)
    }

    $semente = ($Abrangencia + $Cargo).GetHashCode()
    $rnd = New-Object System.Random($semente)
    $nomes = @("CANDIDATO ENSAIO A", "CANDIDATO ENSAIO B", "CANDIDATO ENSAIO C", "CANDIDATO ENSAIO D")
    $siglas = @("PVL", "PDR", "PSU", "PNA")

    $forcas = @(); for ($i = 0; $i -lt $nomes.Count; $i++) { $forcas += $rnd.NextDouble() * 0.5 + 0.5 }
    $soma = ($forcas | Measure-Object -Sum).Sum
    $validos = [int] (4000000 * $pct / 100.0)

    $cands = @()
    for ($i = 0; $i -lt $nomes.Count; $i++) {
        $votos = [int] ($validos * $forcas[$i] / $soma)
        $perc = 0.0
        if ($validos -gt 0) { $perc = [math]::Round(100.0 * $votos / $validos, 2) }
        $cands += [pscustomobject]@{
            Numero = "$((($i + 1) * 11))"; Nome = $nomes[$i]; Partido = $siglas[$i]
            Votos = $votos; Percentual = $perc
            Eleito = $(if ($pct -ge 100 -and $i -eq 0) { "1" } else { "0" })
        }
    }
    $cands = @($cands | Sort-Object -Property @{Expression = "Votos"; Descending = $true})

    return [pscustomobject]@{
        Fase = "S"; Oficial = $false; Praca = $Praca; PctUrnas = $pct
        Geracao = (Get-Date -Format "dd/MM/yyyy HH:mm:ss"); Candidatos = $cands
    }
}

# --------------------------------------------------------------- montar tarja

function Montar-Tarja {
    param($Boletim, $Tarja)

    $selo = ""
    if (-not $Boletim.Oficial) { $selo = $SeloNaoOficial }

    $saida = [ordered]@{
        cargo            = Limitar-Texto (Obter-NomeCargo $Tarja.cargo) 24
        abrangencia      = Limitar-Texto $Boletim.Praca 24
        apuracao_pct     = Formatar-Percentual $Boletim.PctUrnas
        selo             = $selo
        hora_atualizacao = (Get-Date -Format "HH:mm")
    }

    $trilho = 0
    if (Tem-Propriedade $Tarja "trilho_px") { $trilho = [int] $Tarja.trilho_px }

    for ($i = 1; $i -le 2; $i++) {
        $c = $null
        if ($Boletim.Candidatos.Count -ge $i) { $c = $Boletim.Candidatos[$i - 1] }
        $p = "cand$i" + "_"
        if ($null -eq $c) {
            $saida[$p + "visivel"] = "0"
            $saida[$p + "nome"] = ""
            $saida[$p + "partido"] = ""
            if ($Tarja.modelo -eq "presidente") { $saida[$p + "foto"] = "" }
            $saida[$p + "percentual"] = ""
            $saida[$p + "barra_px"] = 0
            $saida[$p + "cor"] = ""
            $saida[$p + "eleito"] = "0"
        } else {
            $largura = 0
            if ($trilho -gt 0) {
                $largura = [int] [math]::Round($trilho * $c.Percentual / 100.0)
                if ($c.Percentual -gt 0 -and $largura -lt 6) { $largura = 6 }
            }
            $saida[$p + "visivel"] = "1"
            $saida[$p + "nome"] = Limitar-Texto $c.Nome $LimiteNome
            $saida[$p + "partido"] = Limitar-Texto $c.Partido $LimitePartido
            if ($Tarja.modelo -eq "presidente") {
                $saida[$p + "foto"] = $PadraoFoto.Replace("{numero}", $c.Numero)
            }
            $saida[$p + "percentual"] = Formatar-Percentual $c.Percentual
            $saida[$p + "barra_px"] = $largura
            $saida[$p + "cor"] = Obter-Cor $c.Partido
            $saida[$p + "eleito"] = $c.Eleito
        }
    }
    return $saida
}

function Obter-NomeCargo {
    param([int] $Codigo)
    switch ($Codigo) {
        1  { return "PRESIDENTE" }
        3  { return "GOVERNADOR" }
        5  { return "SENADOR" }
        6  { return "DEPUTADO FEDERAL" }
        7  { return "DEPUTADO ESTADUAL" }
        8  { return "DEPUTADO DISTRITAL" }
        11 { return "PREFEITO" }
        13 { return "VEREADOR" }
        default { return "CARGO $Codigo" }
    }
}

# ------------------------------------------------------------------- rodizio

function Montar-Lista {
    # Uma lista de pracas num arquivo so, um registro por praca.
    # Serve tanto para o rodizio automatico quanto para o operador escolher
    # o estado na hora: trocar de estado = trocar de registro, sem trocar
    # de arquivo e sem refazer vinculo.
    param($Lista, $Boletins)
    $limite = 14
    if (Tem-Propriedade $Lista "limite_nome") { $limite = [int] $Lista.limite_nome }

    $pracas = @()
    $ordem = 0
    foreach ($p in $Lista.pracas) {
        $ordem++
        $b = $null
        if ($Boletins.ContainsKey($p.uf)) { $b = $Boletins[$p.uf] }

        $registro = [ordered]@{
            ordem = $ordem; visivel = "0"; praca = Limitar-Texto $p.nome 24
            cargo = Obter-NomeCargo $Lista.cargo
            apuracao_pct = ""; selo = ""
            cand1_nome = ""; cand1_partido = ""; cand1_percentual = ""; cand1_cor = ""
            cand2_nome = ""; cand2_partido = ""; cand2_percentual = ""; cand2_cor = ""
        }
        if ($null -ne $b) {
            $registro.visivel = "1"
            $registro.apuracao_pct = Formatar-Percentual $b.PctUrnas
            if (-not $b.Oficial) { $registro.selo = $SeloNaoOficial }
            for ($i = 1; $i -le 2; $i++) {
                if ($b.Candidatos.Count -ge $i) {
                    $c = $b.Candidatos[$i - 1]
                    $registro."cand${i}_nome" = Limitar-Texto $c.Nome $limite
                    $registro."cand${i}_partido" = Limitar-Texto $c.Partido $LimitePartido
                    $registro."cand${i}_percentual" = Formatar-Percentual $c.Percentual
                    $registro."cand${i}_cor" = Obter-Cor $c.Partido
                }
            }
        }
        $pracas += [pscustomobject] $registro
    }
    $comDado = @($pracas | Where-Object { $_.visivel -eq "1" }).Count
    return [ordered]@{ lista = $Lista.arquivo; total = $pracas.Count; com_dado = $comDado; pracas = $pracas }
}

# -------------------------------------------------------------------- painel

function Escrever-Painel {
    param($Linhas, [int] $Intervalo, [string] $Modo)
    $corpo = ""
    foreach ($l in $Linhas) {
        $classe = "ok"
        if ($l.Situacao -like "falha*") { $classe = "erro" }
        elseif ($l.Situacao -like "bloqueado*" -or $l.Situacao -like "sem*") { $classe = "aviso" }
        $corpo += "<tr class='$classe'><td class='n'>$($l.Tarja)</td><td>$($l.Praca)</td>" +
                  "<td class='num'>$($l.Urnas)</td><td>$($l.Primeiro)</td><td class='num'>$($l.Pct1)</td>" +
                  "<td>$($l.Segundo)</td><td class='num'>$($l.Pct2)</td>" +
                  "<td><span class='tag $classe'>$($l.Situacao)</span></td></tr>`n"
    }
    $faixa = ""
    if ($Modo -ne "AR") {
        $faixa = "<div class='faixa'>MODO $Modo - dados nao oficiais. Nao use no ar.</div>"
    }
    $html = @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="$Intervalo"><title>Painel de apuracao</title><style>
body{margin:0;background:#0d1420;color:#e6ecf6;font:14px/1.5 "Segoe UI",sans-serif}
.topo{padding:18px 26px;border-bottom:1px solid #243247;display:flex;gap:18px;align-items:baseline}
h1{margin:0;font-size:19px}.m{color:#93a3bb;font-size:13px;margin-left:auto}
.faixa{background:#4a3410;color:#f0c674;padding:9px 26px;font-weight:600;letter-spacing:.05em}
main{padding:22px 26px}table{width:100%;border-collapse:collapse;font-size:13.5px}
th{text-align:left;font-size:11px;letter-spacing:.09em;color:#93a3bb;text-transform:uppercase;
padding:0 12px 8px 0;border-bottom:1px solid #243247}
td{padding:9px 12px 9px 0;border-bottom:1px solid #243247}
tr.erro td{background:#2a1416}tr.aviso td{background:#2a2312}
.n{font-weight:600}.num{text-align:right;font-variant-numeric:tabular-nums}
.tag{padding:2px 9px;border-radius:3px;font-size:11.5px;font-weight:600}
.tag.ok{background:#13341f;color:#5fce93}.tag.aviso{background:#3a2f12;color:#f0c674}
.tag.erro{background:#3a1a1c;color:#ef8d8d}
</style></head><body>
<div class="topo"><h1>Painel de apuracao</h1>
<div class="m">modo <b>$Modo</b> &middot; atualizado <b>$(Get-Date -Format 'HH:mm:ss')</b>
&middot; recarrega a cada <b>${Intervalo}s</b></div></div>
$faixa
<main><table><thead><tr><th>Tarja</th><th>Praca</th><th class="num">Urnas</th>
<th>1o colocado</th><th class="num">%</th><th>2o colocado</th><th class="num">%</th>
<th>Situacao</th></tr></thead><tbody>
$corpo
</tbody></table></main></body></html>
"@
    Escrever-Arquivo (Join-Path $PastaSaida "painel.html") $html
}

# --------------------------------------------------------------------- ciclo

$Impressoes = @{}   # arquivo -> hash do conteudo, para nao reescrever a toa
$Geracoes = @{}     # arquivo -> ultima data/hora de geracao publicada

function Executar-Ciclo {
    param([string] $Modo)
    $linhas = @()

    foreach ($tarja in $cfg.tarjas) {
        $situacao = "sem dado"; $b = $null
        if ($Ensaio) {
            $b = Gerar-Simulado $tarja.abrangencia $tarja.cargo $tarja.praca
        } else {
            $bruto = Obter-Boletim (Montar-Url $tarja.abrangencia $tarja.cargo)
            if ($bruto -eq "SEM-MUDANCA") { $situacao = "sem mudanca" }
            elseif ($null -ne $bruto) { $b = Normalizar-Boletim $bruto $tarja.praca }
            else { $situacao = "falha" }
        }

        if ($null -ne $b) {
            # Trava de fase: simulado do TSE nunca vai ao ar por engano.
            if (-not $b.Oficial -and $Modo -eq "AR") {
                $situacao = "bloqueado (fase $($b.Fase))"
                Escrever-Log "$($tarja.arquivo): boletim nao oficial descartado" "AVISO"
            } else {
                $json = ($(Montar-Tarja $b $tarja) | ConvertTo-Json -Depth 5)
                $hash = Obter-Hash $json
                if ($Impressoes[$tarja.arquivo] -eq $hash) {
                    $situacao = "sem mudanca"
                } else {
                    Escrever-Arquivo (Join-Path $PastaSaida "$($tarja.arquivo).json") $json
                    $Impressoes[$tarja.arquivo] = $hash
                    $situacao = "publicado"
                }
            }
            $p1 = ""; $q1 = ""; $p2 = ""; $q2 = ""
            if ($b.Candidatos.Count -ge 1) {
                $p1 = "$($b.Candidatos[0].Nome) ($($b.Candidatos[0].Partido))"
                $q1 = Formatar-Percentual $b.Candidatos[0].Percentual
            }
            if ($b.Candidatos.Count -ge 2) {
                $p2 = "$($b.Candidatos[1].Nome) ($($b.Candidatos[1].Partido))"
                $q2 = Formatar-Percentual $b.Candidatos[1].Percentual
            }
            $linhas += [pscustomobject]@{
                Tarja = $tarja.arquivo; Praca = $b.Praca
                Urnas = (Formatar-Percentual $b.PctUrnas)
                Primeiro = $p1; Pct1 = $q1; Segundo = $p2; Pct2 = $q2; Situacao = $situacao
            }
        } else {
            $linhas += [pscustomobject]@{
                Tarja = $tarja.arquivo; Praca = $tarja.praca; Urnas = ""
                Primeiro = ""; Pct1 = ""; Segundo = ""; Pct2 = ""; Situacao = $situacao
            }
        }
    }

    # listas de pracas (rodizio automatico ou escolha do operador)
    if (Tem-Propriedade $cfg "listas") {
        # cada praca e buscada UMA vez por ciclo, mesmo aparecendo em varias
        # listas: governador de SP nao vale duas requisicoes ao TSE.
        $cacheCiclo = @{}
        foreach ($listaCfg in $cfg.listas) {
            $boletins = @{}
            foreach ($p in $listaCfg.pracas) {
                $chave = "$($p.uf)-$($listaCfg.cargo)"
                if (-not $cacheCiclo.ContainsKey($chave)) {
                    $b = $null
                    if ($Ensaio) {
                        $b = Gerar-Simulado $p.uf $listaCfg.cargo $p.nome
                    } else {
                        $bruto = Obter-Boletim (Montar-Url $p.uf $listaCfg.cargo)
                        if ($bruto -ne "SEM-MUDANCA" -and $null -ne $bruto) {
                            $b = Normalizar-Boletim $bruto $p.nome
                        }
                    }
                    if ($null -ne $b -and (-not $b.Oficial) -and $Modo -eq "AR") { $b = $null }
                    $cacheCiclo[$chave] = $b
                }
                $bb = $cacheCiclo[$chave]
                if ($null -ne $bb) {
                    $bb = $bb.PSObject.Copy()
                    $bb.Praca = $p.nome
                    $boletins[$p.uf] = $bb
                }
            }
            $lista = Montar-Lista $listaCfg $boletins
            $json = ($lista | ConvertTo-Json -Depth 6)
            $hash = Obter-Hash $json
            if ($Impressoes[$listaCfg.arquivo] -ne $hash) {
                Escrever-Arquivo (Join-Path $PastaSaida "$($listaCfg.arquivo).json") $json
                $Impressoes[$listaCfg.arquivo] = $hash
            }
            $linhas += [pscustomobject]@{
                Tarja = $listaCfg.arquivo; Praca = "$($lista.com_dado) de $($lista.total) pracas"
                Urnas = ""; Primeiro = ""; Pct1 = ""; Segundo = ""; Pct2 = ""
                Situacao = $(if ($lista.com_dado -gt 0) { "publicado" } else { "sem dado" })
            }
        }
    }

    Escrever-Painel $linhas ([int] $cfg.intervalo_segundos) $Modo
    return $linhas
}

# ---------------------------------------------------------------- descobrir

if ($Descobrir) {
    $url = "$($cfg.tse.base_url.TrimEnd('/'))/comum/config/ele-c.json"
    Escrever-Log "consultando $url"
    try {
        $dados = Invoke-RestMethod -Uri $url -TimeoutSec 20 -UseBasicParsing
        Write-Host ""
        Write-Host "Pleitos publicados pelo TSE:" -ForegroundColor Green
        ($dados | ConvertTo-Json -Depth 6)
        Write-Host ""
        Write-Host "Copie o codigo do pleito de 2026 para 'pleito' e 'eleicao' no config.json."
    } catch {
        Escrever-Log "nao foi possivel consultar: $($_.Exception.Message)" "ERRO"
        Escrever-Log "se for erro de conexao, peca a TI a liberacao de resultados.tse.jus.br:443" "ERRO"
        exit 1
    }
    exit 0
}

# ------------------------------------------------------------------ execucao

if ($Preencher) { $Ensaio = $true; $UmaVez = $true; $DuracaoEnsaio = 0 }

$Modo = "AR"
if ($Ensaio) { $Modo = "ENSAIO" } elseif ($Teste) { $Modo = "TESTE" }

Escrever-Log "modo $Modo | saida em $PastaSaida | intervalo $($cfg.intervalo_segundos)s" "OK"
if ($Modo -ne "AR") {
    Escrever-Log "dados NAO OFICIAIS neste modo. Nao use no ar." "AVISO"
}

do {
    $inicio = Get-Date
    try {
        $linhas = Executar-Ciclo $Modo
        $resumo = ($linhas | ForEach-Object { "$($_.Tarja)=$($_.Situacao)" }) -join "  "
        Escrever-Log $resumo
    } catch {
        Escrever-Log "erro no ciclo: $($_.Exception.Message)" "ERRO"
    }
    if ($UmaVez) { break }
    $gasto = ((Get-Date) - $inicio).TotalSeconds
    $espera = [math]::Max(1, [int] $cfg.intervalo_segundos - $gasto)
    Start-Sleep -Seconds $espera
} while ($true)
