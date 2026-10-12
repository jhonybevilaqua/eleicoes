<#
    Painel web do gctse - 2o TURNO (7.0)
    ------------------------------------------------------------------
    Abas GOVERNADOR (2o turno ao vivo em cima, eleitos no 1o turno embaixo,
    giro automatico na tarja), PRESIDENTE (2o turno ao vivo ou resultado do
    1o) e SENADOR. As tarjas sao as mesmas: so muda o dado que vai nelas.

    Abre uma pagina no navegador para o operador escolher o estado e
    acompanhar a apuracao. Substitui os .bat da pasta SELECIONAR-ESTADO.

    Roda como PROCESSO SEPARADO do coletor, de proposito: se o painel
    travar ou alguem fechar a janela, a coleta e as tarjas seguem no ar.
    Ele nao coleta nada - so le os arquivos da pasta TARJAS e escreve o
    SELECAO.txt, exatamente como os .bat fariam.

        .\PAINEL.ps1              abre em http://localhost:8099
        .\PAINEL.ps1 -Porta 9000  outra porta
        .\PAINEL.ps1 -Rede        aceita acesso de outras maquinas da rede
#>

[CmdletBinding()]
param(
    [int]    $Porta = 8099,
    [switch] $Rede,
    [string] $Config = "config.json",
    [switch] $SemNavegador
)

$ErrorActionPreference = "Stop"

# Um clique na janela preta poe o console em modo "Selecionar" e CONGELA o
# programa ate alguem apertar uma tecla. Painel congelado nao atende o
# navegador. Desliga a edicao rapida (QuickEdit) desta janela.
if ($env:OS -eq "Windows_NT") {
    try {
        Add-Type -Namespace GcTsePainel -Name JanelaConsole -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $entradaConsole = [GcTsePainel.JanelaConsole]::GetStdHandle(-10)
        [uint32] $modoConsole = 0
        if ([GcTsePainel.JanelaConsole]::GetConsoleMode($entradaConsole, [ref] $modoConsole)) {
            if (($modoConsole -band 0x40) -ne 0) { $modoConsole = $modoConsole - 0x40 }
            $modoConsole = $modoConsole -bor 0x80
            [void] [GcTsePainel.JanelaConsole]::SetConsoleMode($entradaConsole, $modoConsole)
        }
    } catch { }
}

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz

if (-not (Test-Path $Config)) {
    Write-Host "config.json nao encontrado nesta pasta." -ForegroundColor Red
    exit 1
}
$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
# A versao NAO e carimbada aqui. Ja foi, e ficou parada na 3.6 enquanto a
# coleta andava ate a 4.1 - o rodape do painel passou semanas dizendo um
# numero que nao existia mais. Dois lugares para a mesma verdade sempre
# acabam assim. Agora sai do VERSAO.txt, que e o mesmo que o gctse grava.
$Versao = "(versao nao encontrada)"
if (Test-Path "VERSAO.txt") {
    try {
        $linha = (Get-Content "VERSAO.txt" -Raw -ErrorAction Stop).Trim()
        if ($linha) { $Versao = ($linha -replace '^gctse versao\s*', '') }
    } catch { }
}
$PastaSaida = $cfg.pasta_saida
$ArquivoSelecao = $cfg.selecao.arquivo_selecao
$ArquivoSelecaoSenador = $null
foreach ($prop in $cfg.selecao.PSObject.Properties) {
    if ($prop.Name -eq "arquivo_selecao_senador") { $ArquivoSelecaoSenador = $prop.Value }
}

function Ler-Json {
    param([string] $Nome)
    $caminho = Join-Path $PastaSaida "$Nome.json"
    if (-not (Test-Path $caminho)) { return $null }
    try { return (Get-Content $caminho -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}


# ------------------------------------------------------------ 2o turno (7.0)
#
# O painel do 2o turno escolhe, para cada tarja, a praca E o turno:
#   GOVERNADOR  SELECAO.txt            "sp:2t" (ao vivo) / "sp:1t" (1o turno)
#   SENADOR     SELECAO-SENADOR.txt    "rj" (o Senado so tem o 1o turno)
#   PRESIDENTE  SELECAO-PRESIDENTE.txt "2t" / "1t"
# As tarjas sao as mesmas de sempre: o coletor so troca DE ONDE vem o dado.
# Tudo o que o painel mostra vem de TARJAS/painel-dados.json, que o coletor
# grava a cada ciclo - o painel nao consulta o TSE.

function Tem-Propriedade {
    param($Objeto, [string] $Nome)
    if ($null -eq $Objeto) { return $false }
    foreach ($prop in $Objeto.PSObject.Properties) { if ($prop.Name -eq $Nome) { return $true } }
    return $false
}

$ArquivoSelecaoPresidente = "SELECAO-PRESIDENTE.txt"
if ((Tem-Propriedade $cfg "segundo_turno") -and (Tem-Propriedade $cfg.segundo_turno "arquivo_selecao_presidente")) {
    $ArquivoSelecaoPresidente = "$($cfg.segundo_turno.arquivo_selecao_presidente)"
}
$Utf8SemBom = New-Object System.Text.UTF8Encoding($false)

function Gravar-Texto {
    # sem BOM e sem quebra de linha extra: o coletor compara texto
    param([string] $Arquivo, [string] $Texto)
    [IO.File]::WriteAllText((Join-Path $Raiz $Arquivo), $Texto, $Utf8SemBom)
}

function Ler-Texto {
    param([string] $Arquivo)
    $c = Join-Path $Raiz $Arquivo
    if (-not (Test-Path $c)) { return "" }
    try { return (Get-Content $c -Raw -ErrorAction Stop).Trim().ToLower() } catch { return "" }
}

function Ler-Alertas {
    if (-not (Tem-Propriedade $cfg "alertas")) { return $null }
    return (Ler-Json ([IO.Path]::GetFileNameWithoutExtension($cfg.alertas.arquivo)))
}

function Nome-Da-Praca {
    param([string] $Uf)
    foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $Uf) { return $p.nome } }
    return $Uf.ToUpper()
}

function Uf-Valida {
    param([string] $Uf)
    foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $Uf) { return $true } }
    return $false
}

function Campo {
    # Le um campo que pode nao existir (JSON do coletor de outra versao).
    param($Objeto, [string] $Nome, $Padrao = $null)
    if (Tem-Propriedade $Objeto $Nome) { return $Objeto.$Nome }
    return $Padrao
}

$ConfirmarPadrao = $true
if (Tem-Propriedade $cfg.selecao "confirmar_antes") {
    $ConfirmarPadrao = [bool] $cfg.selecao.confirmar_antes
}

function Ler-Modo-Clique {
    # Dois cliques (previa -> COLOCAR NO AR) ou um clique (vai direto).
    # A escolha e do operador, no proprio painel, e o estado atual esta
    # escrito na tela - nao escondido no config.json.
    $m = Ler-Texto "MODO-CLIQUE.txt"
    if ($m -eq "direto") { return $false }
    if ($m -eq "previa") { return $true }
    return $ConfirmarPadrao
}

function Html-Seguro {
    param($Texto)
    if ($null -eq $Texto) { return "" }
    return ([string] $Texto).Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;")
}

function Classe-Selo {
    param([string] $Selo)
    if (-not $Selo) { return "" }
    if ($Selo -match 'SEGUNDO|2' -and $Selo -notmatch 'ELEIT') { return "selo2t" }
    return "seloeleito"
}

