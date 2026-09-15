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

function Ler-Json {
    param([string] $Nome)
    $caminho = Join-Path $PastaSaida "$Nome.json"
    if (-not (Test-Path $caminho)) { return $null }
    try { return (Get-Content $caminho -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Ler-Selecao {
    if (Test-Path $ArquivoSelecao) {
        try { return (Get-Content $ArquivoSelecao -Raw).Trim().ToLower() } catch { }
    }
    return $cfg.selecao.padrao
}

function Html-Seguro {
    param($Texto)
    if ($null -eq $Texto) { return "" }
    return ([string] $Texto).Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;")
}

function Montar-Pagina {
    $ufAtual = Ler-Selecao
    $nomeAtual = $ufAtual.ToUpper()
    foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $ufAtual) { $nomeAtual = $p.nome } }

    # botoes de estado
    $botoes = ""
    foreach ($p in $cfg.selecao.pracas) {
        $classe = "btn"
        if ($p.uf -eq $ufAtual) { $classe = "btn ativo" }
        $botoes += "<a class='$classe' href='/selecionar?uf=$($p.uf)'>" +
                   "<b>$(Html-Seguro $p.nome)</b><i>$($p.uf.ToUpper())</i></a>`n"
    }

    # O arquivo acompanhou a selecao? Se o coletor caiu, o operador escolhe
    # um estado e o arquivo fica no anterior - a tarja no ar continuaria
    # mostrando o estado velho. Melhor gritar isso na tela.
    $divergencia = ""
    $gov = Ler-Json "tarja-governador"
    if ($null -ne $gov -and $gov.abrangencia -and $gov.abrangencia -ne $nomeAtual) {
        $divergencia = "<div class='alerta'>Voce selecionou <b>$(Html-Seguro $nomeAtual)</b>, " +
                       "mas o arquivo ainda esta com <b>$(Html-Seguro $gov.abrangencia)</b>. " +
                       "O coletor (janela do INICIAR/TESTE) esta rodando?</div>"
    }

    # cartoes das tarjas
    $cartoes = ""
    $tarjas = @(
        @{ arq = "tarja-presidente";  titulo = "Presidente" },
        @{ arq = "tarja-governador";  titulo = "Governador (selecionado)" },
        @{ arq = "tarja-senador";     titulo = "Senador (selecionado)" }
    )
    foreach ($t in $tarjas) {
        $d = Ler-Json $t.arq
        if ($null -eq $d) {
            $cartoes += "<div class='card vazio'><h3>$($t.titulo)</h3><p>arquivo ainda nao gerado</p></div>`n"
            continue
        }
        $selo = ""
        if ($d.selo) { $selo = "<span class='selo'>$(Html-Seguro $d.selo)</span>" }
        $linhas = ""
        foreach ($i in 1, 2) {
            $vis = $d."cand${i}_visivel"
            if ($vis -ne "1") { continue }
            $linhas += "<div class='cand'><span class='pos'>$i" + "&ordm;</span>" +
                       "<span class='nome'>$(Html-Seguro $d."cand${i}_nome")</span>" +
                       "<span class='part'>$(Html-Seguro $d."cand${i}_partido")</span>" +
                       "<span class='pct'>$(Html-Seguro $d."cand${i}_percentual")</span></div>`n"
        }
        if (-not $linhas) { $linhas = "<p class='nada'>sem candidato ainda</p>" }
        $cartoes += @"
<div class='card'>
  <h3>$($t.titulo) $selo</h3>
  <div class='praca'>$(Html-Seguro $d.abrangencia)
    <span class='urnas'>$(Html-Seguro $d.apuracao_pct) das urnas</span></div>
  $linhas
</div>
"@
    }

    # rodizio
    $rod = Ler-Json "tarja-rodizio"
    $blocoRod = ""
    if ($null -ne $rod) {
        $itens = ""
        foreach ($p in $rod.pracas) {
            $cls = "rodi"
            if ($p.visivel -ne "1") { $cls = "rodi sem" }
            $itens += "<div class='$cls'><b>$($p.ordem)</b>" +
                      "<span class='rp'>$(Html-Seguro $p.praca)</span>" +
                      "<span class='rc'>$(Html-Seguro $p.cand1_nome)</span>" +
                      "<span class='rv'>$(Html-Seguro $p.cand1_percentual)</span></div>`n"
        }
        $blocoRod = "<h2>Rodizio &middot; $($rod.com_dado) de $($rod.total) pracas com boletim</h2>" +
                    "<div class='grade-rod'>$itens</div>"
    }

    return @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="5">
<title>Painel da apuracao</title><style>
*{box-sizing:border-box}
body{margin:0;background:#0b1220;color:#e8eef8;font:15px/1.5 "Segoe UI",system-ui,sans-serif}
header{padding:20px 28px;border-bottom:1px solid #22314a;display:flex;align-items:baseline;gap:16px;flex-wrap:wrap}
h1{margin:0;font-size:20px;font-weight:600}
.agora{margin-left:auto;color:#8ea3c0;font-size:14px}
.agora b{color:#fff}
main{padding:24px 28px 60px;max-width:1280px;margin:0 auto}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.11em;color:#8ea3c0;font-weight:600;
   margin:34px 0 12px}
h2:first-child{margin-top:0}
.estados{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.btn{display:flex;flex-direction:column;gap:2px;padding:13px 16px;border-radius:7px;
     background:#16223a;border:1px solid #22314a;text-decoration:none;color:#cfdcee;
     transition:background .12s,border-color .12s}
.btn:hover{background:#1d2c4a;border-color:#3b6fb5}
.btn b{font-size:15px;font-weight:600;letter-spacing:.01em}
.btn i{font-style:normal;font-size:11.5px;color:#7e93b2;letter-spacing:.09em}
.btn.ativo{background:#1d4d92;border-color:#4a90d9;color:#fff}
.btn.ativo i{color:#b8d4f2}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:14px}
.card{background:#111c30;border:1px solid #22314a;border-radius:8px;padding:16px 18px}
.card.vazio{color:#7e93b2}
.card h3{margin:0 0 10px;font-size:13px;text-transform:uppercase;letter-spacing:.07em;
         color:#8ea3c0;font-weight:600;display:flex;align-items:center;gap:8px}
.selo{background:#3a2f12;color:#f0c674;font-size:10.5px;padding:2px 7px;border-radius:3px;
      letter-spacing:.05em}
.praca{font-size:19px;font-weight:600;margin-bottom:12px;display:flex;align-items:baseline;gap:10px}
.urnas{font-size:12.5px;font-weight:400;color:#8ea3c0;margin-left:auto;white-space:nowrap}
.cand{display:flex;align-items:baseline;gap:9px;padding:7px 0;border-top:1px solid #1b2841}
.pos{color:#7e93b2;font-size:12px;width:20px}
.nome{font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.part{color:#8ea3c0;font-size:12px}
.pct{margin-left:auto;font-weight:700;font-variant-numeric:tabular-nums}
.nada{color:#7e93b2;font-size:13px;margin:6px 0 0}
.grade-rod{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:8px}
.rodi{background:#111c30;border:1px solid #22314a;border-radius:6px;padding:9px 12px;font-size:13px;
      display:flex;align-items:baseline;gap:8px}
.rodi b{color:#7e93b2;font-weight:600;font-size:11.5px}
.rodi{gap:7px}
.rodi .rp{font-weight:600;white-space:nowrap}
.rodi .rc{color:#8ea3c0;font-size:11.5px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
          flex:1;min-width:0}
.rodi .rv{color:#cfdcee;font-size:12px;font-variant-numeric:tabular-nums;white-space:nowrap}
.rodi.sem{opacity:.42}
.alerta{background:#3a1f12;border:1px solid #7a4a22;color:#f0c07a;padding:12px 16px;
  border-radius:7px;margin-bottom:22px;font-size:14px}
.alerta b{color:#fff}
footer{color:#7e93b2;font-size:12.5px;margin-top:34px;padding-top:16px;border-top:1px solid #22314a}
</style></head><body>
<header><h1>Painel da apuracao</h1>
  <div class="agora">no ar: <b>$(Html-Seguro $nomeAtual)</b> &middot;
    atualizado <b>$(Get-Date -Format 'HH:mm:ss')</b></div></header>
<main>
$divergencia
<h2>Estado nas tarjas de governador e senador</h2>
<div class="estados">$botoes</div>
<h2>O que esta nos arquivos agora</h2>
<div class="cards">$cartoes</div>
$blocoRod
<footer>Clicar num estado troca as tarjas de governador e senador em cerca de 1 segundo.
A pagina se atualiza a cada 5 segundos. Quem coleta e o gctse, em outra janela.</footer>
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

        if ($caminho -eq "/selecionar") {
            $uf = $ctx.Request.QueryString["uf"]
            $valida = $false
            foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $uf) { $valida = $true } }
            if ($valida) {
                # sem BOM e sem quebra de linha extra: o coletor le e compara texto
                [IO.File]::WriteAllText((Join-Path $Raiz $ArquivoSelecao), $uf,
                                        (New-Object System.Text.UTF8Encoding($false)))
                Write-Host ("{0} estado selecionado: {1}" -f (Get-Date -Format "HH:mm:ss"), $uf.ToUpper())
            }
            $resposta.StatusCode = 303
            $resposta.RedirectLocation = "/"
            $resposta.Close()
            continue
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
