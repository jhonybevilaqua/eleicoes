<#
    gctse GRAFICOS - SALVAR TODAS AS TELAS EM PNG (SALVAR-TELAS.bat ou botao
    "salvar telas" no gerenciador)

    Para o Jornalismo usar na semana depois da eleicao: grava cada tela que
    tem dado como imagem PNG em Full HD (horizontal 1920x1080, vertical
    1080x1920), COM as fotos dos candidatos, numa pasta com data e hora:
      TELAS-SALVAS\2026-10-26_0930\HORIZONTAL\001 - Presidente.png
      TELAS-SALVAS\2026-10-26_0930\VERTICAL\...
      TELAS-SALVAS\2026-10-26_0930\RESUMOS\...
    Telas ainda "aguardando" (sem dado) ficam de fora.
    Usa o Chrome ou o Edge instalado, sem janela (modo headless). Os numeros
    sao os do web\dados.js / estados.js / municipios.js do momento: rode
    depois que o TSE chegar a 100%. Pode rodar com tudo aberto (demora
    alguns minutos e usa bastante processador - melhor fora do ar).
#>
param([switch] $SemPausa, [switch] $SemAbrirPasta)
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$Web = Join-Path $Raiz "web"
$Status = Join-Path $Raiz "salvar-telas.json"
$Log = Join-Path $Raiz "SALVAR-TELAS.txt"
$script:Linhas = New-Object System.Collections.Generic.List[string]
$script:St = [ordered]@{ ok = $null; rodando = $true; pid = $PID; inicio = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); feitas = 0; total = 0; pasta = ""; mensagem = "comecando..." }

function Anotar([string] $Texto, [string] $Cor = "Gray") { Write-Host $Texto -ForegroundColor $Cor; $script:Linhas.Add(("{0:HH:mm:ss} {1}" -f (Get-Date), $Texto)) }
function Gravar-Status {
    try { [IO.File]::WriteAllText($Status, ($script:St | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false))) } catch { }
}
function Sair([bool] $Ok, [string] $Msg) {
    $script:St.ok = $Ok; $script:St.rodando = $false; $script:St.mensagem = $Msg; $script:St.fim = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Gravar-Status
    Anotar $Msg $(if ($Ok) { "Green" } else { "Red" })
    try { [IO.File]::WriteAllLines($Log, $script:Linhas, (New-Object Text.UTF8Encoding($true))) } catch { }
    if (-not $SemPausa) { Write-Host ""; Read-Host "Enter para fechar" | Out-Null }
    exit $(if ($Ok) { 0 } else { 1 })
}
Gravar-Status

# ------------------------------------------------------------- navegador
$nav = $null
foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                 "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
                 "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) {
    if ($c -and (Test-Path $c)) { $nav = $c; break }
}
if (-not $nav -and $env:GCTSE_NAVEGADOR -and (Test-Path $env:GCTSE_NAVEGADOR)) { $nav = $env:GCTSE_NAVEGADOR }
if (-not $nav) { Sair $false "nao achei o Chrome nem o Edge nesta maquina" }
if (-not (Test-Path (Join-Path $Web "dados.js"))) { Sair $false "falta web\dados.js: abra o GERENCIADOR.bat (ou GRAFICOS.bat) e espere o primeiro boletim" }
Anotar "navegador: $nav" "Cyan"

$tmpBase = $(if ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() })
$Perfil = Join-Path $tmpBase "gctse-salvar-telas"
# Start-Process junta os argumentos com espaco: so o que tem espaco vai
# entre aspas (o Windows tira as aspas; o endereco file:/// ja vem sem espaco).
function Q([string] $Arg) { if ($Arg -match '\s') { return '"' + $Arg + '"' }; return $Arg }
$BaseArgs = @("--headless=new", "--disable-gpu", "--hide-scrollbars", "--mute-audio", "--no-first-run", "--no-default-browser-check",
              "--disable-extensions", "--allow-file-access-from-files", (Q ("--user-data-dir=" + $Perfil)))
