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
$script:JanelasGer = 2   # "janelas_gerenciador": 2 = H e V lado a lado; 1 = uma janela com as duas
$script:AbrirMonitor = $true   # "abrir_monitor": false = nao abre a janela MONITOR (NO AR + PREVIA)
try {
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Name -eq "ensaio" -and $p.Value -eq $true) { $script:Ensaio = $true }
        if ($p.Name -eq "presidente_eleito_no_ar" -and $p.Value -eq $false) { $script:EleitoAuto = $false }
        if ($p.Name -eq "reabrir_coletas" -and $p.Value -eq $false) { $script:Reabrir = $false }
        if ($p.Name -eq "atualizar_dados_ao_abrir" -and $p.Value -eq $false) { $script:DadosAoAbrir = $false }
        if ($p.Name -eq "janelas_gerenciador" -and "$($p.Value)" -eq "1") { $script:JanelasGer = 1 }
        if ($p.Name -eq "abrir_monitor" -and $p.Value -eq $false) { $script:AbrirMonitor = $false }
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
    semTse = $false; viSemEleito = $false; reabriuP = [datetime]::MinValue; reabriuE = [datetime]::MinValue; nomes = @{}
    marcos = @{}; marcosP = $false; marcosE = $false; govLider = @{} }
# MARCOS DA APURACAO (avisos para a bancada e o operador): cada um uma vez
# por eleicao. O que ja tinha passado quando o gerenciador abriu NAO avisa.
$script:Grandes = @("sp", "mg", "rj", "ba", "pr", "rs")
function Marco([string] $Chave, [string] $Texto, [bool] $Calado) {
    if ($script:Vigia.marcos.ContainsKey($Chave)) { return }
    $script:Vigia.marcos[$Chave] = $true
    if (-not $Calado) { Evento "marco" $Texto }
}
function Pct-Txt([double] $v) { return $v.ToString("0.0", [Globalization.CultureInfo]::InvariantCulture).Replace(".", ",") }
function Vigiar-Estados {
    $arq = Join-Path $Web "estados.js"
    if (-not (Test-Path $arq)) { return }
    $quando = (Get-Item $arq).LastWriteTime
    if ($quando -eq $script:Vigia.lidoE) { return }
    $d = $null
    try { $d = Ler-Js "estados.js" } catch { return }
    if ($null -eq $d) { return }
    $script:Vigia.lidoE = $quando
    $calado = -not $script:Vigia.marcosE; $script:Vigia.marcosE = $true
    $ufs = Prop $d "ufs"; if ($null -eq $ufs) { return }
    foreach ($p in $ufs.PSObject.Properties) {
        $k = $p.Name; $g = Prop $p.Value "gov"
        if ($null -eq $g -or -not (Prop $g "tem") -or [int] (Prop $g "turno") -ne 2) { continue }
        $ele = "$(Prop $g 'eleicao')"
        $cs = @(Lista-De (Prop $g "candidatos") | Where-Object { $null -ne $_ })
        $el = @($cs | Where-Object { (Prop $_ "eleito") -eq $true }) | Select-Object -First 1
        if ($null -ne $el) { Marco "gov-eleito|$ele|$k" ("GOVERNADOR ELEITO em {0}: {1} ({2}%)" -f $k.ToUpper(), "$(Prop $el 'nome')", (Pct-Txt ([double] (Prop $el 'pct')))) $calado }
        # virada no governador do 2o turno
        $l = Lider $g
        if ($null -ne $l) {
            $num = "$(Prop $l 'numero')"; $ch = "$ele|$k"; $pu = [double] (Prop $g "urnas_pct")
            if ($script:Vigia.govLider.ContainsKey($ch) -and $script:Vigia.govLider[$ch][0] -ne $num -and $pu -ge 1 -and -not $calado) {
                Evento "virada" ("VIROU GOVERNADOR {0}: {1} passou {2} ({3}% das urnas)" -f $k.ToUpper(), "$(Prop $l 'nome')", $script:Vigia.govLider[$ch][1], (Pct-Txt $pu))
            }
            $script:Vigia.govLider[$ch] = @($num, "$(Prop $l 'nome')")
        }
    }
}
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
    try { Vigiar-Estados } catch { }
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
    # ---- MARCOS: Brasil 25/50/75/90/100% e os 6 maiores eleitorados a 90%
    $caladoP = -not $script:Vigia.marcosP; $script:Vigia.marcosP = $true
    foreach ($m in @(25, 50, 75, 90, 100)) {
        if ($pctBr -ge $m) {
            $lb = Lider $br; $ld = ""
            if ($null -ne $lb) { $ld = " - lidera {0} ({1}%)" -f "$(Prop $lb 'nome')", (Pct-Txt ([double] (Prop $lb 'pct'))) }
            Marco "br$m|$eleicao" ("{0}% DAS URNAS APURADAS NO BRASIL{1}" -f $m, $ld) $caladoP
        }
    }
    $ufsM = Prop $d "ufs"
    foreach ($k in $script:Grandes) {
        $ab = Prop $ufsM $k; if ($null -eq $ab) { continue }
        $pu = [double] (Prop (Prop $ab "secoes") "pct")
        if ($pu -ge 90) {
            $lu = Lider $ab; $ld = ""
            if ($null -ne $lu) { $ld = ": lidera {0} ({1}%)" -f "$(Prop $lu 'nome')", (Pct-Txt ([double] (Prop $lu 'pct'))) }
            Marco "uf90|$eleicao|$k" ("{0} PASSOU DE 90% DAS URNAS{1}" -f $k.ToUpper(), $ld) $caladoP
        }
    }
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

