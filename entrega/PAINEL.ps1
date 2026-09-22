<#
    Painel web do gctse
    ------------------------------------------------------------------
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
    [string] $Config = "config.json"
)

$ErrorActionPreference = "Stop"
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

function Ler-Selecao {
    param([int] $Cargo = 3)
    $arq = $ArquivoSelecao
    if ($Cargo -eq 5 -and $ArquivoSelecaoSenador -and (Test-Path $ArquivoSelecaoSenador)) {
        $arq = $ArquivoSelecaoSenador
    }
    if (Test-Path $arq) {
        try { return (Get-Content $arq -Raw).Trim().ToLower() } catch { }
    }
    return $cfg.selecao.padrao
}

function Ler-Alertas {
    if (-not (Tem-Propriedade $cfg "alertas")) { return $null }
    return (Ler-Json ([IO.Path]::GetFileNameWithoutExtension($cfg.alertas.arquivo)))
}

function Ler-Previa {
    # A praca que o operador esta OLHANDO, que ainda nao foi para o ar. Fica
    # num arquivo separado do SELECAO: o coletor nao conhece este arquivo, e
    # por isso escolher praca aqui nao mexe em nada do que esta no ar.
    param([int] $Cargo = 3)
    $arq = Join-Path $Raiz "PREVIA.txt"
    if ($Cargo -eq 5) { $arq = Join-Path $Raiz "PREVIA-SENADOR.txt" }
    if (Test-Path $arq) {
        try {
            $lido = (Get-Content $arq -Raw -ErrorAction Stop).Trim().ToLower()
            if ($lido) { return $lido }
        } catch { }
    }
    return ""
}

function Nome-Da-Praca {
    param([string] $Uf)
    foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $Uf) { return $p.nome } }
    return $Uf.ToUpper()
}

function Previa-Da-Praca {
    # Monta a previa a partir da lista das 27 pracas, que o coletor ja grava
    # a cada varredura. Nao ha consulta nova ao TSE nem arquivo novo: o dado
    # para a previa ja esta no disco.
    param([string] $Uf, [int] $Cargo)
    $arquivo = "lista-governador"
    if ($Cargo -eq 5) { $arquivo = "lista-senador" }
    $lista = Ler-Json $arquivo
    if ($null -eq $lista -or -not (Tem-Propriedade $lista "pracas")) { return $null }
    $nome = Nome-Da-Praca $Uf
    foreach ($linha in $lista.pracas) {
        if ($linha.praca -eq $nome) { return $linha }
    }
    return $null
}

function Ler-Modo {
    # Qual tarja o clique afeta: ambos, so governador ou so senador.
    if (Test-Path "PAINEL-MODO.txt") {
        try {
            $m = (Get-Content "PAINEL-MODO.txt" -Raw).Trim().ToLower()
            if ($m -in @("ambos", "gov", "sen")) { return $m }
        } catch { }
    }
    return "ambos"
}

function Tem-Propriedade {
    param($Objeto, [string] $Nome)
    if ($null -eq $Objeto) { return $false }
    foreach ($prop in $Objeto.PSObject.Properties) { if ($prop.Name -eq $Nome) { return $true } }
    return $false
}

$ConfirmarPadrao = $true
if (Tem-Propriedade $cfg.selecao "confirmar_antes") {
    $ConfirmarPadrao = [bool] $cfg.selecao.confirmar_antes
}

function Ler-Modo-Clique {
    # Dois cliques (previa -> COLOCAR NO AR) ou um clique (vai direto).
    #
    # Existe porque a duvida "cliquei no estado e a tarja nao mudou" custou
    # uma janela de teste. Os dois cliques protegem o ar, mas quem nao
    # percebeu que sao dois fica olhando uma tarja parada achando que o
    # sistema quebrou. Agora a escolha e do operador, no proprio painel, e
    # o estado atual esta escrito na tela - nao escondido no config.json.
    if (Test-Path "MODO-CLIQUE.txt") {
        try {
            $m = (Get-Content "MODO-CLIQUE.txt" -Raw).Trim().ToLower()
            if ($m -eq "direto") { return $false }
            if ($m -eq "previa") { return $true }
        } catch { }
    }
    return $ConfirmarPadrao
}


function Html-Seguro {
    param($Texto)
    if ($null -eq $Texto) { return "" }
    return ([string] $Texto).Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;")
}

