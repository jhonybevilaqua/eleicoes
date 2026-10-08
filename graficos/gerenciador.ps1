<#
    gctse GRAFICOS - GERENCIADOR DAS SAIDAS (DeckLink via OBS)

    Servidor local (so nesta maquina) que:
      - entrega as paginas da pasta web\ em http://localhost:8098/
      - guarda o que esta NO AR em cada saida (horizontal e vertical)
    O operador usa gerenciador.html (monitor do Windows); cada OBS mostra
    saida.html?saida=h ou ?saida=v, que segue o que o operador escolheu.

    Uso: GERENCIADOR.bat (abre este servidor, as coletas e a pagina).
#>

[CmdletBinding()]
param([int] $Porta = 0, [switch] $AbrirPagina)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# Um clique na janela preta a poe em modo "Selecionar" e CONGELA o programa.
if ($env:OS -eq "Windows_NT") {
    try {
        Add-Type -Namespace GcTseGerenciador -Name JanelaConsole -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $entradaConsole = [GcTseGerenciador.JanelaConsole]::GetStdHandle(-10)
        [uint32] $modoConsole = 0
        if ([GcTseGerenciador.JanelaConsole]::GetConsoleMode($entradaConsole, [ref] $modoConsole)) {
            if (($modoConsole -band 0x40) -ne 0) { $modoConsole = $modoConsole - 0x40 }
            $modoConsole = $modoConsole -bor 0x80
            [void] [GcTseGerenciador.JanelaConsole]::SetConsoleMode($entradaConsole, $modoConsole)
        }
    } catch { }
}

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
$Web = Join-Path $Raiz "web"

function Escrever-Log {
    param([string] $Texto, [string] $Cor = "Gray")
    $linha = "{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $Texto
    Write-Host $linha -ForegroundColor $Cor
    try {
        if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" | Out-Null }
        Add-Content -Path (Join-Path "logs" ("gerenciador-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))) -Value $linha -Encoding UTF8
    } catch { }
}

$PortaCfg = 8098
# Saida VERTICAL no OBS: a tela em pe vai girada dentro do quadro 1920x1080
# (90 = horario, -90 = anti-horario, 0 = sem girar). Trocavel na pagina.
$GirarPadrao = 90
try {
    $cfg = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Name -eq "porta_gerenciador" -and [int] $p.Value -gt 0) { $PortaCfg = [int] $p.Value }
        if ($p.Name -eq "girar_saida_vertical" -and @(90, -90, 0) -contains [int] $p.Value) { $GirarPadrao = [int] $p.Value }
    }
} catch { }
if ($Porta -le 0) { $Porta = $PortaCfg }

# ------------------------------------------------------- o que esta no ar
# h = saida horizontal, v = saida vertical. tela = o que mostrar; seq muda a
# cada troca; acao/aseq = comando para o giro e o resumo (proximo, uf:pr...).
# Fica gravado em gerenciador-estado.json: se o servidor reiniciar, as
# saidas voltam no que estava no ar.