# SO NESTE PC: o gerenciador atende so o proprio exibidor (localhost). O
# acesso pela rede (iPad, outros PCs) foi retirado na 3.24.
$script:Rede = $false
$script:Estado.ipad = "sugerir"
$script:Estado.sugestao_h = $null; $script:Estado.sugestao_v = $null
$script:Estado.travado = $false
$script:Estado.usuarios = @(); $script:Estado.acessos = [ordered]@{}
$script:Quem = ""; $script:ModoReq = ""; $script:Voce = $null
$ouvinte = New-Object System.Net.HttpListener
$ouvinte.Prefixes.Add("http://localhost:$Porta/"); $ouvinte.Prefixes.Add("http://127.0.0.1:$Porta/")   # casa pelo cabecalho Host
try { $ouvinte.Start() } catch {
    Escrever-Log "Nao foi possivel abrir a porta $Porta : $($_.Exception.Message)" "Red"
    Escrever-Log "A porta pode estar em uso (gerenciador ja aberto?). Outra porta: config-graficos.json, porta_gerenciador." "Yellow"
    exit 1
}
$script:Estado.rede = $false
$script:Estado.pvw = [ordered]@{ h = $null; v = $null }; $script:Estado.pvw_ligada = [ordered]@{ h = $false; v = $false }   # janela MONITOR

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
# Abre o gerenciador em DUAS janelas lado a lado (meio a meio na tela)
# ou, com "janelas_gerenciador": 1 no config, numa janela so (tela inteira):
# esquerda = HORIZONTAL, direita = VERTICAL. Edge ou Chrome em modo "app"
# (sem abas/barra), cada janela com o seu perfil - assim a posicao vale
# mesmo com o navegador ja aberto. Sem Edge/Chrome: o navegador padrao.
function Abrir-Gerenciador {
    $urls = @(@("h", "http://localhost:$Porta/gerenciador.html?saida=h"), @("v", "http://localhost:$Porta/gerenciador.html?saida=v"))
    if ($script:JanelasGer -eq 1) { $urls = @(, @("hv", "http://localhost:$Porta/gerenciador.html")) }
    $nav = $null
    foreach ($c in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                     "$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                     "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) { if ($c -and (Test-Path $c)) { $nav = $c; break } }
    $x0 = 0; $y0 = 0; $larg = 960; $alt = 1040
    try { Add-Type -AssemblyName System.Windows.Forms; $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $x0 = $wa.X; $y0 = $wa.Y; $larg = [int] [math]::Floor($wa.Width / $urls.Count); $alt = $wa.Height } catch { }
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
    # MONITOR (NO AR + PREVIA das duas saidas): no 2o monitor, se houver;
    # senao por cima do painel (arraste para onde quiser).
    if ($script:AbrirMonitor) {
        $mx = $x0 + 40; $my = $y0 + 40; $mw = 1400; $mh = 860
        try { $tel = @([System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary }); if ($tel.Count) { $a2 = $tel[0].WorkingArea; $mx = $a2.X; $my = $a2.Y; $mw = $a2.Width; $mh = $a2.Height } } catch { }
        $urlM = "http://localhost:$Porta/monitor.html"
        try {
            if ($nav -and $env:LOCALAPPDATA) {
                Start-Process -FilePath $nav -ArgumentList @(('--user-data-dir="' + (Join-Path $env:LOCALAPPDATA "gctse-monitor") + '"'), "--no-first-run", "--no-default-browser-check", ("--app=" + $urlM), ("--window-position={0},{1}" -f $mx, $my), ("--window-size={0},{1}" -f $mw, $mh))
            } else { Start-Process $urlM }
        } catch { try { Start-Process $urlM } catch { } }
        Escrever-Log "janela MONITOR aberta (NO AR e PREVIA das duas saidas): $urlM" "Green"
    }
    if ($urls.Count -eq 1) { Escrever-Log "gerenciador aberto em 1 janela (HORIZONTAL e VERTICAL juntas)" "Green" }
    else { Escrever-Log "gerenciador aberto em 2 janelas: HORIZONTAL (esquerda) e VERTICAL (direita)" "Green" }
}
# CODIGOS DO 2o TURNO: confere sozinho (ao abrir e a cada 30 min) a lista de
# eleicoes do TSE (comum/config/ele-c.json, pleito de 25/10/2026: cargo 1 =
# Presidente, cargo 3 = Governador) com o config. NAO grava nada: o painel
# avisa e o botao abre o CODIGOS-2-TURNO.bat (que pede S para gravar).
$script:Estado.codigos = $null
$script:ProxCodigos = [datetime]::MinValue
function Checar-Codigos {
    if ((Get-Date) -lt $script:ProxCodigos) { return }
    $script:ProxCodigos = (Get-Date).AddMinutes(30)
    $tc = Prop $cfg "tse"; $baseC = "$(Prop $tc 'base_url')".TrimEnd('/')
    $rc = [ordered]@{ quando = (Get-Date -Format "HH:mm"); config_pres = "$(Prop $tc 'eleicao_presidente')"; config_gov = "$(Prop $tc 'eleicao_estaduais')"; tse_pres = ""; tse_gov = ""; situacao = "" }
    try {
        $respC = Invoke-WebRequest -Uri "$baseC/comum/config/ele-c.json" -TimeoutSec 10 -UseBasicParsing -Headers @{ "User-Agent" = "gctse-graficos/1.0"; "Accept" = "application/json,*/*" }
        $listaC = [Text.Encoding]::UTF8.GetString($respC.RawContentStream.ToArray()) | ConvertFrom-Json
        foreach ($plC in @(Prop $listaC "pl")) {
            if ($null -eq $plC -or "$(Prop $plC 'dt')" -notlike "*25/10/2026*") { continue }
            foreach ($elC in @(Prop $plC "e")) {
                if ($null -eq $elC) { continue }
                $cargosC = @(); foreach ($abC in @(Prop $elC "abr")) { foreach ($cpC in @(Prop $abC "cp")) { if ($null -ne $cpC) { $cargosC += "$(Prop $cpC 'cd')" } } }
                if ($cargosC -contains "1" -and -not $rc.tse_pres) { $rc.tse_pres = "$(Prop $elC 'cd')" }
                if ($cargosC -contains "3" -and -not $rc.tse_gov) { $rc.tse_gov = "$(Prop $elC 'cd')" }
            }
        }
        if (-not $rc.tse_pres) { $rc.situacao = "tse_sem_2t" }
        elseif ($rc.tse_pres -eq $rc.config_pres -and $rc.tse_gov -eq $rc.config_gov) { $rc.situacao = "ok" }
        else {
            $rc.situacao = "diferente"
            if ($null -eq $script:Estado.codigos -or $script:Estado.codigos.situacao -ne "diferente") { Evento "alerta" ("CODIGOS DO 2o TURNO: o TSE usa {0}/{1} e o config esta com {2}/{3} - rode o CODIGOS-2-TURNO (botao no painel)" -f $rc.tse_pres, $rc.tse_gov, $rc.config_pres, $rc.config_gov) }
        }
    } catch { $rc.situacao = "sem_resposta" }
    $script:Estado.codigos = $rc
    Escrever-Log ("codigos do 2o turno: TSE {0}/{1} | config {2}/{3} -> {4}" -f $(if ($rc.tse_pres) { $rc.tse_pres } else { "-" }), $(if ($rc.tse_gov) { $rc.tse_gov } else { "-" }), $rc.config_pres, $rc.config_gov, $rc.situacao) $(if ($rc.situacao -eq "ok") { "Green" } else { "Yellow" })
}
try { Checar-Codigos } catch { }
if ($AbrirPagina) { Abrir-Gerenciador }