function Linha-Cand {
    # Uma linha de candidato: posicao, nome, partido, selo e percentual.
    param($C, [int] $Pos)
    if ($null -eq $C) { return "" }
    $selo = "$(Campo $C 'selo' '')"
    $tag = ""
    if ($selo) { $tag = "<span class='$(Classe-Selo $selo)'>$(Html-Seguro $selo)</span>" }
    return "<div class='cand'><span class='pos'>$Pos&ordm;</span>" +
           "<span class='nome'>$(Html-Seguro (Campo $C 'nome' ''))</span>" +
           "<span class='part'>$(Html-Seguro (Campo $C 'partido' ''))</span>$tag" +
           "<span class='pct'>$(Html-Seguro (Campo $C 'percentual' ''))</span></div>"
}

function Linhas-Resumo {
    param($R)
    if ($null -eq $R) { return "<p class='nada'>ainda sem boletim</p>" }
    $h = ""; $i = 0
    foreach ($c in @(Campo $R "candidatos" @())) { $i++; $h += Linha-Cand $c $i }
    if (-not $h) { $h = "<p class='nada'>sem candidato ainda</p>" }
    return $h
}

function Linhas-Tarja {
    # Os dois candidatos como estao NO ARQUIVO da tarja (o que o GC mostra).
    param($T)
    $h = ""
    foreach ($i in 1, 2) {
        if ("$(Campo $T "cand${i}_visivel" '0')" -ne "1") { continue }
        $c = [pscustomobject]@{ nome = (Campo $T "cand${i}_nome" ""); partido = (Campo $T "cand${i}_partido" "")
                                percentual = (Campo $T "cand${i}_percentual" ""); selo = (Campo $T "cand${i}_eleito" "") }
        $h += Linha-Cand $c $i
    }
    if (-not $h) { $h = "<p class='nada'>sem candidato ainda</p>" }
    return $h
}

function Estados-Do-Painel {
    # Os 27 estados, na ordem do config, com o que o coletor sabe de cada um.
    $d = Ler-Json "painel-dados"
    $lista = @()
    foreach ($p in $cfg.selecao.pracas) {
        $e = $null
        if ($null -ne $d -and (Tem-Propriedade $d "estados") -and (Tem-Propriedade $d.estados $p.uf)) { $e = $d.estados.($p.uf) }
        $sit = "$(Campo $e 'situacao_1t' '')"
        $g2 = Campo $e "gov_2t"
        $eleito2t = $false
        if ($null -ne $g2) { foreach ($c in @(Campo $g2 "candidatos" @())) { if ("$(Campo $c 'eleito' 0)" -eq "1") { $eleito2t = $true } } }
        $lista += [pscustomobject]@{
            uf = $p.uf; nome = $p.nome; sit = $sit
            g1 = (Campo $e "gov_1t"); g2 = $g2; sen = (Campo $e "senador"); eleito2t = $eleito2t
        }
    }
    return $lista
}

# --------------------------------------------------------------- giro (7.0)
#
# Giro automatico na TARJA DE GOVERNADOR: o painel troca o SELECAO.txt de
# tempos em tempos. Fica na memoria do painel; fechar o painel para o giro
# (a tarja fica no ultimo estado). Clique manual num governador para o giro.

$script:Giro = $null
$GirosNomes = @{
    eleitos1t = "Eleitos no 1º turno"
    disputa   = "2º turno ao vivo"
    eleitos   = "Todos os eleitos (1º e 2º turno)"
    todos     = "Os 27 estados"
}

function Lista-Do-Giro {
    param([string] $Tipo)
    $itens = @()
    foreach ($e in (Estados-Do-Painel)) {
        switch ($Tipo) {
            "eleitos1t" { if ($e.sit -eq "eleito") { $itens += "$($e.uf):1t" } }
            "disputa"   { if ($e.sit -eq "2t") { $itens += "$($e.uf):2t" } }
            "eleitos"   {
                if ($e.sit -eq "eleito") { $itens += "$($e.uf):1t" }
                elseif ($e.sit -eq "2t" -and $e.eleito2t) { $itens += "$($e.uf):2t" }
            }
            "todos"     { $itens += "$($e.uf)" }
        }
    }
    return ,$itens
}

function Tempo-Do-Giro {
    $t = 0
    [void] [int]::TryParse((Ler-Texto "GIRO-SEGUNDOS.txt"), [ref] $t)
    if ($t -lt 4 -or $t -gt 120) { $t = 10 }
    return $t
}

function Girar-Agora {
    # Chamado entre as requisicoes (a cada ~0,3 s). Quando vence o tempo,
    # poe o proximo estado da lista na tarja.
    if ($null -eq $script:Giro) { return }
    if ((Get-Date) -lt $script:Giro.proximo) { return }
    if ($script:Giro.i -ge $script:Giro.itens.Count) {
        # Fim da volta: refaz a lista (um 2o turno pode ter acabado de decidir).
        $script:Giro.itens = Lista-Do-Giro $script:Giro.tipo
        $script:Giro.i = 0
        $script:Giro.voltas++
        if ($script:Giro.itens.Count -eq 0) {
            Write-Host ("{0} giro parado: lista '{1}' vazia" -f (Get-Date -Format "HH:mm:ss"), $GirosNomes[$script:Giro.tipo])
            $script:Giro = $null; return
        }
    }
    $item = $script:Giro.itens[$script:Giro.i]
    try {
        Gravar-Texto $ArquivoSelecao $item
        $script:Giro.atual = $item
    } catch {
        Write-Host ("{0} FALHA no giro ao gravar {1}: {2}" -f (Get-Date -Format "HH:mm:ss"), $ArquivoSelecao, $_.Exception.Message) -ForegroundColor Red
    }
    $script:Giro.i++
    $script:Giro.proximo = (Get-Date).AddSeconds((Tempo-Do-Giro))
}

function Parar-Giro {
    param([string] $Motivo)
    if ($null -eq $script:Giro) { return }
    $script:Giro = $null
    Write-Host ("{0} giro PARADO ({1})" -f (Get-Date -Format "HH:mm:ss"), $Motivo)
}

# ------------------------------------------------------------------- pagina

function Rotulo-Turno {
    param($Turno)
    if ("$Turno" -eq "1") { return "1º turno" }
    return "2º turno ao vivo"
}