function Montar-Pagina {
    $ConfirmarAntes = Ler-Modo-Clique
    $modo = Ler-Modo
    $ufGov = Ler-Selecao 3
    $ufSen = Ler-Selecao 5
    $nomeGov = $ufGov.ToUpper(); $nomeSen = $ufSen.ToUpper()
    foreach ($p in $cfg.selecao.pracas) {
        if ($p.uf -eq $ufGov) { $nomeGov = $p.nome }
        if ($p.uf -eq $ufSen) { $nomeSen = $p.nome }
    }
    $al = Ler-Alertas

    # --- seletor de qual tarja o clique afeta
    $abas = ""
    foreach ($m in @(@("ambos","Governador + Senador"), @("gov","Só governador"), @("sen","Só senador"))) {
        $cls = "aba"
        if ($modo -eq $m[0]) { $cls = "aba on" }
        $abas += "<a class='$cls' href='/modo?m=$($m[0])'>$($m[1])</a>"
    }

    # Escrito na tela, em vez de implicito: o operador tem que saber o que o
    # proximo clique num estado vai fazer, ANTES de clicar.
    if ($ConfirmarAntes) {
        $explicaClique = "<span class='comoclique dois'>Clicar num estado monta a <b>prévia</b>. " +
                         "A tarja só muda depois do <b>COLOCAR NO AR</b>.</span>" +
                         "<a class='trocaclique' href='/modoclique?m=direto'>passar para 1 clique</a>"
    } else {
        $explicaClique = "<span class='comoclique um'>Clicar num estado coloca <b>direto no ar</b>. " +
                         "Não há confirmação.</span>" +
                         "<a class='trocaclique' href='/modoclique?m=previa'>passar para 2 cliques</a>"
    }

    $prevGov = Ler-Previa 3
    $prevSen = Ler-Previa 5

    # --- botoes de estado, com aviso de boletim novo
    $botoes = ""
    $qtdNovos = 0
    foreach ($p in $cfg.selecao.pracas) {
        $novoG = $false; $novoS = $false
        if ($null -ne $al -and (Tem-Propriedade $al.estados $p.uf)) {
            $e = $al.estados.($p.uf)
            if ($e.governador) { $novoG = $true }
            if ($e.senador) { $novoS = $true }
        }
        if ($novoG -or $novoS) { $qtdNovos++ }

        $classe = "btn"
        if ($p.uf -eq $ufGov -and $p.uf -eq $ufSen) { $classe = "btn ativo ambos" }
        elseif ($p.uf -eq $ufGov) { $classe = "btn ativo gov" }
        elseif ($p.uf -eq $ufSen) { $classe = "btn ativo sen" }
        if ($novoG -or $novoS) { $classe += " novo" }
        if ($ConfirmarAntes -and ($p.uf -eq $prevGov -or $p.uf -eq $prevSen)) { $classe += " previa" }

        $tags = ""
        if ($novoG) { $tags += "<em class='g'>GOV</em>" }
        if ($novoS) { $tags += "<em class='s'>SEN</em>" }
        if (-not $tags) { $tags = "<em class='vazio'>&nbsp;</em>" }

        $marca = ""
        if ($p.uf -eq $ufGov -and $p.uf -eq $ufSen) { $marca = "<u>no ar</u>" }
        elseif ($p.uf -eq $ufGov) { $marca = "<u>gov no ar</u>" }
        elseif ($p.uf -eq $ufSen) { $marca = "<u>sen no ar</u>" }
        if ($ConfirmarAntes -and -not $marca -and ($p.uf -eq $prevGov -or $p.uf -eq $prevSen)) {
            $marca = "<u class='p'>na prévia</u>"
        }

        $rota = "/selecionar?uf=$($p.uf)"
        if ($ConfirmarAntes) { $rota = "/previa?uf=$($p.uf)" }
        $botoes += "<a class='$classe' href='$rota'>" +
                   "<b>$(Html-Seguro $p.nome)</b><span class='tags'>$tags</span>$marca</a>`n"
    }

    # --- previa: o que entra no ar se voce aprovar
    $blocoPrevia = ""
    if ($ConfirmarAntes) {
        $cartoes = ""
        $temPendente = $false
        foreach ($par in @(@(3, "GOVERNADOR", $prevGov, $ufGov), @(5, "SENADOR", $prevSen, $ufSen))) {
            $cargoP = $par[0]; $rotuloP = $par[1]; $ufPrev = $par[2]; $ufAr = $par[3]
            if (-not $ufPrev) { continue }
            $nomePrev = Nome-Da-Praca $ufPrev
            $igual = ($ufPrev -eq $ufAr)
            if (-not $igual) { $temPendente = $true }
            $d = Previa-Da-Praca $ufPrev $cargoP
            $corpo = "<p class='nada'>ainda sem boletim para esta praça</p>"
            if ($null -ne $d -and $d.visivel -eq "1") {
                $corpo = "<div class='praca'>$(Html-Seguro $d.praca)" +
                         "<span class='urnas'>$(Html-Seguro $d.apuracao_pct) das urnas</span></div>"
                foreach ($k in 1, 2) {
                    $nm = $d."cand${k}_nome"
                    if (-not $nm) { continue }
                    $corpo += "<div class='cand'><span class='pos'>$k&ordm;</span>" +
                              "<span class='nome'>$(Html-Seguro $nm)</span>" +
                              "<span class='part'>$(Html-Seguro $d."cand${k}_partido")</span>" +
                              "<span class='pct'>$(Html-Seguro $d."cand${k}_percentual")</span></div>"
                }
            } elseif ($null -ne $d) {
                $corpo = "<div class='praca'>$(Html-Seguro $d.praca)</div>" +
                         "<p class='nada'>sem candidato ainda</p>"
            }
            $estado = "<span class='jaNoAr'>já está no ar</span>"
            if (-not $igual) { $estado = "<span class='vaiEntrar'>entra ao aprovar</span>" }
            $cartoes += "<div class='card previa'><h3>$rotuloP &middot; $(Html-Seguro $nomePrev) $estado</h3>$corpo</div>"
        }
        if ($cartoes) {
            $acao = ""
            if ($temPendente) {
                $acao = "<p class='acoes'><a class='aprovar' href='/aprovar'>COLOCAR NO AR</a>" +
                        "<a class='descartar' href='/descartar'>descartar</a></p>"
            } else {
                $acao = "<p class='acoes'><span class='semAcao'>nada pendente: a prévia é o que já está no ar</span>" +
                        "<a class='descartar' href='/descartar'>limpar prévia</a></p>"
            }
            $blocoPrevia = "<h2>Prévia &middot; o que entra no ar se você aprovar</h2>" +
                           "<div class='cards'>$cartoes</div>$acao"
        }
    }

    # --- presidente
    $pres = Ler-Json "tarja-presidente"
    $cardPres = "<div class='card vazio'><h3>Presidente</h3><p>arquivo ainda não gerado</p></div>"
    if ($null -ne $pres) {
        $novoPres = ""
        if ($null -ne $al -and $al.presidente) {
            $novoPres = "<span class='badge'>BOLETIM NOVO &middot; $(Html-Seguro $al.presidente.pct)</span>" +
                        "<a class='visto' href='/visto?chave=br-1'>marcar como exibido</a>"
        }
        $linhas = ""
        foreach ($i in 1, 2) {
            if ($pres."cand${i}_visivel" -ne "1") { continue }
            $linhas += "<div class='cand'><span class='pos'>$i&ordm;</span>" +
                       "<span class='nome'>$(Html-Seguro $pres."cand${i}_nome")</span>" +
                       "<span class='part'>$(Html-Seguro $pres."cand${i}_partido")</span>" +
                       "<span class='pct'>$(Html-Seguro $pres."cand${i}_percentual")</span></div>"
        }
        $selo = ""
        if ($pres.selo) { $selo = "<span class='selo'>$(Html-Seguro $pres.selo)</span>" }
        $cardPres = "<div class='card destaque'><h3>Presidente $selo $novoPres</h3>" +
                    "<div class='praca'>$(Html-Seguro $pres.abrangencia)" +
                    "<span class='urnas'>$(Html-Seguro $pres.apuracao_pct) das urnas</span></div>$linhas</div>"
    }

    # --- cartoes das tarjas no ar
    $cartoes = ""
    foreach ($t in @(@("tarja-governador","Governador no ar"), @("tarja-senador","Senador no ar"))) {
        $d = Ler-Json $t[0]
        if ($null -eq $d) {
            $cartoes += "<div class='card vazio'><h3>$($t[1])</h3><p>arquivo ainda não gerado</p></div>"
            continue
        }
        $linhas = ""
        foreach ($i in 1, 2) {
            if ($d."cand${i}_visivel" -ne "1") { continue }
            $linhas += "<div class='cand'><span class='pos'>$i&ordm;</span>" +
                       "<span class='nome'>$(Html-Seguro $d."cand${i}_nome")</span>" +
                       "<span class='part'>$(Html-Seguro $d."cand${i}_partido")</span>" +
                       "<span class='pct'>$(Html-Seguro $d."cand${i}_percentual")</span></div>"
        }
        if (-not $linhas) { $linhas = "<p class='nada'>sem candidato ainda</p>" }
        $selo = ""
        if ($d.selo) { $selo = "<span class='selo'>$(Html-Seguro $d.selo)</span>" }
        $cartoes += "<div class='card'><h3>$($t[1]) $selo</h3>" +
                    "<div class='praca'>$(Html-Seguro $d.abrangencia)" +
                    "<span class='urnas'>$(Html-Seguro $d.apuracao_pct) das urnas</span></div>$linhas</div>"
    }

    # --- a coleta ainda esta viva?
    # Este e o aviso mais importante da tela. Sem ele, um coletor morto deixa
    # numeros plausiveis e CONGELADOS no ar, e ninguem percebe.
    # --- tarjas congeladas
    $congelado = Test-Path (Join-Path $Raiz "CONGELADO.txt")
    $congeladoAviso = ""
    $rotuloCongelar = "CONGELAR AS TARJAS"
    if ($congelado) {
        $desde = ""
        try { $desde = (Get-Content (Join-Path $Raiz "CONGELADO.txt") -Raw).Trim() } catch { }
        $congeladoAviso = "<div class='congelado'><span>TARJAS CONGELADAS desde <b>$desde</b>. " +
                          "Os numeros no ar estao parados de proposito. A coleta continua rodando " +
                          "por tras - ao descongelar, entra o numero mais novo.</span></div>"
        $rotuloCongelar = "DESCONGELAR"
    }

    # --- previa escolhida e ainda NAO no ar
    # A pergunta que custou uma janela de teste foi "cliquei e a tarja nao
    # mudou". A resposta tem que estar no alto da tela, nao no meio dela.
    $previaAviso = ""
    if ($ConfirmarAntes) {
        $pendentes = @()
        if ($prevGov -and $prevGov -ne $ufGov) { $pendentes += "GOVERNADOR" }
        if ($prevSen -and $prevSen -ne $ufSen) { $pendentes += "SENADOR" }
        if ($pendentes.Count -gt 0) {
            $nomePend = ($prevGov + $prevSen).ToUpper()
            foreach ($p in $cfg.selecao.pracas) {
                if ($p.uf -eq $prevGov -or $p.uf -eq $prevSen) { $nomePend = $p.nome }
            }
            $previaAviso = "<div class='pendente'><span>" +
                           "<b>$(Html-Seguro $nomePend)</b> está só na PRÉVIA — ainda NÃO está no ar " +
                           "($($pendentes -join " e ")). Clique em <b>COLOCAR NO AR</b> para trocar a tarja." +
                           "</span></div>"
        }
    }

    $paradoAviso = ""
    $intervaloCfg = 20
    if (Tem-Propriedade $cfg "intervalo_segundos") { $intervaloCfg = [int] $cfg.intervalo_segundos }
    $limiteIdade = 3 * $intervaloCfg + 15
    $arqBatida = Join-Path $PastaSaida "coleta.json"
    # Placar de mudancas: a pergunta "esta atualizando?" nao se responde
    # olhando a tarja e tentando notar diferenca. Se o contador nao sobe, o
    # TSE nao mandou numero novo - e isso e diferente de estar quebrado.
    $placar = ""
    if (-not (Test-Path $arqBatida)) {
        $paradoAviso = "<div class='parado'><span>A coleta ainda nao rodou nenhum ciclo. " +
                       "Abra o <b>INICIAR.bat</b> (ou <b>TESTE.bat</b>) e deixe a janela aberta. " +
                       "Enquanto isso as tarjas nao tem dado nenhum.</span></div>"
    } else {
        $idade = [int] ((Get-Date) - (Get-Item $arqBatida).LastWriteTime).TotalSeconds
        try {
            $bat = Get-Content $arqBatida -Raw -Encoding UTF8 | ConvertFrom-Json
            $qtd = 0
            if (Tem-Propriedade $bat "mudancas_total") { $qtd = [int] $bat.mudancas_total }
            $ciclos = 0
            if (Tem-Propriedade $bat "ciclo") { $ciclos = [int] $bat.ciclo }
            $modoBat = ""
            if (Tem-Propriedade $bat "modo") { $modoBat = "$($bat.modo)" }
            $desde = ""
            if ((Tem-Propriedade $bat "segundos_sem_mudanca") -and ([int] $bat.segundos_sem_mudanca) -ge 0) {
                $desde = " &middot; ultima ha $([int] $bat.segundos_sem_mudanca)s"
            }
            $classe = "placar"
            $frase = "<b>$qtd</b> numeros novos do TSE em $ciclos ciclos$desde"
            if ($qtd -eq 0 -and $ciclos -gt 3) {
                $classe = "placar quieto"
                $frase = "<b>nenhum numero novo</b> em $ciclos ciclos - a coleta esta viva, " +
                         "mas o TSE nao mudou nada ainda"
            }
            if ($modoBat -eq "ENSAIO") {
                # No ensaio nao existe TSE: dizer "numeros do TSE" aqui
                # daria a impressao errada de que o teste ja passou.
                $classe = "placar ensaio"
                $frase = "MODO ENSAIO - dados inventados, sem internet. " +
                         "<b>$qtd</b> numeros novos em $ciclos ciclos$desde"
                if ($qtd -eq 0 -and $ciclos -gt 3) {
                    $frase = "MODO ENSAIO - dados inventados, sem internet. " +
                             "<b>nenhum numero novo</b> em $ciclos ciclos"
                }
            }
            $placar = "<div class='$classe'><span>$frase</span></div>"
        } catch { }
        if ($idade -gt $limiteIdade) {
            $paradoAviso = "<div class='parado'><span>A COLETA PAROU. O ultimo ciclo fechou ha " +
                           "<b>$idade segundos</b> (o normal e no maximo $limiteIdade). " +
                           "Os numeros no ar estao CONGELADOS - nao sobem mais. " +
                           "Verifique a janela do INICIAR/TESTE e reabra se estiver fechada.</span></div>"
        }
    }

    # --- divergencia entre o que foi escolhido e o que esta no arquivo
    $divergencia = ""
    $gov = Ler-Json "tarja-governador"
    if ($null -ne $gov -and $gov.abrangencia -and $gov.abrangencia -ne $nomeGov) {
        $divergencia = "<div class='alerta'>Voce selecionou <b>$(Html-Seguro $nomeGov)</b>, mas o " +
                       "arquivo ainda está com <b>$(Html-Seguro $gov.abrangencia)</b>. " +
                       "A janela do INICIAR/TESTE está rodando?</div>"
    }

    $aviso = ""
    if ($qtdNovos -gt 0) {
        $plural = "praças"; if ($qtdNovos -eq 1) { $plural = "praça" }
        $aviso = "<span class='sino'><i></i>$qtdNovos $plural com boletim novo</span>"
    }

    return @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<noscript><meta http-equiv="refresh" content="5"></noscript>
<title>Apuração 2026</title><style>
/* Tema claro. Fontes do sistema de proposito: a maquina do GC pode nao ter
   internet liberada alem do TSE, e fonte da web viraria espera no carregamento. */
:root{
  --fundo:#f5f7fb; --papel:#ffffff; --papel2:#eef2f8;
  --tinta:#0f1a2c; --tinta2:#47587292; --tinta2s:#475872; --tinta3:#8090a8;
  --fio:#e4eaf3; --fio2:#eef2f8;
  --azul:#1d5aa8; --azul-claro:#e9f1fc; --azul-borda:#b9d3f0;
  --verde:#0d7a55; --verde-claro:#e5f6ee; --verde-borda:#a9ddc6;
  --ambar:#a8650a; --ambar-claro:#fff3e0; --ambar-borda:#f0cf9c;
  --sombra:0 1px 2px rgba(15,26,44,.05), 0 6px 16px -6px rgba(15,26,44,.10);
  --sombra-alta:0 2px 4px rgba(15,26,44,.06), 0 14px 32px -12px rgba(15,26,44,.18);
}
*{box-sizing:border-box}
html{-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
body{margin:0;background:var(--fundo);color:var(--tinta);
  font:15px/1.55 "Segoe UI Variable Text","Segoe UI",system-ui,-apple-system,sans-serif}
a{color:inherit}

/* ---------- cabecalho ---------- */
header{position:sticky;top:0;z-index:5;background:rgba(245,247,251,.86);
  backdrop-filter:blur(10px);border-bottom:1px solid var(--fio);
  padding:15px 30px;display:flex;align-items:center;gap:16px;flex-wrap:wrap}
.marca{display:flex;align-items:baseline;gap:10px}
.marca h1{margin:0;font-size:17px;font-weight:650;letter-spacing:-.01em}
.marca span{font-size:11px;font-weight:600;letter-spacing:.13em;text-transform:uppercase;
  color:var(--azul);background:var(--azul-claro);padding:3px 9px;border-radius:999px}
.sino{display:inline-flex;align-items:center;gap:7px;background:var(--ambar-claro);
  color:var(--ambar);border:1px solid var(--ambar-borda);font-size:12.5px;font-weight:600;
  padding:4px 12px;border-radius:999px}
.sino i{width:7px;height:7px;border-radius:50%;background:var(--ambar);
  animation:pulsa 1.8s ease-in-out infinite}
@keyframes pulsa{0%,100%{opacity:1}50%{opacity:.35}}
@media (prefers-reduced-motion:reduce){.sino i{animation:none}}
.resumo{margin-left:auto;display:flex;gap:22px;align-items:center}
.res{text-align:right;line-height:1.3}
.res u{display:block;text-decoration:none;font-size:10.5px;letter-spacing:.11em;
  text-transform:uppercase;color:var(--tinta3);font-weight:600}
.res b{font-size:14.5px;font-weight:650}
.hora{font-variant-numeric:tabular-nums;color:var(--tinta2s);font-size:13px;
  padding-left:22px;border-left:1px solid var(--fio)}

main{padding:26px 30px 70px;max-width:1520px;margin:0 auto}
h2{font-size:11px;text-transform:uppercase;letter-spacing:.13em;color:var(--tinta3);
  font-weight:650;margin:34px 0 13px;display:flex;align-items:center;gap:14px}
h2:first-of-type{margin-top:0}
h2::after{content:"";flex:1;height:1px;background:var(--fio)}

/* ---------- abas de modo ---------- */
.abas{display:flex;gap:4px;background:var(--papel2);padding:3px;border-radius:999px;
  border:1px solid var(--fio)}
.aba{font-size:12px;font-weight:600;padding:5px 13px;border-radius:999px;color:var(--tinta2s);
  text-decoration:none;letter-spacing:0;text-transform:none;white-space:nowrap}
.aba:hover{color:var(--azul)}
.aba.on{background:var(--papel);color:var(--azul);box-shadow:var(--sombra)}

/* ---------- grade de estados ---------- */
.estados{display:grid;grid-template-columns:repeat(auto-fill,minmax(176px,1fr));gap:9px}
.btn{position:relative;display:flex;flex-direction:column;gap:7px;padding:13px 15px 12px;
  border-radius:10px;background:var(--papel);border:1px solid var(--fio);
  text-decoration:none;color:var(--tinta);box-shadow:var(--sombra);
  transition:transform .12s ease,box-shadow .12s ease,border-color .12s ease}
.btn:hover{transform:translateY(-1px);box-shadow:var(--sombra-alta);border-color:var(--azul-borda)}
.btn b{font-size:13.5px;font-weight:650;line-height:1.25;letter-spacing:-.005em}
.btn .tags{display:flex;gap:5px;min-height:18px;align-items:center}
.btn em{font-style:normal;font-size:9.5px;font-weight:700;letter-spacing:.07em;
  padding:2px 7px;border-radius:999px;border:1px solid transparent}
.btn em.g{background:var(--ambar-claro);color:var(--ambar);border-color:var(--ambar-borda)}
.btn em.s{background:var(--verde-claro);color:var(--verde);border-color:var(--verde-borda)}
.btn em.vazio{padding:0;border:0}
.btn u{text-decoration:none;font-size:9.5px;letter-spacing:.1em;text-transform:uppercase;
  font-weight:700;color:var(--tinta3)}
.btn.novo{border-color:var(--ambar-borda);background:linear-gradient(180deg,#fffaf2,#fff)}
.btn.ativo{color:#fff;border-color:transparent;box-shadow:var(--sombra-alta)}
.btn.ativo u{color:rgba(255,255,255,.78)}
.btn.ativo em.g{background:rgba(255,255,255,.2);color:#fff;border-color:transparent}
.btn.ativo em.s{background:rgba(255,255,255,.2);color:#fff;border-color:transparent}
.btn.ativo.gov{background:linear-gradient(165deg,#2a6cc0,#1a5099)}
.btn.ativo.sen{background:linear-gradient(165deg,#12906a,#0b6a49)}
.btn.ativo.ambos{background:linear-gradient(165deg,#2a6cc0 0%,#1a5099 52%,#0f7a57 52%,#0b6a49 100%)}

/* ---------- cartoes ---------- */
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:13px}
.card{background:var(--papel);border:1px solid var(--fio);border-radius:12px;
  padding:17px 20px 15px;box-shadow:var(--sombra)}
.card.destaque{border-color:var(--azul-borda);box-shadow:var(--sombra-alta)}
.card.vazio{color:var(--tinta3);background:var(--papel2);box-shadow:none}
.card h3{margin:0 0 11px;font-size:10.5px;text-transform:uppercase;letter-spacing:.12em;
  color:var(--tinta3);font-weight:700;display:flex;align-items:center;gap:9px;flex-wrap:wrap}
.selo{background:var(--ambar-claro);color:var(--ambar);border:1px solid var(--ambar-borda);
  font-size:9.5px;padding:2px 7px;border-radius:999px;letter-spacing:.06em}
.badge{background:var(--ambar);color:#fff;font-size:10px;padding:3px 9px;border-radius:999px;
  letter-spacing:.05em;font-weight:700}
.visto{font-size:10.5px;color:var(--azul);text-decoration:none;font-weight:600;
  border-bottom:1px solid var(--azul-borda);padding-bottom:1px}
.visto:hover{border-bottom-color:var(--azul)}
.praca{font-size:21px;font-weight:680;letter-spacing:-.015em;margin-bottom:11px;
  display:flex;align-items:baseline;gap:12px}
.urnas{font-size:12px;font-weight:500;color:var(--tinta2s);margin-left:auto;white-space:nowrap;
  font-variant-numeric:tabular-nums;background:var(--papel2);padding:3px 9px;border-radius:999px}
.cand{display:flex;align-items:baseline;gap:10px;padding:9px 0;border-top:1px solid var(--fio2)}
.pos{color:var(--tinta3);font-size:11px;font-weight:700;width:19px}
.nome{font-weight:640;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
  letter-spacing:-.005em}
.part{color:var(--tinta2s);font-size:11.5px;font-weight:600;background:var(--papel2);
  padding:1px 7px;border-radius:4px}
.pct{margin-left:auto;font-weight:700;font-size:17px;font-variant-numeric:tabular-nums;
  letter-spacing:-.02em}
.nada{color:var(--tinta3);font-size:13px;margin:8px 0 0}

.parado{background:#fdecec;border:1px solid #e7a9a9;color:#8a1f1f;padding:14px 18px;
  border-radius:10px;margin-bottom:20px;font-size:14.5px;font-weight:600;display:flex;gap:11px;
  align-items:baseline}
.parado b{color:#5f0d0d}
.parado::before{content:"";flex:none;width:19px;height:19px;border-radius:50%;
  background:#c22a2a;box-shadow:0 0 0 4px rgba(194,42,42,.18);animation:pulsa 1.4s ease-in-out infinite}
.pendente{margin:0 0 16px;padding:14px 18px;border-radius:10px;background:#fff5d9;
  border:2px solid #e8b931;color:#5c4405;font-size:15px;line-height:1.5}
.pendente b{color:#3d2d02}
.comolinha{margin:-6px 0 16px;display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.comoclique{font-size:14px;color:#5a6672}
.comoclique.um{color:#8a4b12;font-weight:600}
.trocaclique{font-size:13px;color:#3f6ea8;text-decoration:none;border:1px solid #c3d4e6;
  border-radius:7px;padding:5px 11px;background:#f6fafd}
.trocaclique:hover{background:#eaf2fa}
.card.previa{border-color:#9fc0e4;background:#fbfdff}
.card.previa h3{display:flex;align-items:baseline;gap:9px;flex-wrap:wrap}
.jaNoAr{font-size:11px;font-weight:700;letter-spacing:.06em;color:#0d7a55;
  background:#e7f5ef;border:1px solid #bfe3d4;border-radius:5px;padding:2px 7px}
.vaiEntrar{font-size:11px;font-weight:700;letter-spacing:.06em;color:#a8650a;
  background:#fdf4e5;border:1px solid #edd6a8;border-radius:5px;padding:2px 7px}
.acoes{display:flex;gap:12px;align-items:center;margin:16px 0 0;flex-wrap:wrap}
.aprovar{display:inline-block;padding:13px 30px;border-radius:9px;background:#0d7a55;
  color:#fff;font-size:15px;font-weight:800;letter-spacing:.04em;text-decoration:none;
  box-shadow:0 2px 0 #0a5f43}
.aprovar:hover{background:#0f8a60}
.descartar{color:var(--tinta3);font-size:13px;text-decoration:underline}
.semAcao{color:var(--tinta3);font-size:13px}
.btn.previa{border-color:#7ea8d8;box-shadow:inset 0 0 0 2px #dceaf8}
u.p{color:#1d5aa8}
.congelado{background:#eef2f7;border:1px solid #b9c6d6;color:#24405f;padding:13px 17px;
  border-radius:10px;margin-bottom:16px;font-size:14px;font-weight:600;display:flex;gap:10px;
  align-items:baseline}
.congelado b{color:#122b47}
.congelado::before{content:"";flex:none;width:15px;height:15px;border-radius:3px;background:#4a6fa5;
  margin-top:2px}
.btncongela{display:inline-block;padding:9px 18px;border-radius:8px;border:1px solid #c3d0de;
  background:#fff;color:#24405f;font-size:13px;font-weight:700;text-decoration:none;
  letter-spacing:.02em}
.btncongela:hover{background:#eef2f7}
.btncongela.ativo{background:#24405f;border-color:#24405f;color:#fff}
.placar{background:#eef4fb;border:1px solid #c3d6ec;color:#1d5aa8;padding:11px 16px;
  border-radius:10px;margin-bottom:16px;font-size:13.5px;display:flex;gap:9px;align-items:baseline}
.placar b{color:#123f77}
.placar::before{content:"";flex:none;width:9px;height:9px;border-radius:50%;background:#1d5aa8;
  margin-top:5px;animation:pulsa 1.8s ease-in-out infinite}
.placar.quieto{background:#f6f7f9;border-color:#dfe3e8;color:#5c6670}
.placar.quieto b{color:#39424b}
.placar.quieto::before{background:#9aa4ae;animation:none}
.placar.ensaio{background:#fdf6e6;border-color:#e8d5a3;color:#7a5a12}
.placar.ensaio b{color:#5a4109}
.placar.ensaio::before{background:#c79a20}
.alerta{background:#fff4ec;border:1px solid #f3c9a8;color:#8f4a12;padding:13px 17px;
  border-radius:10px;margin-bottom:20px;font-size:14px;display:flex;gap:10px;align-items:baseline}
.alerta b{color:#5f2f06}
.alerta::before{content:"!";flex:none;width:19px;height:19px;border-radius:50%;
  background:#c2661a;color:#fff;font-size:12px;font-weight:700;text-align:center;line-height:19px}

footer{color:var(--tinta3);font-size:12.5px;margin-top:34px;padding-top:16px;
  border-top:1px solid var(--fio)}
footer b{color:var(--tinta2s)}
</style></head><body>
<header>
  <div class="marca"><h1>Apuração</h1><span>Eleições 2026</span></div>
  $aviso
  <div class="resumo">
    <div class="res"><u>Governador</u><b>$(Html-Seguro $nomeGov)</b></div>
    <div class="res"><u>Senador</u><b>$(Html-Seguro $nomeSen)</b></div>
    <div class="hora" id="hora">$(Get-Date -Format 'HH:mm:ss')</div>
  </div>
</header>
<main id="vivo">
$paradoAviso
$congeladoAviso
$previaAviso
$placar
$divergencia
<h2>Escolher a praça <span class="abas">$abas</span></h2>
<p class="comolinha">$explicaClique</p>
<div class="estados">$botoes</div>
$blocoPrevia
<h2>O que está nos arquivos agora</h2>
<div class="cards">$cartoes</div>
<h2>Presidente</h2>
<div class="cards">$cardPres</div>
<p style="margin:26px 0 0"><a class="btncongela$(if ($congelado) { ' ativo' })" href="/congelar">$rotuloCongelar</a></p>
<footer>gctse $Versao &middot; As etiquetas <b>GOV</b> e <b>SEN</b> acendem quando o TSE publica boletim novo daquela
praça, e apagam quando você a coloca no ar. A página se atualiza sozinha a cada 5 segundos.</footer>
</main>
<script>
// Troca o conteudo sem recarregar a pagina: sem piscada branca e sem perder
// a posicao do scroll, que numa tela de operacao faz diferenca.
(function () {
  var parado = false;

  function redesenhar(texto) {
    var doc = new DOMParser().parseFromString(texto, 'text/html');
    var novo = doc.getElementById('vivo');
    var cab = doc.querySelector('header');
    if (novo) { document.getElementById('vivo').innerHTML = novo.innerHTML; }
    if (cab) { document.querySelector('header').innerHTML = cab.innerHTML; }
  }

  function buscar() {
    return fetch('/', { cache: 'no-store' })
      .then(function (r) { return r.text(); })
      .then(redesenhar);
  }

  // Clicar num estado navegava e recarregava a pagina, jogando a rolagem
  // para o topo - com 27 botoes na tela, isso faz perder de vista onde se
  // estava. Agora o clique vai por fetch e so o conteudo e redesenhado: a
  // rolagem fica exatamente onde estava.
  document.addEventListener('click', function (ev) {
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

  setInterval(function () {
    if (parado) return;
    var y = window.scrollY;
    buscar()
      .then(function () { window.scrollTo(0, y); })
      .catch(function () { parado = true; location.reload(); });
  }, 5000);
})();
</script>
</body></html>
"@
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
Write-Host "  Painel no ar em http://localhost:$Porta" -ForegroundColor Green
if ($Rede) {
    Write-Host "  Da rede: http://<ip-desta-maquina>:$Porta" -ForegroundColor Green
}
Write-Host "  Ctrl+C encerra. A coleta continua rodando na outra janela."
Write-Host ""
try { Start-Process "http://localhost:$Porta" } catch { }

while ($ouvinte.IsListening) {
    try {
        $ctx = $ouvinte.GetContext()
        $caminho = $ctx.Request.Url.AbsolutePath
        $resposta = $ctx.Response

        $utf8 = New-Object System.Text.UTF8Encoding($false)

        if ($caminho -eq "/modoclique") {
            $m = $ctx.Request.QueryString["m"]
            if ($m -in @("previa", "direto")) {
                [IO.File]::WriteAllText((Join-Path $Raiz "MODO-CLIQUE.txt"), $m, $utf8)
                # Trocar para 1 clique com uma previa pendente deixaria na
                # tela um bloco de previa que nenhum botao mais aprova.
                if ($m -eq "direto") {
                    foreach ($arq in @("PREVIA.txt", "PREVIA-SENADOR.txt")) {
                        Remove-Item (Join-Path $Raiz $arq) -Force -ErrorAction SilentlyContinue
                    }
                }
                Write-Host ("{0} modo do clique: {1}" -f (Get-Date -Format "HH:mm:ss"),
                            $(if ($m -eq "direto") { "1 CLIQUE, direto ao ar" } else { "2 CLIQUES, com previa" }))
            }
            $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
        }

        if ($caminho -eq "/modo") {
            $m = $ctx.Request.QueryString["m"]
            if ($m -in @("ambos", "gov", "sen")) {
                [IO.File]::WriteAllText((Join-Path $Raiz "PAINEL-MODO.txt"), $m, $utf8)
            }
            $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
        }

        if ($caminho -eq "/previa") {
            # So anota o que o operador quer OLHAR. Nao encosta no SELECAO,
            # entao nada muda no ar enquanto ele decide.
            $uf = $ctx.Request.QueryString["uf"]
            $valida = $false
            foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $uf) { $valida = $true } }
            # A pagina no navegador pode ser de antes da troca de modo. Quem
            # manda e o modo de agora, e nao o link que veio.
            if ($valida -and -not (Ler-Modo-Clique)) {
                $modo = Ler-Modo
                if ($modo -eq "ambos" -or $modo -eq "gov") {
                    [IO.File]::WriteAllText((Join-Path $Raiz $ArquivoSelecao), $uf, $utf8)
                }
                if (($modo -eq "ambos" -or $modo -eq "sen") -and $ArquivoSelecaoSenador) {
                    [IO.File]::WriteAllText((Join-Path $Raiz $ArquivoSelecaoSenador), $uf, $utf8)
                }
                Write-Host ("{0} praca NO AR ({1}): {2}" -f (Get-Date -Format "HH:mm:ss"), $modo, $uf.ToUpper())
                $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
            }
            if ($valida) {
                $modo = Ler-Modo
                if ($modo -eq "ambos" -or $modo -eq "gov") {
                    [IO.File]::WriteAllText((Join-Path $Raiz "PREVIA.txt"), $uf, $utf8)
                }
                if ($modo -eq "ambos" -or $modo -eq "sen") {
                    [IO.File]::WriteAllText((Join-Path $Raiz "PREVIA-SENADOR.txt"), $uf, $utf8)
                }
                Write-Host ("{0} previa ({1}): {2}" -f (Get-Date -Format "HH:mm:ss"), $modo, $uf.ToUpper())
            }
            $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
        }

        if ($caminho -eq "/aprovar") {
            # Aqui, e so aqui, a previa vira o que esta no ar: copia para o
            # SELECAO, que e o arquivo que o coletor obedece.
            foreach ($par in @(@("PREVIA.txt", $ArquivoSelecao), @("PREVIA-SENADOR.txt", $ArquivoSelecaoSenador))) {
                $de = Join-Path $Raiz $par[0]
                if (-not $par[1]) { continue }
                $para = Join-Path $Raiz $par[1]
                if (-not (Test-Path $de)) { continue }
                try {
                    $uf = (Get-Content $de -Raw -ErrorAction Stop).Trim().ToLower()
                    if ($uf) {
                        [IO.File]::WriteAllText($para, $uf, $utf8)
                        Write-Host ("{0} APROVADO em {1}: {2}" -f (Get-Date -Format "HH:mm:ss"),
                                    $par[1], $uf.ToUpper())
                    }
                } catch { }
            }
            foreach ($arq in @("PREVIA.txt", "PREVIA-SENADOR.txt")) {
                Remove-Item (Join-Path $Raiz $arq) -Force -ErrorAction SilentlyContinue
            }
            $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
        }

        if ($caminho -eq "/descartar") {
            foreach ($arq in @("PREVIA.txt", "PREVIA-SENADOR.txt")) {
                Remove-Item (Join-Path $Raiz $arq) -Force -ErrorAction SilentlyContinue
            }
            Write-Host ("{0} previa descartada" -f (Get-Date -Format "HH:mm:ss"))
            $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
        }

        if ($caminho -eq "/congelar") {
            # Arquivo-bandeira: o coletor olha a existencia dele a cada
            # publicacao. Nao ha protocolo nem porta entre os dois programas -
            # um arquivo que existe ou nao existe nao tem como falhar pela
            # metade.
            $arqCong = Join-Path $Raiz "CONGELADO.txt"
            if (Test-Path $arqCong) {
                Remove-Item $arqCong -Force -ErrorAction SilentlyContinue
                Write-Host ("{0} tarjas DESCONGELADAS" -f (Get-Date -Format "HH:mm:ss"))
            } else {
                [IO.File]::WriteAllText($arqCong, (Get-Date -Format "dd/MM/yyyy HH:mm:ss"), $utf8)
                Write-Host ("{0} tarjas CONGELADAS" -f (Get-Date -Format "HH:mm:ss"))
            }
            $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
        }

        if ($caminho -eq "/visto") {
            # baixa de alerta: o coletor le e limpa na proxima volta
            $chave = $ctx.Request.QueryString["chave"]
            if ($chave -match "^[a-z]{2}-\d{1,2}$") {
                [IO.File]::WriteAllText((Join-Path $Raiz "VISTO.txt"), $chave, $utf8)
            }
            $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
        }

        if ($caminho -eq "/selecionar") {
            $uf = $ctx.Request.QueryString["uf"]
            $valida = $false
            foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $uf) { $valida = $true } }
            if ($valida) {
                $modo = Ler-Modo
                # sem BOM e sem quebra de linha extra: o coletor compara texto
                if ($modo -eq "ambos" -or $modo -eq "gov") {
                    [IO.File]::WriteAllText((Join-Path $Raiz $ArquivoSelecao), $uf, $utf8)
                }
                if (($modo -eq "ambos" -or $modo -eq "sen") -and $ArquivoSelecaoSenador) {
                    [IO.File]::WriteAllText((Join-Path $Raiz $ArquivoSelecaoSenador), $uf, $utf8)
                }
                Write-Host ("{0} praca selecionada ({1}): {2}" -f (Get-Date -Format "HH:mm:ss"),
                            $modo, $uf.ToUpper())
            }
            $resposta.StatusCode = 303; $resposta.RedirectLocation = "/"; $resposta.Close(); continue
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
}
