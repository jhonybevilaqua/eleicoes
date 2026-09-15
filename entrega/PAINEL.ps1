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

function Html-Seguro {
    param($Texto)
    if ($null -eq $Texto) { return "" }
    return ([string] $Texto).Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;")
}

function Montar-Pagina {
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

        $tags = ""
        if ($novoG) { $tags += "<em class='g'>GOV</em>" }
        if ($novoS) { $tags += "<em class='s'>SEN</em>" }
        if (-not $tags) { $tags = "<em class='vazio'>&nbsp;</em>" }

        $marca = ""
        if ($p.uf -eq $ufGov -and $p.uf -eq $ufSen) { $marca = "<u>no ar</u>" }
        elseif ($p.uf -eq $ufGov) { $marca = "<u>gov no ar</u>" }
        elseif ($p.uf -eq $ufSen) { $marca = "<u>sen no ar</u>" }

        $botoes += "<a class='$classe' href='/selecionar?uf=$($p.uf)'>" +
                   "<b>$(Html-Seguro $p.nome)</b><span class='tags'>$tags</span>$marca</a>`n"
    }

    # --- presidente
    $pres = Ler-Json "tarja-presidente"
    $cardPres = "<div class='card vazio'><h3>Presidente</h3><p>arquivo ainda nao gerado</p></div>"
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
            $cartoes += "<div class='card vazio'><h3>$($t[1])</h3><p>arquivo ainda nao gerado</p></div>"
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

    # --- divergencia entre o que foi escolhido e o que esta no arquivo
    $divergencia = ""
    $gov = Ler-Json "tarja-governador"
    if ($null -ne $gov -and $gov.abrangencia -and $gov.abrangencia -ne $nomeGov) {
        $divergencia = "<div class='alerta'>Voce selecionou <b>$(Html-Seguro $nomeGov)</b>, mas o " +
                       "arquivo ainda esta com <b>$(Html-Seguro $gov.abrangencia)</b>. " +
                       "A janela do INICIAR/TESTE esta rodando?</div>"
    }

    $aviso = ""
    if ($qtdNovos -gt 0) {
        $aviso = "<span class='contador'>$qtdNovos praça(s) com boletim novo</span>"
    }

    return @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="5">