if ($env:GCTSE_NAVEGADOR_EXTRA) { $BaseArgs += @($env:GCTSE_NAVEGADOR_EXTRA.Split(' ') | Where-Object { $_ }) }
function Url-De([string] $Pagina) {
    $p = $Pagina.Split('?')[0]; $q = $(if ($Pagina.Contains('?')) { "?" + $Pagina.Split('?', 2)[1] } else { "" })
    return (New-Object System.Uri -ArgumentList (Join-Path $Web $p)).AbsoluteUri + $q
}
function Rodar-Nav([string[]] $Extra, [int] $Segundos, [string] $Saida = "") {
    $a = @{ FilePath = $nav; ArgumentList = @($BaseArgs + $Extra); PassThru = $true; NoNewWindow = $true }
    $errTmp = Join-Path $tmpBase ("gctse-salvar-err-{0}.txt" -f $PID); $a.RedirectStandardError = $errTmp
    if ($Saida) { $a.RedirectStandardOutput = $Saida }
    $p = Start-Process @a
    if (-not $p.WaitForExit($Segundos * 1000)) { try { $p.Kill() } catch { }; return $false }
    return $true
}

# ------------------------------------------------- quais telas tem dado
Anotar "conferindo quais telas tem dado..." "Cyan"
$tmpLista = Join-Path $tmpBase ("gctse-telas-{0}.html" -f $PID)
[void] (Rodar-Nav @("--virtual-time-budget=15000", "--dump-dom", (Q (Url-De "telas-com-dados.html"))) 120 $tmpLista)
$lista = @()
try {
    $html = [IO.File]::ReadAllText($tmpLista, [Text.Encoding]::UTF8)
    $m = [regex]::Match($html, '<pre id="r">(.*?)</pre>', 'Singleline')
    # (PowerShell 5.1 devolve a lista JSON inteira como um objeto so: desmonta)
    if ($m.Success) { $lj = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value) | ConvertFrom-Json; $lista = @($lj | ForEach-Object { $_ }) }
} catch { }
Remove-Item -LiteralPath $tmpLista -Force -ErrorAction SilentlyContinue
if (-not $lista.Count) { Sair $false "nao consegui ler a lista de telas (telas-com-dados.html) - o navegador abriu?" }
$comDado = @($lista | Where-Object { -not $_.vazia })
Anotar ("{0} telas na lista, {1} com dado ({2} aguardando, ficam de fora)" -f $lista.Count, $comDado.Count, ($lista.Count - $comDado.Count))

# ------------------------------------------------------------- a fila
$Pasta = Join-Path (Join-Path $Raiz "TELAS-SALVAS") (Get-Date -Format "yyyy-MM-dd_HHmm")
$fila = New-Object System.Collections.Generic.List[object]
$n = 0
foreach ($t in $comDado) {
    $n++
    $v = ("$($t.f)" -eq "v")
    $nomeArq = ("{0:000} - {1}" -f $n, "$($t.nome)") -replace '[\\/:*?"<>|]', '-'
    $fila.Add([pscustomobject]@{ pagina = "grafico.html?g=$($t.id)"; sub = $(if ($v) { "VERTICAL" } else { "HORIZONTAL" }); nome = $nomeArq
                                 w = $(if ($v) { 540 } else { 1280 }); h = $(if ($v) { 960 } else { 720 }); escala = $(if ($v) { 2 } else { 1.5 })
                                 tempo = $(if ("$($t.id)" -match '^munmapa') { 20000 } else { 8000 }) })
}
# os resumos (paginas Full HD proprias): 7 telas, horizontal e vertical
for ($i = 1; $i -le 7; $i++) {
    $fila.Add([pscustomobject]@{ pagina = "resumo-horizontal.html?tela=$i"; sub = "RESUMOS"; nome = ("resumo {0} - horizontal" -f $i); w = 1920; h = 1080; escala = 1; tempo = 8000 })
    $fila.Add([pscustomobject]@{ pagina = "resumo-vertical.html?tela=$i"; sub = "RESUMOS"; nome = ("resumo {0} - vertical" -f $i); w = 1080; h = 1920; escala = 1; tempo = 8000 })
}
$script:St.total = $fila.Count; $script:St.pasta = $Pasta; $script:St.mensagem = "salvando..."; Gravar-Status
Anotar "salvando $($fila.Count) imagens em $Pasta" "Cyan"