$ArqEstado = Join-Path $Raiz "gerenciador-estado.json"
function Estado-Padrao {
    return [ordered]@{
        h = [ordered]@{ tela = "apresentacao"; seq = 1; acao = ""; aseq = 0; quando = ""; rodizio = ""; tempo = 0 }
        v = [ordered]@{ tela = "apresentacao"; seq = 1; acao = ""; aseq = 0; quando = ""; rodizio = ""; tempo = 0 }
        girar_v = $GirarPadrao
        obs = [ordered]@{ h = ""; v = "" }
    }
}
$script:Estado = Estado-Padrao
if (Test-Path $ArqEstado) {
    try {
        $lido = Get-Content $ArqEstado -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($s in @("h", "v")) {
            $x = $lido.$s
            if ($null -ne $x -and "$($x.tela)" -match '^[a-z0-9-]{1,40}$') {
                $script:Estado[$s].tela = "$($x.tela)"
                $script:Estado[$s].seq = [int] $x.seq + 1
                if ("$($x.acao)" -match '^[a-z0-9:,-]{1,40}$') { $script:Estado[$s].acao = "$($x.acao)" }
                foreach ($p in $x.PSObject.Properties) {
                    if ($p.Name -eq "rodizio" -and "$($p.Value)" -match '^[a-z0-9:,-]{0,800}$') { $script:Estado[$s].rodizio = "$($p.Value)" }
                    if ($p.Name -eq "tempo" -and "$($p.Value)" -match '^\d{1,3}$' -and [int] $p.Value -ge 3 -and [int] $p.Value -le 300) { $script:Estado[$s].tempo = [int] $p.Value }
                }
            }
        }
        foreach ($p in $lido.PSObject.Properties) {
            if ($p.Name -eq "girar_v" -and @(90, -90, 0) -contains [int] $p.Value) { $script:Estado.girar_v = [int] $p.Value }
        }
    } catch { $script:Estado = Estado-Padrao }
}
function Salvar-Estado {
    try {
        [IO.File]::WriteAllText($ArqEstado, ($script:Estado | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

# Situacao dos dois OBS (obs-saidas.json e gravado pelo obs-saidas.ps1):
# "" = sem OBS automatico | fechado | sem-decklink (canal nao escolhido) | ok
$ArqObs = Join-Path $Raiz "obs-saidas.json"
$script:ObsChecado = [datetime]::MinValue
function Checar-Obs {
    if (((Get-Date) - $script:ObsChecado).TotalSeconds -lt 5) { return }
    $script:ObsChecado = Get-Date
    try {
        if (-not (Test-Path $ArqObs)) { return }
        $info = Get-Content $ArqObs -Raw -Encoding UTF8 | ConvertFrom-Json
        $abertos = @()
        foreach ($pr in @(Get-Process -Name obs64 -ErrorAction SilentlyContinue)) { try { if ($pr.Path) { $abertos += $pr.Path } } catch { } }
        foreach ($s in @("h", "v")) {
            $x = $null
            foreach ($p in $info.PSObject.Properties) { if ($p.Name -eq $s) { $x = $p.Value } }
            if ($null -eq $x -or -not $x.instalado) { $script:Estado.obs[$s] = ""; continue }
            $exe = "$($x.exe)"
            $aberto = @($abertos | Where-Object { [string]::Equals($_, $exe, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            $dl = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $exe))) "config\obs-studio\plugin_config\decklink-output-ui\decklinkOutputProps.json"
            $escolhida = $false
            try { if (Test-Path $dl) { $escolhida = ((Get-Content $dl -Raw) -match '"auto_start"\s*:\s*true') } } catch { }
            if (-not $aberto) { $script:Estado.obs[$s] = "fechado" }
            elseif (-not $escolhida) { $script:Estado.obs[$s] = "sem-decklink" }
            else { $script:Estado.obs[$s] = "ok" }
        }
    } catch { }
}

# ------------------------------------------------------------- respostas

$Tipos = @{
    ".html" = "text/html; charset=utf-8"; ".js" = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"; ".css" = "text/css; charset=utf-8"
    ".png" = "image/png"; ".jpg" = "image/jpeg"; ".jpeg" = "image/jpeg"; ".svg" = "image/svg+xml"
    ".md" = "text/plain; charset=utf-8"; ".txt" = "text/plain; charset=utf-8"; ".ico" = "image/x-icon"
}

function Responder {
    param($Ctx, [int] $Codigo, [string] $Tipo, [byte[]] $Corpo)
    $r = $Ctx.Response
    $r.StatusCode = $Codigo
    $r.ContentType = $Tipo
    $r.Headers["Cache-Control"] = "no-store"
    if ($null -eq $Corpo) { $Corpo = [byte[]] @() }
    $r.ContentLength64 = $Corpo.Length
    if ($Corpo.Length -gt 0) { $r.OutputStream.Write($Corpo, 0, $Corpo.Length) }
}
function Responder-Json {
    param($Ctx, $Obj)
    Responder $Ctx 200 "application/json; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes(($Obj | ConvertTo-Json -Depth 4 -Compress)))
}
function Ler-Arquivo {
    # Le mesmo com o coletor trocando o arquivo ao lado (dados.js).
    param([string] $Caminho)
    $fs = [IO.File]::Open($Caminho, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $ms = New-Object System.IO.MemoryStream
        $fs.CopyTo($ms)
        return ,$ms.ToArray()
    } finally { $fs.Dispose() }
}

# ------------------------------------------------------- vigia da noite
# A cada 3 s le web\dados.js e web\estados.js e:
#  - PRESIDENTE ELEITO: quando o TSE declara, avisa no painel e (se ligado)
#    poe a tela "Presidente eleito" no ar nas DUAS saidas, sozinho - mesmo
#    com a pagina do gerenciador fechada. Uma vez por eleicao.
#  - VIRADA: quem lidera Presidente no Brasil ou num estado mudou.
#  - COLETA PAROU / TSE SEM RESPOSTA, e reabre GRAFICOS.bat / ESTADOS.bat
#    se a janela foi fechada.
# Tudo vai para o painel (eventos) e para logs\ocorrencias-AAAA-MM-DD.csv;
# cada troca do que vai ao ar, para logs\no-ar-AAAA-MM-DD.csv (relatorio).
$script:Ensaio = $false
$script:EleitoAuto = $true
$script:Reabrir = $true
try {
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Name -eq "ensaio" -and $p.Value -eq $true) { $script:Ensaio = $true }
        if ($p.Name -eq "presidente_eleito_no_ar" -and $p.Value -eq $false) { $script:EleitoAuto = $false }
        if ($p.Name -eq "reabrir_coletas" -and $p.Value -eq $false) { $script:Reabrir = $false }
    }
} catch { }
if ($script:Ensaio) { $script:Reabrir = $false }   # o ENSAIO.bat cuida das janelas dele
$script:Estado.eleito = [ordered]@{ auto = $script:EleitoAuto; feito = ""; nome = ""; quando = ""; cortou = $false }
$script:Estado.eventos = New-Object System.Collections.ArrayList
$script:Estado.ensaio = $script:Ensaio
if (Test-Path $ArqEstado) {
    try {
        $lidoEl = (Get-Content $ArqEstado -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | Where-Object { $_.Name -eq "eleito" } | Select-Object -First 1
        if ($lidoEl -and $lidoEl.Value) {
            foreach ($p in $lidoEl.Value.PSObject.Properties) {
                if ($p.Name -eq "auto") { $script:Estado.eleito.auto = [bool] $p.Value }
                if (@("feito", "nome", "quando") -contains $p.Name -and "$($p.Value)" -match '^[^<>]{0,80}$') { $script:Estado.eleito[$p.Name] = "$($p.Value)" }
                if ($p.Name -eq "cortou") { $script:Estado.eleito.cortou = [bool] $p.Value }
            }
        }
    } catch { }
}

function Linha-Csv([string] $Arq, [string[]] $Campos) {
    try {
        if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" | Out-Null }
        $caminho = Join-Path "logs" ("{0}-{1}.csv" -f $Arq, (Get-Date -Format "yyyy-MM-dd"))
        if (-not (Test-Path $caminho)) { Add-Content -Path $caminho -Value "data;hora;$(if ($Arq -eq 'no-ar') { 'saida;tela;acao;origem' } else { 'tipo;texto' })" -Encoding UTF8 }
        $limpos = @($Campos | ForEach-Object { "$_" -replace '[;\r\n]', ' ' })
        Add-Content -Path $caminho -Value ((@((Get-Date -Format "yyyy-MM-dd"), (Get-Date -Format "HH:mm:ss")) + $limpos) -join ";") -Encoding UTF8
    } catch { }
}
function Registrar-NoAr([string] $S, [string] $Tela, [string] $Acao, [string] $Origem) { Linha-Csv "no-ar" @($S, $Tela, $Acao, $Origem) }
# tipo: eleito | virada | alerta | ok | info
function Evento([string] $Tipo, [string] $Texto) {
    $id = [DateTime]::Now.Ticks
    [void] $script:Estado.eventos.Add([ordered]@{ id = "$id"; hora = (Get-Date -Format "HH:mm:ss"); tipo = $Tipo; texto = $Texto })
    while ($script:Estado.eventos.Count -gt 40) { $script:Estado.eventos.RemoveAt(0) }
    Linha-Csv "ocorrencias" @($Tipo, $Texto)
    Escrever-Log ("{0}: {1}" -f $Tipo.ToUpper(), $Texto) $(if ($Tipo -eq "alerta") { "Red" } elseif ($Tipo -eq "eleito") { "Green" } else { "Yellow" })
}
function Por-No-Ar([string] $S, [string] $Tela, [string] $Acao, [string] $Origem) {
    $script:Estado[$S].tela = $Tela
    $script:Estado[$S].seq = [int] $script:Estado[$S].seq + 1
    $script:Estado[$S].acao = $Acao
    $script:Estado[$S].quando = (Get-Date -Format "HH:mm:ss")
    Registrar-NoAr $S $Tela $Acao $Origem
}

function Ler-Js([string] $Nome) {
    # "window.GCTSE_X = {...};" -> objeto (le mesmo com o coletor gravando)
    $arq = Join-Path $Web $Nome
    if (-not (Test-Path $arq)) { return $null }
    $txt = [Text.Encoding]::UTF8.GetString((Ler-Arquivo $arq))
    $i = $txt.IndexOf("{"); $f = $txt.LastIndexOf("}")
    if ($i -lt 0 -or $f -le $i) { return $null }
    return $txt.Substring($i, $f - $i + 1) | ConvertFrom-Json
}
function Prop($o, [string] $n) { if ($null -eq $o) { return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Lista-De($x) { if ($null -eq $x) { return @() }; $v = Prop $x "value"; if ($x -isnot [array] -and $null -ne $v) { return @($v) }; return @($x) }
function Lider($ab) {
    if ($null -eq $ab -or -not (Prop $ab "tem")) { return $null }
    $cs = @(Lista-De (Prop $ab "candidatos") | Where-Object { $null -ne $_ -and [double] (Prop $_ "votos") -gt 0 } | Sort-Object { [double] (Prop $_ "votos") } -Descending)
    if ($cs.Count -lt 2) { return $null }
    return $cs[0]
}
function Coletor-Aberto([string] $Ps1) {
    $alvo = [regex]::Escape((Join-Path $Raiz $Ps1))
    try {
        $ps = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop | Where-Object { $_.CommandLine -match $alvo })
        return $ps.Count -gt 0
    } catch { }
    try { return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $c = $null; try { $c = $_.CommandLine } catch { }; $c -and $c -match $alvo }).Count -gt 0 } catch { return $true }
}
$script:Vigia = @{ prox = [datetime]::MinValue; lidoP = [datetime]::MinValue; lidoE = [datetime]::MinValue; lideres = @{}; parouP = $false; parouE = $false
    semTse = $false; viSemEleito = $false; reabriuP = [datetime]::MinValue; reabriuE = [datetime]::MinValue; nomes = @{} }
function Vigiar-Coleta([string] $Qual, [string] $Js, [string] $Ps1, [string] $Bat, [int] $Limite) {
    $arq = Join-Path $Web $Js
    if (-not (Test-Path $arq)) { return }
    $idade = ((Get-Date) - (Get-Item $arq).LastWriteTime).TotalSeconds
    $chave = "parou$Qual"; $chaveR = "reabriu$Qual"
    if ($idade -gt $Limite -and -not $script:Vigia[$chave]) {
        $script:Vigia[$chave] = $true
        Evento "alerta" ("COLETA {0} PAROU ha {1:N0} s ({2})" -f $(if ($Qual -eq "P") { "DE PRESIDENTE" } else { "DOS ESTADOS" }), $idade, $Bat)
    } elseif ($idade -le $Limite -and $script:Vigia[$chave]) {
        $script:Vigia[$chave] = $false
        Evento "ok" ("coleta {0} voltou" -f $(if ($Qual -eq "P") { "de Presidente" } else { "dos estados" }))
    }
    if ($script:Vigia[$chave] -and $script:Reabrir -and ((Get-Date) - $script:Vigia[$chaveR]).TotalSeconds -gt 120) {
        $script:Vigia[$chaveR] = Get-Date
        if (Coletor-Aberto $Ps1) { Evento "alerta" ("a janela do {0} esta aberta mas nao grava: clique nela e aperte ESC (ou feche e abra de novo)" -f $Bat) }
        else {
            try { Start-Process -FilePath (Join-Path $Raiz $Bat) -WorkingDirectory $Raiz; Evento "info" ("{0} estava fechado: REABERTO sozinho" -f $Bat) }
            catch { Evento "alerta" ("nao consegui reabrir o {0}: {1}" -f $Bat, $_.Exception.Message) }
        }
    }
}
function Vigiar {
    if ((Get-Date) -lt $script:Vigia.prox) { return }
    $script:Vigia.prox = (Get-Date).AddSeconds(3)
    Vigiar-Coleta "P" "dados.js" "graficos.ps1" "GRAFICOS.bat" 90
    Vigiar-Coleta "E" "estados.js" "estados.ps1" "ESTADOS.bat" 150
    $arq = Join-Path $Web "dados.js"
    if (-not (Test-Path $arq)) { return }
    $quando = (Get-Item $arq).LastWriteTime
    if ($quando -eq $script:Vigia.lidoP) { return }
    $d = $null
    try { $d = Ler-Js "dados.js" } catch { return }   # gravando neste instante: proxima volta
    if ($null -eq $d) { return }
    $script:Vigia.lidoP = $quando
    # TSE sem resposta (depois de publicar; antes das 17h e normal)
    $semTse = ((Prop $d "recebendo_tse") -eq $false) -and -not (Prop $d "tse_nao_publicou")
    if ($semTse -and -not $script:Vigia.semTse) { Evento "alerta" "TSE SEM RESPOSTA (Presidente) - a tela fica no ultimo dado" }
    elseif (-not $semTse -and $script:Vigia.semTse) { Evento "ok" "TSE respondendo de novo" }
    $script:Vigia.semTse = $semTse
    $br = Prop $d "br"
    if ($null -eq $br -or -not (Prop $br "tem")) { return }
    $eleicao = "$(Prop (Prop $d 'tse') 'eleicao')"
    $cs = @(Lista-De (Prop $br "candidatos") | Where-Object { $null -ne $_ })
    $el = @($cs | Where-Object { (Prop $_ "eleito") -eq $true }) | Select-Object -First 1
    $pctBr = [double] (Prop (Prop $br "secoes") "pct")
    # ---- PRESIDENTE ELEITO
    if ($null -eq $el) { $script:Vigia.viSemEleito = $true }
    elseif ($script:Estado.eleito.feito -ne $eleicao) {
        $nome = "$(Prop $el 'nome')"; $pctV = ([double] (Prop $el 'pct')).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture).Replace(".", ",")
        $script:Estado.eleito.feito = $eleicao; $script:Estado.eleito.nome = $nome; $script:Estado.eleito.quando = (Get-Date -Format "HH:mm:ss"); $script:Estado.eleito.cortou = $false
        # corte automatico so se o eleito apareceu com o gerenciador aberto
        # (reabrir o programa no dia seguinte nao tira nada do ar)
        if ($script:Estado.eleito.auto -and $script:Vigia.viSemEleito) {
            Por-No-Ar "h" "eleito-h" "" "automatico (eleito)"; Por-No-Ar "v" "eleito-v" "" "automatico (eleito)"
            $script:Estado.eleito.cortou = $true
            Evento "eleito" ("PRESIDENTE ELEITO: {0} ({1}%) - NO AR nas duas saidas (automatico)" -f $nome, $pctV)
        } else {
            Evento "eleito" ("PRESIDENTE ELEITO: {0} ({1}%) - coloque no ar pelo painel" -f $nome, $pctV)
        }
        Salvar-Estado
    }
    # ---- VIRADAS (Brasil e estados), com a apuracao ja andando
    $abs = New-Object System.Collections.ArrayList
    [void] $abs.Add(@("br", $br))
    $ufs = Prop $d "ufs"
    if ($ufs) { foreach ($p in $ufs.PSObject.Properties) { [void] $abs.Add(@($p.Name, $p.Value)) } }
    foreach ($par in $abs) {
        $k = $par[0]; $ab = $par[1]; $l = Lider $ab
        if ($null -eq $l) { continue }
        $num = "$(Prop $l 'numero')"; $script:Vigia.nomes[$num] = "$(Prop $l 'nome')"
        $pctAb = [double] (Prop (Prop $ab "secoes") "pct")
        $chaveL = "$eleicao|$k"
        if ($script:Vigia.lideres.ContainsKey($chaveL) -and $script:Vigia.lideres[$chaveL] -ne $num -and $pctAb -ge 1) {
            $antes = $script:Vigia.nomes[$script:Vigia.lideres[$chaveL]]
            Evento "virada" ("VIROU {0}: {1} passou {2} ({3}% das urnas)" -f $(if ($k -eq "br") { "NO BRASIL" } else { $k.ToUpper() }), "$(Prop $l 'nome')", $antes, $pctAb.ToString("0.0", [Globalization.CultureInfo]::InvariantCulture).Replace(".", ","))
        }
        $script:Vigia.lideres[$chaveL] = $num
    }
}

# ------------------------------------------------------------------ servidor

# O HttpListener casa pelo cabecalho Host: registra localhost e 127.0.0.1.
$ouvinte = New-Object System.Net.HttpListener
$ouvinte.Prefixes.Add("http://localhost:$Porta/")
$ouvinte.Prefixes.Add("http://127.0.0.1:$Porta/")
try {
    $ouvinte.Start()
} catch {
    Escrever-Log "Nao foi possivel abrir a porta $Porta : $($_.Exception.Message)" "Red"
    Escrever-Log "A porta pode estar em uso (gerenciador ja aberto?). Outra porta: config-graficos.json, porta_gerenciador." "Yellow"
    exit 1
}

Escrever-Log "gctse GERENCIADOR no ar: http://localhost:$Porta/gerenciador.html" "Green"
Escrever-Log "OBS da saida HORIZONTAL: http://localhost:$Porta/saida.html?saida=h  (fonte Navegador 1920x1080)" "Cyan"
Escrever-Log "OBS da saida VERTICAL:   http://localhost:$Porta/saida.html?saida=v&obs=1  (fonte Navegador 1920x1080, ja girada)" "Cyan"
Escrever-Log ("no ar agora: horizontal = {0} | vertical = {1}" -f $script:Estado.h.tela, $script:Estado.v.tela)
Write-Host ""
Write-Host "  Deixe esta janela ABERTA: sem ela as saidas param de trocar." -ForegroundColor Yellow
Write-Host ""
if ($AbrirPagina) { try { Start-Process "http://localhost:$Porta/gerenciador.html" } catch { } }

$script:Pedido = $null
while ($ouvinte.IsListening) {
    $ctx = $null
    try {
        # espera um pedido sem parar a vigia (a cada 3 s, mesmo sem pagina aberta)
        if ($null -eq $script:Pedido) { $script:Pedido = $ouvinte.GetContextAsync() }
        if (-not $script:Pedido.Wait(1000)) { try { Vigiar } catch { Escrever-Log "vigia: $($_.Exception.Message)" "Red" }; continue }
        $ctx = $script:Pedido.Result; $script:Pedido = $null
        $req = $ctx.Request
        $caminho = $req.Url.AbsolutePath

        if ($caminho -eq "/estado") {
            Checar-Obs
            try { Vigiar } catch { }
            Responder-Json $ctx $script:Estado
        }
        elseif ($caminho -eq "/eleito") {
            # ?auto=1|0 liga/desliga o corte automatico; ?ar=1 poe a tela do
            # Presidente eleito no ar nas duas saidas agora.
            $a = "$($req.QueryString['auto'])"; $ar = "$($req.QueryString['ar'])"
            if ($a -eq "1" -or $a -eq "0") { $script:Estado.eleito.auto = ($a -eq "1"); Evento "info" ("Presidente eleito automatico no ar: {0}" -f $(if ($a -eq "1") { "LIGADO" } else { "DESLIGADO" })) }
            if ($ar -eq "1") { Por-No-Ar "h" "eleito-h" "" "painel (eleito)"; Por-No-Ar "v" "eleito-v" "" "painel (eleito)"; $script:Estado.eleito.cortou = $true; Evento "info" "Presidente eleito NO AR nas duas saidas (painel)" }
            Salvar-Estado
            Responder-Json $ctx $script:Estado
        }
        elseif ($caminho -eq "/relatorio-dados") {
            # Relatorio da noite: o que foi ao ar, ocorrencias, evolucao e copias
            # (hoje e ontem - a noite passa da meia-noite).
            $dias = @((Get-Date).AddDays(-1).ToString("yyyy-MM-dd"), (Get-Date).ToString("yyyy-MM-dd"))
            $q = "$($req.QueryString['dia'])"; if ($q -match '^\d{4}-\d{2}-\d{2}$') { $dias = @($q, ([datetime]::ParseExact($q, "yyyy-MM-dd", $null)).AddDays(1).ToString("yyyy-MM-dd")) }
            $rel = [ordered]@{ dias = $dias; no_ar = @(); ocorrencias = @(); evolucao = $null; copias = @(); eleito = $script:Estado.eleito; gerado = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") }
            foreach ($dia in $dias) {
                foreach ($par in @(@("no-ar", "no_ar"), @("ocorrencias", "ocorrencias"))) {
                    $arqL = Join-Path (Join-Path $Raiz "logs") ("{0}-{1}.csv" -f $par[0], $dia)
                    if (Test-Path $arqL) { $rel[$par[1]] += @([IO.File]::ReadAllLines($arqL, [Text.Encoding]::UTF8) | Select-Object -Skip 1) }
                }
            }
            $ev = @(Get-ChildItem -Path $Raiz -Filter "evolucao-*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
            if ($ev.Count) { try { $rel.evolucao = Get-Content $ev[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
            $pc = Join-Path $Raiz "copias-de-seguranca"
            if (Test-Path $pc) { $rel.copias = @(Get-ChildItem -Path $pc -Filter "*.zip" -File | Where-Object { $n = $_.Name; @($dias | Where-Object { $n -like "*$_*" }).Count -gt 0 } | ForEach-Object { $_.Name }) }
            Responder $ctx 200 "application/json; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes(($rel | ConvertTo-Json -Depth 8 -Compress)))
        }
        elseif ($caminho -eq "/rodizio") {
            # Telas da apresentacao automatica de uma saida (vazio = as do
            # apresentacao-config.js) e segundos por tela (0 = do config).
            $s = "$($req.QueryString['saida'])"; $telas = "$($req.QueryString['telas'])"; $tempo = "$($req.QueryString['tempo'])"
            $tempoOk = ($tempo -eq "" -or $tempo -eq "0" -or ($tempo -match '^\d{1,3}$' -and [int] $tempo -ge 3 -and [int] $tempo -le 300))
            if (($s -eq "h" -or $s -eq "v") -and $telas -match '^[a-z0-9:,-]{0,800}$' -and $tempoOk) {
                $script:Estado[$s].rodizio = $telas
                $script:Estado[$s].tempo = $(if ($tempo -eq "") { 0 } else { [int] $tempo })
                # apresentacao no ar: recomeca ja com as telas novas
                if ($script:Estado[$s].tela -eq "apresentacao") {
                    $script:Estado[$s].seq = [int] $script:Estado[$s].seq + 1
                    $script:Estado[$s].quando = (Get-Date -Format "HH:mm:ss")
                }
                Salvar-Estado
                Escrever-Log ("rodizio - saida {0}: {1} ({2} s)" -f $(if ($s -eq "h") { "HORIZONTAL" } else { "VERTICAL" }), $(if ($telas) { $telas } else { "padrao" }), $script:Estado[$s].tempo) "Green"
                Responder-Json $ctx $script:Estado
            } else {
                Responder $ctx 400 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("pedido invalido"))
            }
        }
        elseif ($caminho -eq "/copia") {
            # Copia de seguranca (copia-seguranca.ps1) num clique. ?ver=1 so
            # devolve como foi a ultima.
            $arqCopia = Join-Path $Raiz "copia-seguranca.json"
            if ("$($req.QueryString['ver'])" -ne "1") {
                $psExe = "powershell"
                if ($env:WINDIR -and (Test-Path (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"))) { $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe" }
                [IO.File]::WriteAllText($arqCopia, '{"ok":null,"mensagem":"copiando..."}')
                $argsCopia = @{ FilePath = $psExe; WorkingDirectory = $Raiz; ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + (Join-Path $Raiz "copia-seguranca.ps1") + '"'), "-SemPausa") }
                if ($env:OS -eq "Windows_NT") { $argsCopia.WindowStyle = "Minimized" }
                try { Start-Process @argsCopia }
                catch { [IO.File]::WriteAllText($arqCopia, (([ordered]@{ ok = $false; mensagem = "nao abriu: $($_.Exception.Message)" }) | ConvertTo-Json -Compress)) }
                Escrever-Log "copia de seguranca pedida pelo gerenciador" "Green"
            }
            $txt = $(if (Test-Path $arqCopia) { [IO.File]::ReadAllText($arqCopia) } else { '{"ok":null,"mensagem":"nenhuma copia ainda"}' })
            Responder $ctx 200 "application/json; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes($txt))
        }
        elseif ($caminho -eq "/girar") {
            # Como a tela VERTICAL vai girada na saida do OBS.
            $g = "$($req.QueryString['graus'])"
            if (@("90", "-90", "0") -contains $g) {
                $script:Estado.girar_v = [int] $g
                Salvar-Estado
                Escrever-Log ("saida VERTICAL no OBS: girar {0}" -f $g) "Green"
                Responder-Json $ctx $script:Estado
            } else {
                Responder $ctx 400 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("pedido invalido"))
            }
        }
        elseif ($caminho -eq "/definir") {
            # Troca o que vai ao ar numa saida.
            $s = "$($req.QueryString['saida'])"; $tela = "$($req.QueryString['tela'])"; $acao = "$($req.QueryString['acao'])"
            if (($s -eq "h" -or $s -eq "v") -and $tela -match '^[a-z0-9-]{1,40}$' -and ($acao -eq "" -or $acao -match '^[a-z0-9:,-]{1,40}$')) {
                $script:Estado[$s].tela = $tela
                $script:Estado[$s].seq = [int] $script:Estado[$s].seq + 1
                $script:Estado[$s].acao = $acao
                $script:Estado[$s].quando = (Get-Date -Format "HH:mm:ss")
                Salvar-Estado
                Registrar-NoAr $s $tela $acao "painel"
                Escrever-Log ("NO AR - saida {0}: {1}" -f $(if ($s -eq "h") { "HORIZONTAL" } else { "VERTICAL" }), $tela) "Green"
                Responder-Json $ctx $script:Estado
            } else {
                Responder $ctx 400 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("pedido invalido"))
            }
        }
        elseif ($caminho -eq "/comando") {
            # Comando para o giro / resumo que esta no ar (proximo, anterior,
            # uf:pr, tela:3, auto).
            $s = "$($req.QueryString['saida'])"; $acao = "$($req.QueryString['acao'])"
            if (($s -eq "h" -or $s -eq "v") -and $acao -match '^[a-z0-9:,-]{1,40}$') {
                $script:Estado[$s].acao = $acao
                $script:Estado[$s].aseq = [int] $script:Estado[$s].aseq + 1
                Escrever-Log ("comando - saida {0}: {1}" -f $(if ($s -eq "h") { "HORIZONTAL" } else { "VERTICAL" }), $acao)
                Responder-Json $ctx $script:Estado
            } else {
                Responder $ctx 400 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("pedido invalido"))
            }
        }
        else {
            # Arquivos da pasta web\ (so ela: nada de .. nem caminho absoluto).
            $rel = [Uri]::UnescapeDataString($caminho.TrimStart('/'))
            if ($rel -eq "") { $rel = "gerenciador.html" }
            $arq = Join-Path $Web ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            if ($rel -match '\.\.' -or $rel -match '[:\\]' -or -not (Test-Path $arq -PathType Leaf)) {
                Responder $ctx 404 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("nao encontrado"))
            } else {
                $ext = [IO.Path]::GetExtension($arq).ToLower()
                $tipo = "application/octet-stream"
                if ($Tipos.ContainsKey($ext)) { $tipo = $Tipos[$ext] }
                try {
                    Responder $ctx 200 $tipo (Ler-Arquivo $arq)
                } catch {
                    # arquivo sendo trocado pelo coletor neste instante: a
                    # pagina tenta de novo em 3 s e fica no ultimo dado.
                    Responder $ctx 503 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("ocupado"))
                }
            }
        }
    } catch {
        Escrever-Log ("FALHA ao atender {0}: {1}" -f $(if ($ctx) { $ctx.Request.Url.AbsolutePath } else { "?" }), $_.Exception.Message) "Red"
    } finally {
        if ($ctx) { try { $ctx.Response.Close() } catch { } }
    }
}