$script:Pedido = $null
while ($ouvinte.IsListening) {
    $ctx = $null
    try {
        # espera um pedido sem parar a vigia (a cada 3 s, mesmo sem pagina aberta)
        if ($null -eq $script:Pedido) { $script:Pedido = $ouvinte.GetContextAsync() }
        if (-not $script:Pedido.Wait(1000)) { $script:Quem = ""; try { Checar-Codigos } catch { }; try { Vigiar } catch { Escrever-Log "vigia: $($_.Exception.Message)" "Red" }; continue }
        $ctx = $script:Pedido.Result; $script:Pedido = $null
        $req = $ctx.Request
        $caminho = $req.Url.AbsolutePath

        # so o operador deste PC (o servidor escuta so localhost)
        $script:Quem = ""; $script:ModoReq = ""
        $script:Voce = [ordered]@{ nome = "Operador (exibidor)"; tela = "gerenciador"; modo = "direto"; local = $true }

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
        elseif ($caminho -eq "/pvw") {
            # PREVIA de cada saida (o que esta selecionado e ainda nao foi ao
            # ar), para a janela MONITOR. Nao vai ao ar e nao fica gravado.
            $s = "$($req.QueryString['saida'])"; $tela = "$($req.QueryString['tela'])"; $acao = "$($req.QueryString['acao'])"
            $rodP = "$($req.QueryString['rodizio'])"; $tempoP = "$($req.QueryString['tempo'])"
            if (($s -eq "h" -or $s -eq "v") -and ($tela -eq "" -or $tela -match '^[a-z0-9-]{1,40}$') -and ($acao -eq "" -or $acao -match '^[a-z0-9:,-]{1,40}$') -and
                ($rodP -eq "" -or $rodP -match '^[a-z0-9:,-]{1,2000}$') -and ($tempoP -eq "" -or $tempoP -match '^\d{1,3}$')) {
                if ($null -eq $script:Estado.pvw) { $script:Estado.pvw = [ordered]@{ h = $null; v = $null } }
                if ($tela) { $script:Estado.pvw[$s] = [ordered]@{ tela = $tela; acao = $acao; rodizio = $rodP; tempo = $tempoP; nome = "$($req.QueryString['nome'])".Substring(0, [math]::Min(80, "$($req.QueryString['nome'])".Length)); quando = (Get-Date -Format "HH:mm:ss") } }
                else { $script:Estado.pvw[$s] = $null }
                $pl = $script:Estado.pvw_ligada; if ($null -eq $pl) { $pl = [ordered]@{ h = $false; v = $false }; $script:Estado.pvw_ligada = $pl }
                $pl[$s] = ("$($req.QueryString['ligada'])" -eq "1")
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
