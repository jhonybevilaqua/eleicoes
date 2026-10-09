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
    if ($Obj -is [System.Collections.IDictionary] -and $Obj.Contains("h") -and $Obj.Contains("v")) { $Obj.voce = $script:Voce }
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
$script:DadosAoAbrir = $true
try {
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Name -eq "ensaio" -and $p.Value -eq $true) { $script:Ensaio = $true }
        if ($p.Name -eq "presidente_eleito_no_ar" -and $p.Value -eq $false) { $script:EleitoAuto = $false }
        if ($p.Name -eq "reabrir_coletas" -and $p.Value -eq $false) { $script:Reabrir = $false }
        if ($p.Name -eq "atualizar_dados_ao_abrir" -and $p.Value -eq $false) { $script:DadosAoAbrir = $false }
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
function Registrar-NoAr([string] $S, [string] $Tela, [string] $Acao, [string] $Origem) {
    if ($script:Quem) { $Origem = "$Origem - $($script:Quem)" }
    Linha-Csv "no-ar" @($S, $Tela, $Acao, $Origem)
}
# tipo: eleito | virada | alerta | ok | info
# Situacao dos dados que nao vem do boletim ao vivo (botao "dados do TSE"):
# andamento do atualizar-dados.ps1 e quando cada arquivo foi gerado.
function Ler-Situacao-Dados {
    $o = [ordered]@{ rodando = $false; etapa = ""; execucao = $null; arquivos = [ordered]@{} }
    $arqS = Join-Path $Raiz "atualizar-dados.json"
    if (Test-Path $arqS) {
        try {
            $x = [IO.File]::ReadAllText($arqS) | ConvertFrom-Json
            $o.execucao = $x
            if ($x.rodando) {
                $vivo = $false; try { $vivo = $null -ne (Get-Process -Id ([int] $x.pid) -ErrorAction Stop) } catch { }
                $o.rodando = $vivo; $o.etapa = "$($x.etapa)"
                if (-not $vivo) { $o.etapa = "" }
            }
        } catch { }
    }
    function Quando([string] $Arq) { if (Test-Path $Arq) { return (Get-Item $Arq).LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss") }; return $null }
    $o.arquivos.tse = Quando (Join-Path $Raiz "GUARDAR-DADOS-TSE.txt")
    $o.arquivos.candidatos = Quando (Join-Path $Web "candidatos-genero.js")
    $o.arquivos.perfil = Quando (Join-Path $Web "perfil-eleitor.js")
    $o.arquivos.comparecimento = $false
    $pf = Join-Path $Web "perfil-eleitor.js"
    if (Test-Path $pf) { try { $o.arquivos.comparecimento = ([IO.File]::ReadAllText($pf)).Contains('"comparecimento"') } catch { } }
    return $o
}
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

# CONTROLE PELO iPAD (config-graficos.json): "acesso_rede": true e
# "senha_controle": "1234". O iPad abre http://<IP deste PC>:<porta>/controle.html,
# digita a senha uma vez e so pode usar a rota /ipad (trocar tela) e ler
# /estado. Precisa do LIBERAR-IPAD.bat (como administrador) uma vez no PC.
$script:Rede = $false; $script:Senha = ""
try { foreach ($p in $cfg.PSObject.Properties) {
    if ($p.Name -eq "acesso_rede" -and $p.Value -eq $true) { $script:Rede = $true }
    if ($p.Name -eq "senha_controle" -and "$($p.Value)" -match '^\S{4,32}$') { $script:Senha = "$($p.Value)" } } } catch { }
if ($script:Ensaio) { $script:Rede = $false }
$script:Estado.ipad = "ar"   # iPad: "ar" = direto; "sugerir" = cai na previa (lembrado)
try { $li = (Get-Content $ArqEstado -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | Where-Object { $_.Name -eq "ipad" } | Select-Object -First 1
      if ($li -and @("ar", "sugerir") -contains "$($li.Value)") { $script:Estado.ipad = "$($li.Value)" } } catch { }
$script:Estado.sugestao_h = $null; $script:Estado.sugestao_v = $null

# VARIOS USUARIOS (config-graficos.json, "usuarios"): cada um com nome, senha,
# tela e modo. Todos os comandos chegam AQUI (o exibidor, onde esta o OBS).
#   tela: "controle"     -> controle.html (iPad/celular: botoes grandes)
#         "gerenciador"  -> gerenciador.html completo (outro computador)
#   modo: "direto"    -> o comando vai ao ar
#         "sugerir"   -> cai na PREVIA do operador, que corta (ou nao)
#         "bloqueado" -> so ve; nao comanda
# O operador (este PC) muda o modo de cada um na hora, ou TRAVA todos.
# Coisas tecnicas (dados do TSE, copia, girar, eleito automatico, acessos)
# so neste PC. A "senha_controle" antiga vira o usuario "iPad".
$script:Usuarios = New-Object System.Collections.ArrayList
$modosSalvos = @{}
try { $la = (Get-Content $ArqEstado -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | Where-Object { $_.Name -eq "acessos" } | Select-Object -First 1
      if ($la -and $la.Value) { foreach ($pa in $la.Value.PSObject.Properties) { $modosSalvos["$($pa.Name)"] = "$($pa.Value)" } } } catch { }
try {
    $listaU = @(); foreach ($p in $cfg.PSObject.Properties) { if ($p.Name -eq "usuarios" -and $p.Value) { $listaU = @($p.Value) } }
    foreach ($x in $listaU) {
        $nomeU = "$((Prop $x 'nome'))".Trim(); $senhaU = "$((Prop $x 'senha'))"
        $telaU = $(if ("$((Prop $x 'tela'))" -eq "gerenciador") { "gerenciador" } else { "controle" })
        $modoU = "$((Prop $x 'modo'))"; if (@("direto", "sugerir", "bloqueado") -notcontains $modoU) { $modoU = $(if ($telaU -eq "gerenciador") { "direto" } else { "sugerir" }) }
        if ($nomeU -notmatch '^[^<>"&]{1,30}$' -or $senhaU -notmatch '^\S{4,32}$') { Escrever-Log "usuario ignorado no config (nome 1-30 letras e senha de 4 a 32 caracteres sem espaco): '$nomeU'" "Yellow"; continue }
        if (@($script:Usuarios | Where-Object { $_.senha -eq $senhaU -or $_.nome -eq $nomeU }).Count) { Escrever-Log "usuario '$nomeU' ignorado: nome ou senha repetidos (cada pessoa precisa de uma senha diferente)" "Yellow"; continue }
        if ($modosSalvos.ContainsKey($nomeU) -and @("direto", "sugerir", "bloqueado") -contains $modosSalvos[$nomeU]) { $modoU = $modosSalvos[$nomeU] }
        [void] $script:Usuarios.Add([ordered]@{ nome = $nomeU; senha = $senhaU; tela = $telaU; modo = $modoU; visto = $null; ip = ""; ultimo = ""; rodSug = $null; legado = $false })
    }
} catch { Escrever-Log "config 'usuarios' com erro: $($_.Exception.Message)" "Yellow" }
if ($script:Senha -and -not @($script:Usuarios | Where-Object { $_.senha -eq $script:Senha }).Count) {
    [void] $script:Usuarios.Add([ordered]@{ nome = "iPad"; senha = $script:Senha; tela = "controle"; modo = $(if ($script:Estado.ipad -eq "ar") { "direto" } else { "sugerir" }); visto = $null; ip = ""; ultimo = ""; rodSug = $null; legado = $true })
}
if ($script:Rede -and $script:Usuarios.Count -eq 0) { Escrever-Log "acesso_rede ligado SEM usuarios/senha (minimo 4 caracteres): acesso pela rede DESLIGADO por seguranca." "Yellow"; $script:Rede = $false }
$script:Estado.travado = $false
try { $lt = (Get-Content $ArqEstado -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | Where-Object { $_.Name -eq "travado" } | Select-Object -First 1
      if ($lt) { $script:Estado.travado = [bool] $lt.Value } } catch { }
# o que vai para o /estado (sem as senhas)
function Publicar-Usuarios {
    $agora = Get-Date; $l = @(); $m = [ordered]@{}
    foreach ($u in $script:Usuarios) {
        $on = ($null -ne $u.visto -and ($agora - $u.visto).TotalSeconds -lt 20)
        $l += [ordered]@{ nome = $u.nome; tela = $u.tela; modo = $u.modo; online = $on; ip = $u.ip; ultimo = $u.ultimo }
        $m[$u.nome] = $u.modo
    }
    $script:Estado.usuarios = $l; $script:Estado.acessos = $m
}
Publicar-Usuarios
$script:Quem = ""; $script:ModoReq = ""; $script:Voce = $null
function Abrir-Ouvinte([bool] $Rede) {
    $o = New-Object System.Net.HttpListener
    if ($Rede) { $o.Prefixes.Add("http://+:$Porta/") }
    else { $o.Prefixes.Add("http://localhost:$Porta/"); $o.Prefixes.Add("http://127.0.0.1:$Porta/") }   # casa pelo cabecalho Host
    $o.Start()
    return $o
}
$ouvinte = $null
if ($script:Rede) {
    try { $ouvinte = Abrir-Ouvinte $true }
    catch {
        Escrever-Log "iPad: o Windows nao liberou a porta $Porta para a rede ($($_.Exception.Message)). Rode o LIBERAR-IPAD.bat (como administrador) uma vez. Seguindo SEM iPad." "Yellow"
        $script:Rede = $false
    }
}
if ($null -eq $ouvinte) {
    try { $ouvinte = Abrir-Ouvinte $false } catch {
        Escrever-Log "Nao foi possivel abrir a porta $Porta : $($_.Exception.Message)" "Red"
        Escrever-Log "A porta pode estar em uso (gerenciador ja aberto?). Outra porta: config-graficos.json, porta_gerenciador." "Yellow"
        exit 1
    }
}
$script:Estado.rede = $script:Rede
if ($script:Rede) {
    $ips = @()
    try { $ips = @([Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq "InterNetwork" -and -not [Net.IPAddress]::IsLoopback($_) -and -not $_.ToString().StartsWith("169.254") } | ForEach-Object { $_.ToString() }) } catch { }
    foreach ($ip in $ips) { Escrever-Log "iPad (mesma rede): http://${ip}:$Porta/controle.html  (senha do config)" "Green" }
    $script:Estado.ipad_enderecos = @($ips | ForEach-Object { "http://${_}:$Porta/controle.html" })
}
$PaginaSenha = @'
<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Controle</title>
<style>body{margin:0;background:#0b1220;color:#fff;font:18px 'Segoe UI',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh}
form{background:#131c2c;padding:28px;border-radius:12px;width:min(360px,90vw)}input,button{font:inherit;width:100%;box-sizing:border-box;padding:14px;margin-top:12px;border-radius:8px;border:1px solid #2c3f5e}
button{background:#1f6fc0;color:#fff;font-weight:700}.e{color:#ff8787;margin-top:10px}</style></head><body>
<form method="get" action="/entrar"><b>gctse - CONTROLE DAS TELAS</b><input name="pin" type="password" inputmode="numeric" placeholder="senha" autofocus><button>ENTRAR</button>__ERRO__</form></body></html>
'@

Escrever-Log "gctse GERENCIADOR no ar - HORIZONTAL: http://localhost:$Porta/gerenciador.html?saida=h  |  VERTICAL: http://localhost:$Porta/gerenciador.html?saida=v" "Green"
Escrever-Log "OBS da saida HORIZONTAL: http://localhost:$Porta/saida.html?saida=h  (fonte Navegador 1920x1080)" "Cyan"
Escrever-Log "OBS da saida VERTICAL:   http://localhost:$Porta/saida.html?saida=v&obs=1  (fonte Navegador 1920x1080, ja girada)" "Cyan"
Escrever-Log ("no ar agora: horizontal = {0} | vertical = {1}" -f $script:Estado.h.tela, $script:Estado.v.tela)
Write-Host ""
Write-Host "  Deixe esta janela ABERTA: sem ela as saidas param de trocar." -ForegroundColor Yellow
Write-Host ""
# Dados do TSE que nao vem do boletim ao vivo: se algum ainda nao existe
# nesta maquina, ja busca sozinho (janela minimizada). Desligar no config:
# "atualizar_dados_ao_abrir": false. Atualizar depois: botao "dados do TSE".
if ($script:DadosAoAbrir -and -not $script:Ensaio) {
    $faltam = @()
    if (-not (Test-Path (Join-Path $Raiz "GUARDAR-DADOS-TSE.txt"))) { $faltam += "tse" }
    if (-not (Test-Path (Join-Path $Web "candidatos-genero.js"))) { $faltam += "candidatos" }
    if (-not (Test-Path (Join-Path $Web "perfil-eleitor.js"))) { $faltam += "perfil" }
    if ($faltam.Count) {
        $psExeD = "powershell"
        if ($env:WINDIR -and (Test-Path (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"))) { $psExeD = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe" } elseif (-not (Get-Command "powershell" -ErrorAction SilentlyContinue)) { $psExeD = "pwsh" }
        $argsDA = @{ FilePath = $psExeD; WorkingDirectory = $Raiz; ArgumentList = @(@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + (Join-Path $Raiz "atualizar-dados.ps1") + '"'), "-SemPausa") + $faltam) }
        if ($env:OS -eq "Windows_NT") { $argsDA.WindowStyle = "Minimized" }
        try {
            $pDA = Start-Process @argsDA -PassThru
            [IO.File]::WriteAllText((Join-Path $Raiz "atualizar-dados.json"), (([ordered]@{ rodando = $true; pid = $pDA.Id; inicio = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); etapa = "comecando..."; etapas = @() }) | ConvertTo-Json -Compress))
            Escrever-Log ("dados do TSE ainda nao baixados nesta maquina ({0}): buscando sozinho, janela minimizada" -f ($faltam -join ", ")) "Cyan"
            Evento "info" ("dados do TSE: buscando sozinho o que faltava ({0})" -f ($faltam -join ", "))
        } catch { Escrever-Log "dados do TSE: nao consegui iniciar ($($_.Exception.Message))" "Yellow" }
    }
}
# Abre o gerenciador em DUAS janelas lado a lado (meio a meio na tela):
# esquerda = HORIZONTAL, direita = VERTICAL. Edge ou Chrome em modo "app"
# (sem abas/barra), cada janela com o seu perfil - assim a posicao vale
# mesmo com o navegador ja aberto. Sem Edge/Chrome: o navegador padrao.
function Abrir-Gerenciador {
    $urls = @(@("h", "http://localhost:$Porta/gerenciador.html?saida=h"), @("v", "http://localhost:$Porta/gerenciador.html?saida=v"))
    $nav = $null
    foreach ($c in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                     "$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                     "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) { if ($c -and (Test-Path $c)) { $nav = $c; break } }
    $x0 = 0; $y0 = 0; $larg = 960; $alt = 1040
    try { Add-Type -AssemblyName System.Windows.Forms; $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $x0 = $wa.X; $y0 = $wa.Y; $larg = [int] [math]::Floor($wa.Width / 2); $alt = $wa.Height } catch { }
    $i = 0
    foreach ($par in $urls) {
        try {
            if ($nav -and $env:LOCALAPPDATA) {
                $perfil = Join-Path $env:LOCALAPPDATA ("gctse-gerenciador-" + $par[0])
                Start-Process -FilePath $nav -ArgumentList @(('--user-data-dir="' + $perfil + '"'), "--no-first-run", "--no-default-browser-check", ("--app=" + $par[1]), ("--window-position={0},{1}" -f ($x0 + $i * $larg), $y0), ("--window-size={0},{1}" -f $larg, $alt))
            } else { Start-Process $par[1] }
        } catch { try { Start-Process $par[1] } catch { } }
        $i++
    }
    Escrever-Log "gerenciador aberto em 2 janelas: HORIZONTAL (esquerda) e VERTICAL (direita)" "Green"
}
if ($AbrirPagina) { Abrir-Gerenciador }

$script:Pedido = $null
while ($ouvinte.IsListening) {
    $ctx = $null
    try {
        # espera um pedido sem parar a vigia (a cada 3 s, mesmo sem pagina aberta)
        if ($null -eq $script:Pedido) { $script:Pedido = $ouvinte.GetContextAsync() }
        if (-not $script:Pedido.Wait(1000)) { $script:Quem = ""; try { Vigiar } catch { Escrever-Log "vigia: $($_.Exception.Message)" "Red" }; continue }
        $ctx = $script:Pedido.Result; $script:Pedido = $null
        $req = $ctx.Request
        $caminho = $req.Url.AbsolutePath

        # ---- pedido de OUTRO aparelho (iPad, outro PC): usuario pela senha,
        # e so as rotas que o usuario pode usar. Comandos respeitam o modo dele.
        $script:Quem = ""; $script:ModoReq = ""
        $script:Voce = [ordered]@{ nome = "Operador (exibidor)"; tela = "gerenciador"; modo = "direto"; local = $true }
        $remoto = -not $req.IsLocal
        if ($env:GCTSE_TESTE_IPAD -eq "1" -and $req.Headers["X-Teste-Remoto"] -eq "1") { $remoto = $true }   # so para teste
        if ($remoto) {
            if (-not $script:Rede) { Responder $ctx 403 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("acesso pela rede desligado")); continue }
            $ipR = "$($req.RemoteEndPoint.Address)"
            if ($caminho -eq "/entrar") {
                $pin = "$($req.QueryString['pin'])"
                $uE = @($script:Usuarios | Where-Object { $_.senha -eq $pin }) | Select-Object -First 1
                if ($pin -and $uE) {
                    $ctx.Response.Headers.Add("Set-Cookie", "gctse_pin=$([Uri]::EscapeDataString($pin)); Path=/; Max-Age=2592000")
                    $ctx.Response.Redirect($(if ($uE.tela -eq "gerenciador") { "/gerenciador.html" } else { "/controle.html" }))
                    $uE.visto = Get-Date; $uE.ip = $ipR
                    Evento "info" ("{0} entrou ({1}, {2})" -f $uE.nome, $ipR, $(if ($uE.tela -eq "gerenciador") { "gerenciador" } else { "controle" })); continue
                }
                Escrever-Log "acesso pela rede: senha errada de $ipR" "Yellow"
                Responder $ctx 200 "text/html; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes($PaginaSenha.Replace("__ERRO__", '<div class="e">senha errada</div>'))); continue
            }
            $ck = $req.Cookies["gctse_pin"]
            $u = $null
            if ($null -ne $ck) { $pinC = [Uri]::UnescapeDataString($ck.Value); $u = @($script:Usuarios | Where-Object { $_.senha -eq $pinC }) | Select-Object -First 1 }
            if ($null -eq $u) {
                if ($caminho -eq "/" -or $caminho -like "*.html") { Responder $ctx 200 "text/html; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes($PaginaSenha.Replace("__ERRO__", ""))) }
                else { Responder $ctx 401 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("senha")) }
                continue
            }
            $u.visto = Get-Date; $u.ip = $ipR
            $modoEf = $(if ($script:Estado.travado) { "bloqueado" } else { $u.modo })
            $script:Voce = [ordered]@{ nome = $u.nome; tela = $u.tela; modo = $modoEf; local = $false; travado = [bool] $script:Estado.travado }
            if ($caminho -eq "/") { $ctx.Response.Redirect($(if ($u.tela -eq "gerenciador") { "/gerenciador.html" } else { "/controle.html" })); continue }
            if ($caminho -notmatch '\.') {
                $cmds = $(if ($u.tela -eq "gerenciador") { @("/ipad", "/definir", "/comando", "/rodizio", "/eleito") } else { @("/ipad") })
                if (@("/estado", "/relatorio-dados") -contains $caminho) { }
                elseif ($cmds -contains $caminho) {
                    function Recusar([string] $Msg) { Responder $ctx 423 "application/json; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes((([ordered]@{ erro = $Msg }) | ConvertTo-Json -Compress))) }
                    if ($caminho -eq "/eleito" -and "$($req.QueryString['auto'])") { Recusar "o automatico do presidente eleito so muda no PC do exibidor"; continue }
                    if ($modoEf -eq "bloqueado") { Recusar $(if ($script:Estado.travado) { "o operador TRAVOU os comandos remotos" } else { "seu acesso esta so para ver (o operador pode liberar)" }); continue }
                    if ($modoEf -eq "sugerir") {
                        if ($caminho -eq "/rodizio") {
                            $u.rodSug = [ordered]@{ telas = "$($req.QueryString['telas'])"; tempo = "$($req.QueryString['tempo'])" }
                            Responder-Json $ctx $script:Estado; continue
                        }
                        if ($caminho -eq "/definir") {
                            $sS = "$($req.QueryString['saida'])"; $tS = "$($req.QueryString['tela'])"; $aS = "$($req.QueryString['acao'])"
                            if (($sS -eq "h" -or $sS -eq "v") -and $tS -match '^[a-z0-9-]{1,40}$' -and ($aS -eq "" -or $aS -match '^[a-z0-9:,-]{1,40}$')) {
                                $rS = ""; $tpS = ""
                                if ($u.rodSug -and "$($u.rodSug.telas)" -match '^[a-z0-9:,-]{0,800}$') { $rS = "$($u.rodSug.telas)"; $tpS = "$($u.rodSug.tempo)" }
                                $u.rodSug = $null
                                $script:Estado["sugestao_$sS"] = [ordered]@{ id = "$([DateTime]::Now.Ticks)"; tela = $tS; acao = $aS; rod = $rS; tempo = $tpS; hora = (Get-Date -Format "HH:mm:ss"); quem = $u.nome }
                                $u.ultimo = "{0} sugeriu {1} ({2})" -f (Get-Date -Format "HH:mm:ss"), $tS, $sS.ToUpper()
                                Escrever-Log ("{0} SUGERE - saida {1}: {2} {3} (vai para a previa do operador)" -f $u.nome, $sS.ToUpper(), $tS, $aS) "Cyan"
                                Publicar-Usuarios; Responder-Json $ctx $script:Estado
                            } else { Responder $ctx 400 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("pedido invalido")) }
                            continue
                        }
                        if ($caminho -ne "/ipad") { Recusar "no modo SUGERE so da para sugerir telas (o operador comanda o resto)"; continue }
                    }
                    $script:ModoReq = $(if ($modoEf -eq "sugerir") { "sugerir" } else { "ar" })
                    if ($modoEf -eq "direto") { $script:Quem = $u.nome }
                    $u.ultimo = "{0} {1} {2}" -f (Get-Date -Format "HH:mm:ss"), $caminho.TrimStart('/'), "$($req.QueryString['tela'])$($req.QueryString['acao'])"
                }
                else { Responder $ctx 403 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("so no PC do exibidor")); continue }
            }
        }

        if ($caminho -eq "/ipad") {
            # Troca pedida pelo iPad (controle.html). Modo "ar": vai direto ao
            # ar; modo "sugerir": cai na PREVIA do gerenciador e o operador corta.
            $s = "$($req.QueryString['saida'])"; $tela = "$($req.QueryString['tela'])"; $acao = "$($req.QueryString['acao'])"
            $rod = "$($req.QueryString['rod'])"; $tempo = "$($req.QueryString['tempo'])"
            if (($s -eq "h" -or $s -eq "v") -and $tela -match '^[a-z0-9-]{1,40}$' -and ($acao -eq "" -or $acao -match '^[a-z0-9:,-]{1,40}$') -and $rod -match '^[a-z0-9:,-]{0,800}$' -and ($tempo -eq "" -or $tempo -match '^\d{1,3}$')) {
                $modoIpad = $(if ($script:ModoReq) { $script:ModoReq } else { $script:Estado.ipad })
                if ($modoIpad -eq "ar") {
                    if ($rod) { $script:Estado[$s].rodizio = $rod; $script:Estado[$s].tempo = $(if ($tempo) { [math]::Max(3, [int] $tempo) } else { 0 }) }
                    Por-No-Ar $s $tela $acao "ipad"
                    Escrever-Log ("NO AR ({3}) - saida {0}: {1} {2}" -f $(if ($s -eq "h") { "HORIZONTAL" } else { "VERTICAL" }), $tela, $acao, $(if ($script:Voce.local) { "controle local" } else { $script:Voce.nome })) "Green"
                } else {
                    $script:Estado["sugestao_$s"] = [ordered]@{ id = "$([DateTime]::Now.Ticks)"; tela = $tela; acao = $acao; rod = $rod; tempo = $tempo; hora = (Get-Date -Format "HH:mm:ss"); quem = $(if ($script:Voce.local) { "iPad" } else { $script:Voce.nome }) }
                    Escrever-Log ("iPad SUGERE - saida {0}: {1} {2} (vai para a previa do gerenciador)" -f $s.ToUpper(), $tela, $acao) "Cyan"
                }
                Salvar-Estado
                Responder-Json $ctx $script:Estado
            } else { Responder $ctx 400 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("pedido invalido")) }
            continue
        }
        if ($caminho -eq "/ipadmodo") {
            $m = "$($req.QueryString['m'])"
            if ($m -eq "ar" -or $m -eq "sugerir") { $script:Estado.ipad = $m; foreach ($ul in @($script:Usuarios | Where-Object { $_.legado })) { $ul.modo = $(if ($m -eq "ar") { "direto" } else { "sugerir" }) }; Publicar-Usuarios; Salvar-Estado; Evento "info" ("iPad: {0}" -f $(if ($m -eq "ar") { "coloca NO AR direto" } else { "so SUGERE (cai na previa)" })) }
            Responder-Json $ctx $script:Estado; continue
        }

        if ($caminho -eq "/acesso") {
            # Operador (so neste PC): ?nome=X&modo=direto|sugerir|bloqueado ou ?travar=1|0
            $nA = "$($req.QueryString['nome'])"; $mA = "$($req.QueryString['modo'])"; $tA = "$($req.QueryString['travar'])"
            if ($tA -eq "1" -or $tA -eq "0") {
                $script:Estado.travado = ($tA -eq "1")
                Evento "info" $(if ($tA -eq "1") { "Comandos remotos TRAVADOS pelo operador (iPad e outros PCs so veem)" } else { "Comandos remotos LIBERADOS" })
            }
            $uA = @($script:Usuarios | Where-Object { $_.nome -eq $nA }) | Select-Object -First 1
            if ($uA -and @("direto", "sugerir", "bloqueado") -contains $mA) {
                $uA.modo = $mA
                if ($uA.legado) { $script:Estado.ipad = $(if ($mA -eq "direto") { "ar" } else { "sugerir" }) }
                Evento "info" ("{0}: {1}" -f $uA.nome, $(switch ($mA) { "direto" { "comandos vao DIRETO ao ar" } "sugerir" { "so SUGERE (cai na previa do operador)" } default { "BLOQUEADO (so ve)" } }))
            }
            Publicar-Usuarios; Salvar-Estado
            Responder-Json $ctx $script:Estado; continue
        }

        if ($caminho -eq "/estado") {
            Publicar-Usuarios
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
        elseif ($caminho -eq "/dados") {
            # DADOS DO TSE: roda o atualizar-dados.ps1 (guardar copia do TSE,
            # importar candidatos e perfil do eleitor) numa janela minimizada.
            # ?rodar=tudo|tse|candidatos|perfil  ou  ?rodar=codigos (abre a
            # janela do CODIGOS-2-TURNO, que pede confirmacao). Sem ?rodar so
            # devolve a situacao.
            $rodar = "$($req.QueryString['rodar'])"; $msgD = ""
            $stD = Ler-Situacao-Dados
            if ($rodar) {
                $psExe = "powershell"
                if ($env:WINDIR -and (Test-Path (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"))) { $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe" } elseif (-not (Get-Command "powershell" -ErrorAction SilentlyContinue)) { $psExe = "pwsh" }
                if ($script:Ensaio) { $msgD = "no ENSAIO os dados do TSE nao sao baixados (use o gerenciador de verdade)" }
                elseif ($rodar -eq "codigos") {
                    try { Start-Process -FilePath (Join-Path $Raiz "CODIGOS-2-TURNO.bat") -WorkingDirectory $Raiz; $msgD = "janela CODIGOS DO 2o TURNO aberta: confira e responda S para gravar" }
                    catch { $msgD = "nao abriu: $($_.Exception.Message)" }
                    Escrever-Log "dados do TSE: CODIGOS-2-TURNO aberto pelo gerenciador" "Green"
                }
                elseif (@("tudo", "tse", "candidatos", "perfil") -notcontains $rodar) { $msgD = "pedido invalido" }
                elseif ($stD.rodando) { $msgD = "ja esta rodando: " + $stD.etapa }
                else {
                    $argsD = @{ FilePath = $psExe; WorkingDirectory = $Raiz; ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + (Join-Path $Raiz "atualizar-dados.ps1") + '"'), "-SemPausa", $rodar) }
                    if ($env:OS -eq "Windows_NT") { $argsD.WindowStyle = "Minimized" }
                    try {
                        $pD = Start-Process @argsD -PassThru
                        [IO.File]::WriteAllText((Join-Path $Raiz "atualizar-dados.json"), (([ordered]@{ rodando = $true; pid = $pD.Id; inicio = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); etapa = "comecando..."; etapas = @() }) | ConvertTo-Json -Compress))
                        $msgD = "iniciado: $rodar"
                        Evento "info" ("dados do TSE: atualizacao iniciada ({0})" -f $rodar)
                    } catch { $msgD = "nao abriu: $($_.Exception.Message)" }
                }
                $stD = Ler-Situacao-Dados
            }
            $stD.mensagem = $msgD
            Responder $ctx 200 "application/json; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes(($stD | ConvertTo-Json -Depth 6 -Compress)))
        }
        elseif ($caminho -eq "/copia") {
            # Copia de seguranca (copia-seguranca.ps1) num clique. ?ver=1 so
            # devolve como foi a ultima.
            $arqCopia = Join-Path $Raiz "copia-seguranca.json"
            if ("$($req.QueryString['ver'])" -ne "1") {
                $psExe = "powershell"
                if ($env:WINDIR -and (Test-Path (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"))) { $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe" } elseif (-not (Get-Command "powershell" -ErrorAction SilentlyContinue)) { $psExe = "pwsh" }
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
                $deSug = "$($req.QueryString['de'])"
                Registrar-NoAr $s $tela $acao $(if ($deSug -match '^[^<>;"]{1,30}$') { "painel (sugestao de $deSug)" } else { "painel" })
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