<title>Painel da apuracao</title><style>
*{box-sizing:border-box}
body{margin:0;background:#0b1220;color:#e8eef8;font:15px/1.5 "Segoe UI",system-ui,sans-serif}
header{padding:18px 26px;border-bottom:1px solid #22314a;display:flex;align-items:center;
  gap:14px;flex-wrap:wrap}
h1{margin:0;font-size:19px;font-weight:600}
.contador{background:#7a4a10;color:#ffd489;font-size:12.5px;font-weight:600;padding:3px 10px;
  border-radius:999px}
.agora{margin-left:auto;color:#8ea3c0;font-size:13.5px;text-align:right}
.agora b{color:#fff}
main{padding:20px 26px 60px;max-width:1500px;margin:0 auto}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.11em;color:#8ea3c0;font-weight:600;
  margin:26px 0 10px;display:flex;align-items:center;gap:12px}
h2:first-of-type{margin-top:0}
.abas{display:flex;gap:6px;margin-left:auto}
.aba{font-size:12px;padding:4px 11px;border-radius:999px;background:#16223a;color:#9db1cc;
  text-decoration:none;border:1px solid #22314a;text-transform:none;letter-spacing:0}
.aba:hover{border-color:#3b6fb5}
.aba.on{background:#1d4d92;border-color:#4a90d9;color:#fff}
.estados{display:grid;grid-template-columns:repeat(auto-fill,minmax(168px,1fr));gap:8px}
.btn{position:relative;display:flex;flex-direction:column;gap:3px;padding:10px 13px;
  border-radius:7px;background:#16223a;border:1px solid #22314a;text-decoration:none;
  color:#cfdcee;transition:background .12s,border-color .12s}
.btn:hover{background:#1d2c4a;border-color:#3b6fb5}
.btn b{font-size:13.5px;font-weight:600;line-height:1.25}
.btn .tags{display:flex;gap:4px;min-height:16px}
.btn em{font-style:normal;font-size:10px;font-weight:700;letter-spacing:.06em;padding:1px 5px;
  border-radius:3px}
.btn em.g{background:#7a4a10;color:#ffd489}
.btn em.s{background:#16513a;color:#7ae0ae}
.btn em.vazio{padding:0}
.btn u{text-decoration:none;font-size:10px;letter-spacing:.07em;color:#8fbdf0;text-transform:uppercase}
.btn.novo{border-color:#a8702a;box-shadow:0 0 0 1px #a8702a inset}
.btn.ativo{background:#1d4d92;border-color:#4a90d9;color:#fff}
.btn.ativo u{color:#cfe4fb}
.btn.ativo.gov{background:#1d4d92}
.btn.ativo.sen{background:#155741;border-color:#3fae83}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px}
.card{background:#111c30;border:1px solid #22314a;border-radius:8px;padding:14px 16px}
.card.destaque{border-color:#3b6fb5}
.card.vazio{color:#7e93b2}
.card h3{margin:0 0 8px;font-size:12.5px;text-transform:uppercase;letter-spacing:.07em;
  color:#8ea3c0;font-weight:600;display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.selo{background:#3a2f12;color:#f0c674;font-size:10px;padding:2px 6px;border-radius:3px}
.badge{background:#7a4a10;color:#ffd489;font-size:10.5px;padding:2px 7px;border-radius:3px;
  letter-spacing:.04em}
.visto{font-size:10.5px;color:#8fbdf0;text-decoration:none;border-bottom:1px dotted #4a7cb5}
.praca{font-size:18px;font-weight:600;margin-bottom:9px;display:flex;align-items:baseline;gap:10px}
.urnas{font-size:12px;font-weight:400;color:#8ea3c0;margin-left:auto;white-space:nowrap}
.cand{display:flex;align-items:baseline;gap:8px;padding:6px 0;border-top:1px solid #1b2841}
.pos{color:#7e93b2;font-size:11.5px;width:18px}
.nome{font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.part{color:#8ea3c0;font-size:11.5px}
.pct{margin-left:auto;font-weight:700;font-variant-numeric:tabular-nums}
.nada{color:#7e93b2;font-size:13px;margin:6px 0 0}
.alerta{background:#3a1f12;border:1px solid #7a4a22;color:#f0c07a;padding:11px 15px;
  border-radius:7px;margin-bottom:18px;font-size:14px}
.alerta b{color:#fff}
footer{color:#7e93b2;font-size:12.5px;margin-top:30px;padding-top:14px;border-top:1px solid #22314a}
</style></head><body>
<header><h1>Painel da apuracao</h1>$aviso
  <div class="agora">governador <b>$(Html-Seguro $nomeGov)</b> &middot;
    senador <b>$(Html-Seguro $nomeSen)</b><br>
    atualizado <b>$(Get-Date -Format 'HH:mm:ss')</b></div></header>
<main>
$divergencia
<h2>Presidente</h2>
<div class="cards">$cardPres</div>
<h2>Escolher a praca <span class="abas">$abas</span></h2>
<div class="estados">$botoes</div>
<h2>O que esta nos arquivos agora</h2>
<div class="cards">$cartoes</div>
<footer>As etiquetas <b>GOV</b> e <b>SEN</b> acendem quando o TSE publica boletim novo daquela
praca. Elas apagam quando voce coloca a praca no ar. A pagina se atualiza a cada 5 segundos.</footer>
</main></body></html>
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

        if ($caminho -eq "/modo") {
            $m = $ctx.Request.QueryString["m"]
            if ($m -in @("ambos", "gov", "sen")) {
                [IO.File]::WriteAllText((Join-Path $Raiz "PAINEL-MODO.txt"), $m, $utf8)
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
        # uma requisicao malformada nao pode derrubar o painel
        try { $resposta.Close() } catch { }
    }
}