function Montar-Pagina {
    $ConfirmarAntes = Ler-Modo-Clique
    $dados = Ler-Json "painel-dados"
    $al = Ler-Alertas
    $estados = Estados-Do-Painel

    # O que esta no ar, segundo o coletor (ja com o turno resolvido).
    $noAr = Campo $dados "no_ar"
    $ufGov = "$(Campo (Campo $noAr 'governador') 'uf' '')"
    $tGov = "$(Campo (Campo $noAr 'governador') 'turno' '')"
    $ufSen = "$(Campo (Campo $noAr 'senador') 'uf' '')"
    $tPres = "$(Campo (Campo $noAr 'presidente') 'turno' '2')"
    if (-not $ufGov) { $ufGov = (Ler-Texto $ArquivoSelecao) -replace ':.*$', '' }
    if (-not $ufSen) { $ufSen = (Ler-Texto $ArquivoSelecaoSenador) -replace ':.*$', '' }

    # Previas pendentes (modo 2 cliques)
    $prevGov = Ler-Texto "PREVIA.txt"
    $prevSen = Ler-Texto "PREVIA-SENADOR.txt"
    $prevPres = Ler-Texto "PREVIA-PRESIDENTE.txt"

    # --- como o clique funciona, escrito na tela
    if ($ConfirmarAntes) {
        $explicaClique = "<span class='comoclique dois'>Clique monta a <b>prévia</b>; a tarja só muda no <b>COLOCAR NO AR</b>.</span>" +
                         "<a class='trocaclique' href='/modoclique?m=direto'>passar para 1 clique</a>"
    } else {
        $explicaClique = "<span class='comoclique um'>Clique coloca <b>direto no ar</b>, sem confirmação.</span>" +
                         "<a class='trocaclique' href='/modoclique?m=previa'>passar para 2 cliques</a>"
    }

    # --- NO AR AGORA: o que esta nos tres arquivos
    $cardsAr = ""
    foreach ($t in @(@("tarja-presidente", "PRESIDENTE"), @("tarja-governador", "GOVERNADOR"), @("tarja-senador", "SENADOR"))) {
        $d = Ler-Json $t[0]
        if ($null -eq $d) { $cardsAr += "<div class='card vazio'><h3>$($t[1])</h3><p class='nada'>arquivo ainda não gerado</p></div>"; continue }
        $turnoTxt = ""
        if ($t[0] -eq "tarja-presidente") { $turnoTxt = Rotulo-Turno $tPres }
        elseif ($t[0] -eq "tarja-governador" -and $tGov) { $turnoTxt = Rotulo-Turno $tGov }
        elseif ($t[0] -eq "tarja-senador") { $turnoTxt = "1º turno" }
        $clsT = "t2"; if ($turnoTxt -like "1*") { $clsT = "t1" }
        $selo = ""; if ("$(Campo $d 'selo' '')") { $selo = "<span class='selo'>$(Html-Seguro $d.selo)</span>" }
        $cardsAr += "<div class='card noar'><h3>$($t[1]) <span class='turno $clsT'>$turnoTxt</span> $selo</h3>" +
                    "<div class='praca'>$(Html-Seguro (Campo $d 'abrangencia' ''))" +
                    "<span class='urnas'>$(Html-Seguro (Campo $d 'apuracao_pct' '')) das urnas</span></div>$(Linhas-Tarja $d)</div>"
    }

    # --- PREVIA pendente
    $blocoPrevia = ""
    if ($ConfirmarAntes -and ($prevGov -or $prevSen -or $prevPres)) {
        $cartoes = ""
        if ($prevPres) {
            $tp = 2; if ($prevPres -match '^1') { $tp = 1 }
            $r = Campo $dados "presidente_$($tp)t"
            $cartoes += "<div class='card previa'><h3>PRESIDENTE <span class='turno t$tp'>$(Rotulo-Turno $tp)</span></h3>" +
                        "<div class='praca'>BRASIL<span class='urnas'>$(Html-Seguro (Campo $r 'urnas' '')) das urnas</span></div>$(Linhas-Resumo $r)</div>"
        }
        if ($prevGov) {
            $ufP = $prevGov -replace ':.*$', ''
            $e = $estados | Where-Object { $_.uf -eq $ufP } | Select-Object -First 1
            $tp = 2; if ($prevGov -match ':1t$' -or ($null -ne $e -and $e.sit -eq "eleito")) { $tp = 1 }
            $r = $null; if ($null -ne $e) { if ($tp -eq 1) { $r = $e.g1 } else { $r = $e.g2 } }
            $cartoes += "<div class='card previa'><h3>GOVERNADOR <span class='turno t$tp'>$(Rotulo-Turno $tp)</span></h3>" +
                        "<div class='praca'>$(Html-Seguro (Nome-Da-Praca $ufP))<span class='urnas'>$(Html-Seguro (Campo $r 'urnas' '')) das urnas</span></div>$(Linhas-Resumo $r)</div>"
        }
        if ($prevSen) {
            $e = $estados | Where-Object { $_.uf -eq $prevSen } | Select-Object -First 1
            $r = $null; if ($null -ne $e) { $r = $e.sen }
            $cartoes += "<div class='card previa'><h3>SENADOR <span class='turno t1'>1º turno</span></h3>" +
                        "<div class='praca'>$(Html-Seguro (Nome-Da-Praca $prevSen))</div>$(Linhas-Resumo $r)</div>"
        }
        $blocoPrevia = "<section class='blocoprevia'><h2>Prévia &middot; entra no ar quando você aprovar</h2>" +
                       "<div class='cards'>$cartoes</div><p class='acoes'><a class='aprovar' href='/aprovar'>COLOCAR NO AR</a>" +
                       "<a class='descartar' href='/descartar'>descartar</a></p></section>"
    }

    # --- ABA GOVERNADOR
    $giroHtml = ""
    $tempoGiro = Tempo-Do-Giro
    if ($null -ne $script:Giro) {
        $faltam = [int] [math]::Max(0, ($script:Giro.proximo - (Get-Date)).TotalSeconds)
        $atual = "$($script:Giro.atual)" -replace ':.*$', ''
        $giroHtml = "<div class='giro ativo'><b>GIRO NA TARJA DE GOVERNADOR</b> &middot; $(Html-Seguro $GirosNomes[$script:Giro.tipo]) &middot; " +
                    "no ar: <b>$(Html-Seguro (Nome-Da-Praca $atual))</b> ($($script:Giro.i) de $($script:Giro.itens.Count)) &middot; próximo em ${faltam}s" +
                    "<a class='parar' href='/giro?parar=1'>PARAR O GIRO</a></div>"
    } else {
        $botoesGiro = ""
        foreach ($k in @("eleitos1t", "disputa", "eleitos", "todos")) {
            $n = (Lista-Do-Giro $k).Count
            $cls = "gbtn"; $rota = "/giro?lista=$k"
            if ($n -eq 0) { $cls = "gbtn off"; $rota = "/" }
            $botoesGiro += "<a class='$cls' href='$rota'>$(Html-Seguro $GirosNomes[$k]) <i>$n</i></a>"
        }
        $giroHtml = "<div class='giro'><b>GIRAR NA TARJA</b>$botoesGiro</div>"
    }
    $tempos = ""
    foreach ($s in 6, 8, 10, 15, 20) {
        $cls = "tbtn"; if ($s -eq $tempoGiro) { $cls = "tbtn on" }
        $tempos += "<a class='$cls' href='/girotempo?s=$s'>${s}s</a>"
    }
    $giroHtml += "<div class='tempos'>cada estado fica <span>$tempos</span> no ar durante o giro</div>"

    $cards2t = ""; $cards1t = ""; $cardsSem = ""
    $n2 = 0; $n1 = 0; $ns = 0
    foreach ($e in $estados) {
        $novo = $false
        if ($null -ne $al -and (Tem-Propriedade $al "estados") -and (Tem-Propriedade $al.estados $e.uf)) {
            if ($al.estados.($e.uf).governador) { $novo = $true }
        }
        $noArAqui = ($e.uf -eq $ufGov)
        $naPrevia = ($prevGov -and (($prevGov -replace ':.*$', '') -eq $e.uf))
        if ($e.sit -eq "2t") {
            $n2++
            $cls = "uf disputa"
            if ($noArAqui) { $cls += " ar" }
            if ($novo) { $cls += " novo" }
            if ($e.eleito2t) { $cls += " decidido" }
            $urn = Campo $e.g2 "urnas" ""
            $marca = ""
            if ($noArAqui) { $marca = "<u class='m-ar'>NO AR &middot; $(Rotulo-Turno $tGov)</u>" }
            elseif ($naPrevia) { $marca = "<u class='m-prev'>na prévia</u>" }
            elseif ($novo) { $marca = "<u class='m-novo'>boletim novo</u>" }
            $b2 = "b2"; $b1 = "b1"
            if ($noArAqui -and $tGov -eq "2") { $b2 += " on" }
            if ($noArAqui -and $tGov -eq "1") { $b1 += " on" }
            $cards2t += "<div class='$cls'><div class='uftopo'><b>$(Html-Seguro $e.nome)</b><span class='urnas'>$(Html-Seguro $urn) urnas</span></div>" +
                        "$marca$(Linhas-Resumo $e.g2)" +
                        "<div class='botoes'><a class='$b2' href='/gov?uf=$($e.uf)&t=2'>2º TURNO AO VIVO</a>" +
                        "<a class='$b1' href='/gov?uf=$($e.uf)&t=1'>1º TURNO</a></div></div>`n"
        } elseif ($e.sit -eq "eleito") {
            $n1++
            $cls = "uf eleito1t"
            if ($noArAqui) { $cls += " ar" }
            $marca = "<u class='m-e1'>ELEITO NO 1º TURNO</u>"
            if ($noArAqui) { $marca = "<u class='m-ar'>NO AR &middot; 1º turno</u>" }
            elseif ($naPrevia) { $marca = "<u class='m-prev'>na prévia</u>" }
            $cands = @(Campo $e.g1 "candidatos" @())
            $l1 = ""; $l2 = ""
            if ($cands.Count -ge 1) {
                $l1 = "<div class='venc'><span class='nome'>$(Html-Seguro $cands[0].nome)</span><span class='part'>$(Html-Seguro $cands[0].partido)</span><span class='pct'>$(Html-Seguro $cands[0].percentual)</span></div>"
            }
            if ($cands.Count -ge 2) {
                $l2 = "<div class='vice'><span class='pos'>2º</span><span class='nome'>$(Html-Seguro $cands[1].nome)</span><span class='part'>$(Html-Seguro $cands[1].partido)</span><span class='pct'>$(Html-Seguro $cands[1].percentual)</span></div>"
            }
            $cards1t += "<a class='$cls' href='/gov?uf=$($e.uf)&t=1'><div class='uftopo'><b>$(Html-Seguro $e.nome)</b></div>$marca$l1$l2</a>`n"
        } else {
            $ns++
            $cls = "uf semdado"; if ($noArAqui) { $cls += " ar" }
            $cardsSem += "<a class='$cls' href='/gov?uf=$($e.uf)'><div class='uftopo'><b>$(Html-Seguro $e.nome)</b></div><u>aguardando o 1º turno</u></a>`n"
        }
    }
    $abaGov = "$giroHtml<h2 class='h2t'>2º TURNO &middot; apuração ao vivo <em>$n2 estados</em></h2>"
    if ($n2 -gt 0) { $abaGov += "<div class='grade'>$cards2t</div>" } else { $abaGov += "<p class='nada'>nenhum estado com 2º turno identificado ainda</p>" }
    $abaGov += "<h2 class='h1t'>ELEITOS NO 1º TURNO <em>$n1 estados</em></h2>"
    if ($n1 -gt 0) { $abaGov += "<div class='grade'>$cards1t</div>" } else { $abaGov += "<p class='nada'>o resultado do 1º turno ainda não foi lido</p>" }
    if ($ns -gt 0) {
        $abaGov += "<h2>SEM O RESULTADO DO 1º TURNO <em>$ns estados</em></h2><p class='nada'>A coleta ainda não leu o 1º turno destes estados " +
                   "(ou o TSE não respondeu). Clicar põe o estado no ar no modo automático.</p><div class='grade'>$cardsSem</div>"
    }

    # --- ABA PRESIDENTE
    $p2 = Campo $dados "presidente_2t"; $p1 = Campo $dados "presidente_1t"
    $novoPres = ""
    if ($null -ne $al -and (Tem-Propriedade $al "presidente") -and $al.presidente) {
        $novoPres = "<span class='badge'>BOLETIM NOVO</span><a class='visto' href='/visto?chave=br-1'>marcar como exibido</a>"
    }
    $c2 = "card pres"; $c1 = "card pres"
    if ($tPres -eq "2") { $c2 += " ar" } else { $c1 += " ar" }
    $m2 = ""; $m1 = ""
    if ($tPres -eq "2") { $m2 = "<u class='m-ar'>NO AR</u>" } else { $m1 = "<u class='m-ar'>NO AR</u>" }
    if ($prevPres -match '^2') { $m2 += "<u class='m-prev'>na prévia</u>" } elseif ($prevPres -match '^1') { $m1 += "<u class='m-prev'>na prévia</u>" }
    $abaPres = "<div class='cards dois'>" +
        "<div class='$c2'><h3>PRESIDENTE &middot; 2º TURNO AO VIVO $novoPres</h3>$m2<div class='praca'>BRASIL<span class='urnas'>$(Html-Seguro (Campo $p2 'urnas' '')) das urnas</span></div>" +
        "$(Linhas-Resumo $p2)<p class='acoes'><a class='b2 grande' href='/pres?t=2'>2º TURNO AO VIVO NA TARJA</a></p></div>" +
        "<div class='$c1'><h3>PRESIDENTE &middot; RESULTADO DO 1º TURNO</h3>$m1<div class='praca'>BRASIL<span class='urnas'>$(Html-Seguro (Campo $p1 'urnas' '')) das urnas</span></div>" +
        "$(Linhas-Resumo $p1)<p class='acoes'><a class='b1 grande' href='/pres?t=1'>1º TURNO NA TARJA</a></p></div></div>"

    # --- ABA SENADOR
    $cardsSen = ""
    foreach ($e in $estados) {
        $cls = "uf sen"; if ($e.uf -eq $ufSen) { $cls += " ar" }
        $marca = ""
        if ($e.uf -eq $ufSen) { $marca = "<u class='m-ar'>NO AR</u>" }
        elseif ($prevSen -eq $e.uf) { $marca = "<u class='m-prev'>na prévia</u>" }
        $lin = ""
        $i = 0
        foreach ($c in @(Campo $e.sen "candidatos" @())) {
            $i++
            $lin += "<div class='vice'><span class='pos'>$i&ordm;</span><span class='nome'>$(Html-Seguro $c.nome)</span><span class='part'>$(Html-Seguro $c.partido)</span><span class='pct'>$(Html-Seguro $c.percentual)</span></div>"
        }
        if (-not $lin) { $lin = "<p class='nada'>sem dado</p>" }
        $cardsSen += "<a class='$cls' href='/sen?uf=$($e.uf)'><div class='uftopo'><b>$(Html-Seguro $e.nome)</b></div>$marca$lin</a>`n"
    }
    $abaSen = "<p class='nota'>Senado não tem 2º turno: a tarja de senador mostra o resultado do 1º turno (os dois mais votados ficam com as vagas).</p><div class='grade'>$cardsSen</div>"

    # --- avisos do alto da tela
    $congelado = Test-Path (Join-Path $Raiz "CONGELADO.txt")
    $congeladoAviso = ""
    $rotuloCongelar = "CONGELAR AS TARJAS"
    if ($congelado) {
        $desde = ""
        try { $desde = (Get-Content (Join-Path $Raiz "CONGELADO.txt") -Raw).Trim() } catch { }
        $congeladoAviso = "<div class='congelado'><span>TARJAS CONGELADAS desde <b>$desde</b>. Os números no ar estão parados de propósito. " +
                          "A coleta continua por trás - ao descongelar, entra o número mais novo.</span></div>"
        $rotuloCongelar = "DESCONGELAR"
    }

    $paradoAviso = ""
    $placar = ""
    $intervaloCfg = 20
    if (Tem-Propriedade $cfg "intervalo_segundos") { $intervaloCfg = [int] $cfg.intervalo_segundos }
    $limiteIdade = 3 * $intervaloCfg + 15
    $arqBatida = Join-Path $PastaSaida "coleta.json"
    if (-not (Test-Path $arqBatida)) {
        $paradoAviso = "<div class='parado'><span>A coleta ainda não rodou nenhum ciclo. Abra o <b>INICIAR.bat</b> e deixe a janela aberta. " +
                       "Enquanto isso as tarjas não têm dado nenhum.</span></div>"
    } else {
        $idade = [int] ((Get-Date) - (Get-Item $arqBatida).LastWriteTime).TotalSeconds
        try {
            $bat = Get-Content $arqBatida -Raw -Encoding UTF8 | ConvertFrom-Json
            $qtd = [int] (Campo $bat "mudancas_total" 0)
            $ciclos = [int] (Campo $bat "ciclo" 0)
            $desde = ""
            if ([int] (Campo $bat "segundos_sem_mudanca" -1) -ge 0) { $desde = " &middot; última há $([int] $bat.segundos_sem_mudanca)s" }
            $classe = "placar"
            $frase = "<b>$qtd</b> números novos do TSE em $ciclos ciclos$desde"
            if ($qtd -eq 0 -and $ciclos -gt 3) {
                $classe = "placar quieto"
                $frase = "<b>nenhum número novo</b> em $ciclos ciclos - a coleta está viva, mas o TSE não mudou nada ainda"
            }
            $placar = "<div class='$classe'><span>$frase</span></div>"
            if ((Tem-Propriedade $bat "recebendo_tse") -and ($bat.recebendo_tse -eq $false)) {
                $ultimoTse = "nenhum dado do TSE chegou desde que a coleta abriu - as tarjas estão VAZIAS"
                if ("$(Campo $bat 'ultimo_dado_tse' '')") {
                    $ultimoTse = "último dado recebido às <b>$(Html-Seguro "$($bat.ultimo_dado_tse)")</b> - as tarjas estão PARADAS nesse dado"
                }
                $motivoTse = ""
                if ("$(Campo $bat 'motivo_sem_tse' '')") { $motivoTse = "<br><small>último erro: $(Html-Seguro "$($bat.motivo_sem_tse)")</small>" }
                $paradoAviso = "<div class='parado'><span><b>NÃO ESTAMOS RECEBENDO DADOS DO TSE.</b> $ultimoTse. " +
                               "A coleta continua tentando sozinha. Rode o <b>DIAGNOSTICO-OFICIAL.bat</b>.$motivoTse</span></div>"
            }
        } catch { }
        if ($idade -gt $limiteIdade) {
            $paradoAviso = "<div class='parado'><span>A COLETA PAROU. O último ciclo fechou há <b>$idade segundos</b> (o normal é no máximo $limiteIdade). " +
                           "Os números no ar estão CONGELADOS. Verifique a janela do INICIAR e reabra se estiver fechada. " +
                           "Se o título dela começa com <b>Selecionar</b>, alguém clicou nela: clique na janela e aperte <b>ESC</b>.</span></div>"
        }
    }
    $semDados = ""
    if ($null -eq $dados) {
        $semDados = "<div class='alerta'>O painel ainda não recebeu o <b>painel-dados.json</b> da coleta. Confira se o INICIAR.bat é da versão 7.0 " +
                    "e espere o primeiro ciclo fechar.</div>"
    }

    $pendente = ""
    if ($ConfirmarAntes -and ($prevGov -or $prevSen -or $prevPres)) {
        $pendente = "<div class='pendente'><span>Há escolha só na <b>PRÉVIA</b> - ainda NÃO está no ar. Clique em <b>COLOCAR NO AR</b> para trocar a tarja.</span></div>"
    }

    $nomeGov = Nome-Da-Praca $ufGov
    $nomeSen = Nome-Da-Praca $ufSen
    $turnoGovTxt = ""; if ($tGov) { $turnoGovTxt = " &middot; " + (Rotulo-Turno $tGov) }

    return @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<noscript><meta http-equiv="refresh" content="5"></noscript>
<title>Tarjas - 2º turno</title><style>
/* Fontes do sistema de proposito: a maquina do GC pode nao ter internet
   liberada alem do TSE. */
:root{
  --fundo:#f3f5f9; --papel:#ffffff; --papel2:#eef2f8;
  --tinta:#0f1a2c; --tinta2:#475872; --tinta3:#7d8ca3; --fio:#e2e8f1;
  --azul:#1d5aa8; --azul-claro:#e9f1fc; --azul-borda:#b9d3f0;
  --verde:#0b7a3b; --verde-claro:#e6f5ec; --verde-borda:#9fd6b5;
  --cinza:#5b6b82; --cinza-claro:#eef1f6; --cinza-borda:#c9d2df;
  --ambar:#a8650a; --ambar-claro:#fff3e0; --ambar-borda:#f0cf9c;
  --verm:#c22a2a;
  --sombra:0 1px 2px rgba(15,26,44,.05), 0 6px 16px -6px rgba(15,26,44,.10);
}
*{box-sizing:border-box}
body{margin:0;background:var(--fundo);color:var(--tinta);font:14.5px/1.5 "Segoe UI",system-ui,sans-serif}
a{color:inherit}
header{position:sticky;top:0;z-index:5;background:#0f1a2c;color:#fff;padding:10px 24px;display:flex;align-items:center;gap:18px;flex-wrap:wrap}
.marca h1{margin:0;font-size:16px;font-weight:700;letter-spacing:.02em}
.marca span{font-size:11px;color:#9fb3cf;letter-spacing:.12em}
.resumo{margin-left:auto;display:flex;gap:20px;align-items:center;flex-wrap:wrap}
.res{line-height:1.25}
.res u{display:block;text-decoration:none;font-size:10px;letter-spacing:.12em;color:#9fb3cf;font-weight:700}
.res b{font-size:14px}
.hora{font-variant-numeric:tabular-nums;font-size:20px;font-weight:800;padding-left:18px;border-left:1px solid #2c3d58}
main{padding:18px 24px 60px;max-width:1600px;margin:0 auto}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.12em;color:var(--tinta3);font-weight:800;margin:26px 0 10px;display:flex;align-items:center;gap:10px}
h2 em{font-style:normal;font-size:11px;background:var(--papel2);border-radius:999px;padding:2px 9px;color:var(--tinta2)}
h2::after{content:"";flex:1;height:1px;background:var(--fio)}
h2.h2t{color:var(--azul)} h2.h1t{color:var(--verde)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px}
.cards.dois{grid-template-columns:repeat(auto-fit,minmax(380px,1fr))}
.card{background:var(--papel);border:1px solid var(--fio);border-radius:12px;padding:14px 16px;box-shadow:var(--sombra)}
.card h3{margin:0 0 8px;font-size:11px;letter-spacing:.1em;color:var(--tinta3);font-weight:800;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.card.noar{border-top:4px solid var(--verm)}
.card.previa{border:2px dashed var(--ambar)}
.card.pres.ar{border:2px solid var(--verm)}
.praca{font-size:19px;font-weight:700;margin-bottom:6px;display:flex;align-items:baseline;gap:10px}
.urnas{font-size:12px;font-weight:600;color:var(--tinta2);margin-left:auto;white-space:nowrap;background:var(--papel2);padding:2px 9px;border-radius:999px}
.cand,.venc,.vice{display:flex;align-items:center;gap:8px;padding:5px 0;border-top:1px solid var(--fio)}
.pos{color:var(--tinta3);font-weight:700;font-size:12px;width:22px}
.nome{font-weight:650;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0}
.part{color:var(--tinta2);font-size:11px;font-weight:700;background:var(--papel2);padding:1px 6px;border-radius:4px}
.pct{margin-left:auto;font-weight:800;font-size:16px;font-variant-numeric:tabular-nums}
.seloeleito{background:var(--verde);color:#fff;border-radius:4px;padding:1px 6px;font-size:10.5px;font-weight:800;white-space:nowrap}
.selo2t{background:var(--azul);color:#fff;border-radius:4px;padding:1px 6px;font-size:10.5px;font-weight:800;white-space:nowrap}
.selo{background:var(--ambar-claro);color:var(--ambar);border:1px solid var(--ambar-borda);font-size:10px;padding:1px 7px;border-radius:999px}
.turno{font-size:10.5px;font-weight:800;letter-spacing:.06em;padding:2px 8px;border-radius:999px;color:#fff}
.turno.t2{background:var(--azul)} .turno.t1{background:var(--verde)}
.nada{color:var(--tinta3);font-size:13px;margin:6px 0}
.nota{color:var(--tinta2);font-size:13px;margin:0 0 12px}
/* abas */
.abas{display:flex;gap:6px;margin:22px 0 4px;border-bottom:2px solid var(--fio)}
.abas button{font:inherit;font-size:13px;font-weight:800;letter-spacing:.06em;border:0;background:none;padding:10px 18px;color:var(--tinta2);cursor:pointer;border-bottom:3px solid transparent;margin-bottom:-2px}
.abas button.on{color:var(--azul);border-bottom-color:var(--azul)}
.aba{display:none} .aba.on{display:block}
/* grade de estados */
.grade{display:grid;grid-template-columns:repeat(auto-fill,minmax(262px,1fr));gap:10px}
.uf{display:block;position:relative;background:var(--papel);border:1px solid var(--fio);border-radius:10px;padding:10px 12px;box-shadow:var(--sombra);text-decoration:none}
.uftopo{display:flex;align-items:baseline;gap:8px;margin-bottom:4px}
.uftopo b{font-size:14px}
.uf u,u.m-ar,u.m-prev,u.m-novo,u.m-e1{display:inline-block;text-decoration:none;font-size:10px;font-weight:800;letter-spacing:.08em;border-radius:4px;padding:1px 6px;margin:0 6px 4px 0}
.uf .cand .nome,.uf .venc .nome,.uf .vice .nome{font-size:13px}
.uf .pct{font-size:14px}
.uf.disputa{background:var(--cinza-claro);border-color:var(--cinza-borda);border-left:5px solid var(--azul)}
.uf.disputa.decidido{border-left-color:var(--verde)}
.uf.eleito1t{background:var(--verde-claro);border-color:var(--verde-borda);border-left:5px solid var(--verde)}
.uf.eleito1t:hover,.uf.sen:hover,.uf.semdado:hover{border-color:var(--azul)}
.uf.eleito1t .venc .nome{font-size:14px;font-weight:800;color:var(--verde)}
.uf.eleito1t .vice{color:var(--tinta2)} .uf.eleito1t .vice .pct{font-size:13px;font-weight:700}
.uf.semdado{border-style:dashed}
.uf.ar{outline:3px solid var(--verm);outline-offset:-1px}
.uf.novo{box-shadow:0 0 0 3px var(--ambar-borda)}
.m-ar{background:var(--verm);color:#fff}
.m-prev{background:var(--ambar);color:#fff}
.m-novo{background:var(--ambar-claro);color:var(--ambar)}
.m-e1{background:var(--verde);color:#fff}
.botoes{display:flex;gap:6px;margin-top:8px}
.b2,.b1{flex:1;white-space:nowrap;text-align:center;text-decoration:none;font-size:10.5px;font-weight:800;letter-spacing:.04em;padding:7px 6px;border-radius:7px;border:1px solid}
.b2{color:var(--azul);border-color:var(--azul-borda);background:#fff}
.b1{color:var(--verde);border-color:var(--verde-borda);background:#fff}
.b2.on{background:var(--azul);color:#fff} .b1.on{background:var(--verde);color:#fff}
.grande{display:inline-block;flex:none;padding:11px 22px;font-size:13px}
.acoes{margin:12px 0 0;display:flex;gap:14px;align-items:center}
.aprovar{display:inline-block;padding:12px 28px;border-radius:9px;background:var(--verde);color:#fff;font-size:15px;font-weight:800;text-decoration:none}
.descartar{color:var(--tinta2);font-size:13px}
/* giro */
.giro{display:flex;gap:8px;align-items:center;flex-wrap:wrap;background:var(--papel);border:1px solid var(--fio);border-radius:10px;padding:10px 12px;margin-top:14px}
.giro b{font-size:11.5px;letter-spacing:.1em;color:var(--tinta2);margin-right:6px}
.giro.ativo{background:#fff4e5;border:2px solid var(--ambar);font-size:14px}
.gbtn{text-decoration:none;font-size:12.5px;font-weight:700;padding:6px 12px;border-radius:7px;border:1px solid var(--azul-borda);color:var(--azul);background:var(--azul-claro)}
.gbtn i{font-style:normal;background:#fff;border-radius:999px;padding:0 6px;margin-left:4px;font-size:11px}
.gbtn.off{opacity:.45;pointer-events:none}
.parar{margin-left:auto;background:var(--verm);color:#fff;text-decoration:none;font-weight:800;padding:8px 16px;border-radius:8px}
.tempos{font-size:12px;color:var(--tinta2);margin-top:6px}
.tbtn{text-decoration:none;font-size:11.5px;font-weight:700;padding:2px 8px;border-radius:5px;border:1px solid var(--fio);margin:0 2px;background:#fff}
.tbtn.on{background:var(--tinta);color:#fff}
/* avisos */
.parado{background:#fdecec;border:1px solid #e7a9a9;color:#8a1f1f;padding:12px 16px;border-radius:10px;margin-bottom:12px;font-weight:600}
.pendente{background:#fff5d9;border:2px solid #e8b931;color:#5c4405;padding:12px 16px;border-radius:10px;margin-bottom:12px}
.congelado{background:#eef2f7;border:1px solid #b9c6d6;color:#24405f;padding:12px 16px;border-radius:10px;margin-bottom:12px;font-weight:600}
.placar{background:#eef4fb;border:1px solid #c3d6ec;color:#1d5aa8;padding:9px 14px;border-radius:10px;margin-bottom:12px;font-size:13px}
.placar.quieto{background:#f4f4f4;color:#555;border-color:#ddd}
.alerta{background:#fff4ec;border:1px solid #f3c9a8;color:#8f4a12;padding:12px 16px;border-radius:10px;margin-bottom:12px}
.badge{background:var(--ambar);color:#fff;font-size:10px;padding:2px 8px;border-radius:999px}
.visto{font-size:10.5px;color:var(--azul)}
.barra{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:12px 0 0;font-size:13px}
.trocaclique{font-size:12.5px;color:var(--azul);text-decoration:none;border:1px solid var(--azul-borda);border-radius:7px;padding:4px 10px;background:#fff}
.btncongela{margin-left:auto;padding:8px 16px;border-radius:8px;border:1px solid #c3d0de;background:#fff;color:#24405f;font-size:12.5px;font-weight:800;text-decoration:none}
.btncongela.ativo{background:#24405f;color:#fff}
footer{color:var(--tinta3);font-size:12px;margin-top:30px;padding-top:12px;border-top:1px solid var(--fio)}
</style></head><body>
<header>
  <div class="marca"><h1>TARJAS &middot; 2º TURNO</h1><span>gctse $Versao</span></div>
  <div class="resumo">
    <div class="res"><u>Presidente</u><b>$(Rotulo-Turno $tPres)</b></div>
    <div class="res"><u>Governador</u><b>$(Html-Seguro $nomeGov)$turnoGovTxt</b></div>
    <div class="res"><u>Senador</u><b>$(Html-Seguro $nomeSen)</b></div>
    <div class="hora" id="hora">$(Get-Date -Format 'HH:mm:ss')</div>
  </div>
</header>
<main id="vivo">
$paradoAviso
$semDados
$congeladoAviso
$pendente
$placar
<h2>No ar agora &middot; o que está nos arquivos das tarjas</h2>
<div class="cards">$cardsAr</div>
<div class="barra">$explicaClique<a class="btncongela$(if ($congelado) { ' ativo' })" href="/congelar">$rotuloCongelar</a></div>
$blocoPrevia
<nav class="abas">
  <button data-aba="gov">GOVERNADOR</button>
  <button data-aba="pres">PRESIDENTE</button>
  <button data-aba="sen">SENADOR</button>
</nav>
<section class="aba" id="aba-gov">$abaGov</section>
<section class="aba" id="aba-pres">$abaPres</section>
<section class="aba" id="aba-sen">$abaSen</section>
<footer>Governador: <b>2º TURNO AO VIVO</b> mostra a apuração de agora; <b>1º TURNO</b> mostra o resultado de 4/10.
Estado decidido no 1º turno sai sempre com o resultado do 1º (selo ELEITO NO 1º TURNO e o 2º colocado).
As tarjas são as mesmas de sempre - nenhum campo mudou. A página se atualiza sozinha a cada 3 segundos.</footer>
</main>
<script>
(function () {
  var parado = false, CH = 'gctse-tarjas-aba';
  function aba() { var a = 'gov'; try { a = localStorage.getItem(CH) || 'gov'; } catch (e) { } return a; }
  function aplicarAba() {
    var a = aba();
    if (!document.getElementById('aba-' + a)) a = 'gov';
    Array.prototype.forEach.call(document.querySelectorAll('.abas button'), function (b) { b.className = b.getAttribute('data-aba') === a ? 'on' : ''; });
    Array.prototype.forEach.call(document.querySelectorAll('.aba'), function (s) { s.className = s.id === 'aba-' + a ? 'aba on' : 'aba'; });
  }
  function redesenhar(texto) {
    var doc = new DOMParser().parseFromString(texto, 'text/html');
    var novo = doc.getElementById('vivo'), cab = doc.querySelector('header');
    if (novo) { document.getElementById('vivo').innerHTML = novo.innerHTML; }
    if (cab) { document.querySelector('header').innerHTML = cab.innerHTML; }
    aplicarAba();
  }
  function buscar() {
    return fetch('/', { cache: 'no-store' }).then(function (r) { return r.text(); }).then(redesenhar);
  }
  document.addEventListener('click', function (ev) {
    var b = ev.target.closest ? ev.target.closest('.abas button') : null;
    if (b) { try { localStorage.setItem(CH, b.getAttribute('data-aba')); } catch (e) { } aplicarAba(); return; }
    var a = ev.target.closest ? ev.target.closest('a') : null;
    if (!a) { return; }
    var href = a.getAttribute('href') || '';
    if (href.charAt(0) !== '/') { return; }
    if (ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.button !== 0) { return; }
    ev.preventDefault();
    var y = window.scrollY;
    fetch(href, { cache: 'no-store' })
      .then(function () { return buscar(); })
      .then(function () { window.scrollTo(0, y); })
      .catch(function () { location.href = href; });
  });
  aplicarAba();
  setInterval(function () {
    if (parado) return;
    var y = window.scrollY;
    buscar().then(function () { window.scrollTo(0, y); }).catch(function () { parado = true; location.reload(); });
  }, 3000);
  setInterval(function () { var h = document.getElementById('hora'); if (h) h.textContent = new Date().toTimeString().slice(0, 8); }, 500);
})();
</script>
</body></html>
"@
}

function Abrir-Navegador {
    # CHROME primeiro (pedido da operacao); sem Chrome, o navegador padrao.
    param([string] $Url)
    foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                     "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                     "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            try { Start-Process -FilePath $c -ArgumentList @("--new-window", $Url); return } catch { }
        }
    }
    try { Start-Process $Url } catch { }
}

# ------------------------------------------------------------------ servidor

# O HttpListener casa pelo cabecalho Host: com prefixo "localhost", quem
# digita 127.0.0.1 leva 404. Registra os dois.
$prefixos = @("http://localhost:$Porta/", "http://127.0.0.1:$Porta/")
if ($Rede) { $prefixos = @("http://+:$Porta/") }
$prefixo = $prefixos[0]

$ouvinte = New-Object System.Net.HttpListener
foreach ($pfx in $prefixos) { $ouvinte.Prefixes.Add($pfx) }
try {
    $ouvinte.Start()
} catch {
    Write-Host ""
    Write-Host "Nao foi possivel abrir $prefixo" -ForegroundColor Red
    Write-Host $_.Exception.Message
    if ($Rede) {
        Write-Host ""
        Write-Host "Para aceitar acesso da rede, rode UMA VEZ como administrador:" -ForegroundColor Yellow
        Write-Host "  netsh http add urlacl url=http://+:$Porta/ user=Todos"
        Write-Host "(em Windows em ingles, user=Everyone)"
    } else {
        Write-Host "A porta $Porta pode estar em uso. Tente: .\PAINEL.ps1 -Porta 8100" -ForegroundColor Yellow
    }
    exit 1
}

Write-Host ""
Write-Host "  Painel das TARJAS (2o turno) no ar em http://localhost:$Porta" -ForegroundColor Green
if ($Rede) {
    Write-Host "  Da rede: http://<ip-desta-maquina>:$Porta" -ForegroundColor Green
}
Write-Host "  Ctrl+C encerra. A coleta continua rodando na outra janela."
Write-Host ""
if (-not $SemNavegador) { Abrir-Navegador "http://localhost:$Porta" }

function Responder-Volta {
    param($Resposta)
    $Resposta.StatusCode = 303; $Resposta.RedirectLocation = "/"; $Resposta.Close()
}

# Espera a proxima requisicao em fatias curtas: entre uma e outra o giro
# anda, sem precisar de outro processo nem de outra janela.
$pendenteCtx = $ouvinte.GetContextAsync()
while ($ouvinte.IsListening) {
    $ctx = $null
    try {
        if (-not $pendenteCtx.Wait(300)) { Girar-Agora; continue }
        $ctx = $pendenteCtx.Result
    } catch {
        Write-Host ("{0} FALHA na espera do painel: {1}" -f (Get-Date -Format "HH:mm:ss"), $_.Exception.Message) -ForegroundColor Red
    }
    $pendenteCtx = $ouvinte.GetContextAsync()
    if ($null -eq $ctx) { continue }
    $caminho = ""
    $resposta = $ctx.Response
    try {
        $caminho = $ctx.Request.Url.AbsolutePath
        $q = $ctx.Request.QueryString
        $hora = Get-Date -Format "HH:mm:ss"

        if ($caminho -eq "/modoclique") {
            $m = $q["m"]
            if ($m -in @("previa", "direto")) {
                Gravar-Texto "MODO-CLIQUE.txt" $m
                # Trocar para 1 clique com uma previa pendente deixaria na
                # tela um bloco de previa que nenhum botao mais aprova.
                if ($m -eq "direto") {
                    foreach ($arq in @("PREVIA.txt", "PREVIA-SENADOR.txt", "PREVIA-PRESIDENTE.txt")) {
                        Remove-Item (Join-Path $Raiz $arq) -Force -ErrorAction SilentlyContinue
                    }
                }
                Write-Host ("{0} modo do clique: {1}" -f $hora, $(if ($m -eq "direto") { "1 CLIQUE, direto ao ar" } else { "2 CLIQUES, com previa" }))
            }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/gov") {
            # Governador: estado + turno ("sp:2t", "sp:1t" ou "sp" = automatico).
            $uf = "$($q['uf'])".ToLower()
            $t = "$($q['t'])"
            if (Uf-Valida $uf) {
                $valor = $uf
                if ($t -eq "1" -or $t -eq "2") { $valor = "${uf}:${t}t" }
                if (Ler-Modo-Clique) {
                    Gravar-Texto "PREVIA.txt" $valor
                    Write-Host ("{0} previa GOVERNADOR: {1}" -f $hora, $valor.ToUpper())
                } else {
                    Parar-Giro "governador escolhido na mao"
                    Gravar-Texto $ArquivoSelecao $valor
                    Write-Host ("{0} GOVERNADOR NO AR: {1}" -f $hora, $valor.ToUpper())
                }
            }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/sen" -or $caminho -eq "/selecionar") {
            # /selecionar e o endereco antigo (um estado para as duas tarjas):
            # no 2o turno ele vale so para o senador e o governador automatico.
            $uf = "$($q['uf'])".ToLower()
            if ((Uf-Valida $uf) -and $ArquivoSelecaoSenador) {
                if ((Ler-Modo-Clique) -and $caminho -eq "/sen") {
                    Gravar-Texto "PREVIA-SENADOR.txt" $uf
                    Write-Host ("{0} previa SENADOR: {1}" -f $hora, $uf.ToUpper())
                } else {
                    Gravar-Texto $ArquivoSelecaoSenador $uf
                    if ($caminho -eq "/selecionar") { Parar-Giro "selecao antiga"; Gravar-Texto $ArquivoSelecao $uf }
                    Write-Host ("{0} SENADOR NO AR: {1}" -f $hora, $uf.ToUpper())
                }
            }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/pres") {
            $t = "$($q['t'])"
            if ($t -eq "1" -or $t -eq "2") {
                if (Ler-Modo-Clique) {
                    Gravar-Texto "PREVIA-PRESIDENTE.txt" "${t}t"
                    Write-Host ("{0} previa PRESIDENTE: {1}o turno" -f $hora, $t)
                } else {
                    Gravar-Texto $ArquivoSelecaoPresidente "${t}t"
                    Write-Host ("{0} PRESIDENTE NO AR: {1}o turno" -f $hora, $t)
                }
            }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/aprovar") {
            # Aqui, e so aqui, a previa vira o que esta no ar.
            foreach ($par in @(@("PREVIA.txt", $ArquivoSelecao), @("PREVIA-SENADOR.txt", $ArquivoSelecaoSenador),
                               @("PREVIA-PRESIDENTE.txt", $ArquivoSelecaoPresidente))) {
                if (-not $par[1]) { continue }
                $v = Ler-Texto $par[0]
                if ($v) {
                    if ($par[0] -eq "PREVIA.txt") { Parar-Giro "governador aprovado na mao" }
                    Gravar-Texto $par[1] $v
                    Write-Host ("{0} APROVADO em {1}: {2}" -f $hora, $par[1], $v.ToUpper())
                }
            }
            foreach ($arq in @("PREVIA.txt", "PREVIA-SENADOR.txt", "PREVIA-PRESIDENTE.txt")) {
                Remove-Item (Join-Path $Raiz $arq) -Force -ErrorAction SilentlyContinue
            }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/descartar") {
            foreach ($arq in @("PREVIA.txt", "PREVIA-SENADOR.txt", "PREVIA-PRESIDENTE.txt")) {
                Remove-Item (Join-Path $Raiz $arq) -Force -ErrorAction SilentlyContinue
            }
            Write-Host ("{0} previa descartada" -f $hora)
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/giro") {
            if ($q["parar"]) {
                Parar-Giro "botao PARAR"
            } else {
                $tipo = "$($q['lista'])"
                if ($GirosNomes.ContainsKey($tipo)) {
                    $itens = Lista-Do-Giro $tipo
                    if ($itens.Count -gt 0) {
                        $script:Giro = @{ tipo = $tipo; itens = $itens; i = 0; voltas = 0; atual = ""; proximo = (Get-Date).AddSeconds(-1) }
                        Write-Host ("{0} GIRO iniciado: {1} ({2} estados, {3}s cada)" -f $hora, $GirosNomes[$tipo], $itens.Count, (Tempo-Do-Giro))
                        Girar-Agora
                    }
                }
            }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/girotempo") {
            $s = 0
            if ([int]::TryParse("$($q['s'])", [ref] $s) -and $s -ge 4 -and $s -le 120) { Gravar-Texto "GIRO-SEGUNDOS.txt" "$s" }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/congelar") {
            # Arquivo-bandeira: o coletor olha a existencia dele a cada
            # publicacao. Um arquivo que existe ou nao existe nao tem como
            # falhar pela metade.
            $arqCong = Join-Path $Raiz "CONGELADO.txt"
            if (Test-Path $arqCong) {
                Remove-Item $arqCong -Force -ErrorAction SilentlyContinue
                Write-Host ("{0} tarjas DESCONGELADAS" -f $hora)
            } else {
                Gravar-Texto "CONGELADO.txt" (Get-Date -Format "dd/MM/yyyy HH:mm:ss")
                Write-Host ("{0} tarjas CONGELADAS" -f $hora)
            }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/visto") {
            # baixa de alerta: o coletor le e limpa na proxima volta
            $chave = "$($q['chave'])"
            if ($chave -match "^[a-z]{2}-\d{1,2}$") { Gravar-Texto "VISTO.txt" $chave }
            Responder-Volta $resposta; continue
        }

        if ($caminho -eq "/favicon.ico") { $resposta.StatusCode = 404; $resposta.Close(); continue }

        $html = Montar-Pagina
        $bytes = [Text.Encoding]::UTF8.GetBytes($html)
        $resposta.ContentType = "text/html; charset=utf-8"
        $resposta.ContentLength64 = $bytes.Length
        $resposta.OutputStream.Write($bytes, 0, $bytes.Length)
        $resposta.Close()
    } catch {
        # Uma requisicao malformada nao pode derrubar o painel. Mas engolir
        # em silencio e pior: se o clique de COLOCAR NO AR falhar (arquivo
        # preso, disco cheio), o operador ve a pagina voltar normalmente e
        # acredita que trocou. Por isso a falha aparece na janela do painel.
        Write-Host ("{0} FALHA ao atender {1}: {2}" -f (Get-Date -Format "HH:mm:ss"),
                    $caminho, $_.Exception.Message) -ForegroundColor Red
        try { $resposta.Close() } catch { }
    }
    Girar-Agora
}