# ------------------------------------------------------------ fotografar
# O navegador sem janela desenha so a area visivel, um pouco menor que a
# janela: a janela vai 200 px mais alta, a pagina fica com o tamanho exato
# (?exportar=LxA) no canto de cima e a imagem e recortada no tamanho certo.
$script:SemCorte = $false
try { Add-Type -AssemblyName System.Drawing } catch { $script:SemCorte = $true }
function Cortar([string] $Arq, [int] $W, [int] $H) {
    if ($script:SemCorte) { return }
    try {
        $src = [System.Drawing.Image]::FromFile($Arq); $bmp = $null
        try {
            if ($src.Width -eq $W -and $src.Height -eq $H) { return }
            $bmp = New-Object System.Drawing.Bitmap -ArgumentList $W, $H
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $ret = New-Object System.Drawing.Rectangle -ArgumentList 0, 0, $W, $H
            $g.DrawImage($src, $ret, $ret, [System.Drawing.GraphicsUnit]::Pixel); $g.Dispose()
        } finally { $src.Dispose() }
        if ($bmp) { $bmp.Save($Arq, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose() }
    } catch { $script:SemCorte = $true; Anotar "   (nao consegui recortar as imagens: $($_.Exception.Message))" "Yellow" }
}
$falhas = 0
foreach ($it in $fila) {
    $dir = Join-Path $Pasta $it.sub
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $png = Join-Path $dir ($it.nome + ".png")
    $pag = $it.pagina + $(if ($it.pagina.Contains("?")) { "&" } else { "?" }) + ("exportar={0}x{1}" -f $it.w, $it.h)
    $ok = Rodar-Nav @(("--window-size={0},{1}" -f $it.w, ($it.h + 200)), ("--force-device-scale-factor={0}" -f ([string] $it.escala).Replace(",", ".")),
                      ("--virtual-time-budget={0}" -f $it.tempo), (Q ("--screenshot=" + $png)), (Q (Url-De $pag))) 90
    if ($ok -and (Test-Path $png) -and (Get-Item $png).Length -gt 1000) {
        if (-not $script:SemCorte) { try { Cortar $png ([int] [math]::Round($it.w * $it.escala)) ([int] [math]::Round($it.h * $it.escala)) } catch { $script:SemCorte = $true; Anotar "   (nao consegui recortar as imagens: $($_.Exception.Message))" "Yellow" } }
        $script:St.feitas++
    }
    else { $falhas++; Anotar "   FALHOU: $($it.sub)\$($it.nome)" "Yellow" }
    if (($script:St.feitas + $falhas) % 5 -eq 0) { $script:St.mensagem = ("salvando... {0} de {1}" -f ($script:St.feitas + $falhas), $fila.Count); Gravar-Status; Write-Host ("   {0} de {1}" -f ($script:St.feitas + $falhas), $fila.Count) }
}
try { Remove-Item -LiteralPath $Perfil -Recurse -Force -ErrorAction SilentlyContinue } catch { }
if ($script:St.feitas -gt 0 -and -not $SemAbrirPasta -and $env:OS -eq "Windows_NT") { try { Start-Process explorer.exe -ArgumentList ('"' + $Pasta + '"') } catch { } }
if ($script:St.feitas -eq 0) { Sair $false "nenhuma tela salva - veja SALVAR-TELAS.txt" }
Sair $true ("{0} imagens salvas em TELAS-SALVAS\{1}{2}" -f $script:St.feitas, (Split-Path -Leaf $Pasta), $(if ($falhas) { " ($falhas falharam - veja SALVAR-TELAS.txt)" } else { "" }))
