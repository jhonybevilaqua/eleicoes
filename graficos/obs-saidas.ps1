<#
    gctse GRAFICOS - OBS DAS SAIDAS DA DECKLINK (automatico)

    Chamado pelo GERENCIADOR.bat (ou ABRIR-OBS.bat). Sozinho:
      1. acha o OBS instalado nesta maquina (Arquivos de Programas)
      2. na 1a vez, faz duas copias dele em <disco>\GCTSE-OBS\horizontal e
         \vertical (cada saida da DeckLink com o seu OBS e a sua
         configuracao - o canal de uma nao se mistura com o da outra)
      3. escreve a configuracao: cena SAIDA, fonte Navegador 1920x1080 com
         o endereco do gerenciador, video 1920x1080, sem audio
      4. espera o gerenciador responder e abre os dois OBS
    O canal da DeckLink e escolhido UMA vez em cada OBS (Ferramentas >
    Saida DeckLink, "Iniciar automaticamente"); depois disso o OBS abre
    minimizado e liga a saida sozinho.
#>

[CmdletBinding()]
param([switch] $Auto)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
$script:Problema = $false

function Escrever-Log {
    param([string] $Texto, [string] $Cor = "Gray")
    $linha = "{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $Texto
    Write-Host $linha -ForegroundColor $Cor
    if ($Cor -eq "Red" -or $Cor -eq "Yellow") { $script:Problema = $true }
    try {
        if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" | Out-Null }
        Add-Content -Path (Join-Path "logs" ("obs-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))) -Value $linha -Encoding UTF8
    } catch { }
}

function Gravar-Texto {
    # UTF-8 sem BOM (o OBS le .ini e .json assim)
    param([string] $Caminho, [string] $Texto)
    $pasta = Split-Path -Parent $Caminho
    if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    [IO.File]::WriteAllText($Caminho, $Texto, (New-Object System.Text.UTF8Encoding($false)))
}

# ------------------------------------------------------------ configuracao

$Porta = 8098
$Fps = "29.97"
$ObsPastaCfg = ""
$DestinoCfg = ""
try {
    $cfg = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Name -eq "porta_gerenciador" -and [int] $p.Value -gt 0) { $Porta = [int] $p.Value }
        if ($p.Name -eq "obs_fps" -and @("29.97", "59.94", "30", "60", "25", "50") -contains "$($p.Value)") { $Fps = "$($p.Value)" }
        if ($p.Name -eq "obs_instalado" -and "$($p.Value)" -ne "") { $ObsPastaCfg = "$($p.Value)" }
        if ($p.Name -eq "obs_copias" -and "$($p.Value)" -ne "") { $DestinoCfg = "$($p.Value)" }
    }
} catch { }
if ($Fps -eq "25") { $Fps = "25 PAL" }
if ($Fps -eq "50") { $Fps = "50 PAL" }

# Pasta das copias: raiz do disco desta pasta (ex.: D:\GCTSE-OBS). So
# letras simples no caminho (o navegador do OBS nao gosta de acento).
$Destino = $DestinoCfg
if ($Destino -eq "") {
    $disco = ""
    try { $disco = Split-Path -Qualifier $Raiz } catch { }
    if ($disco -notmatch '^[A-Za-z]:$') { $disco = $env:SystemDrive }
    $Destino = $disco + "\GCTSE-OBS"
}
$Destino = $Destino.TrimEnd('\')
if ($Destino -notmatch '^[A-Za-z]:\\[A-Za-z0-9\\ _.-]+$') { $Destino = $env:SystemDrive + "\GCTSE-OBS" }

$Saidas = @(
    @{ id = "h"; nome = "SAIDA-HORIZONTAL"; titulo = "HORIZONTAL"; pasta = ($Destino + "\horizontal"); url = "http://localhost:$Porta/saida.html?saida=h" },
    @{ id = "v"; nome = "SAIDA-VERTICAL";   titulo = "VERTICAL";   pasta = ($Destino + "\vertical");   url = "http://localhost:$Porta/saida.html?saida=v&obs=1" }
)

# ------------------------------------------------------- achar o OBS instalado

function Tem-Obs([string] $Pasta) {
    # sem Join-Path: ele da erro se o disco (ex.: D:) nao existir
    if (-not $Pasta) { return $false }
    try { return [bool] (Test-Path -LiteralPath ($Pasta.TrimEnd('\') + "\bin\64bit\obs64.exe")) } catch { return $false }
}
function Achar-Obs {
    $cands = New-Object System.Collections.Generic.List[string]
    if ($ObsPastaCfg) { $cands.Add($ObsPastaCfg) }
    foreach ($chave in @("HKLM:\SOFTWARE\OBS Studio", "HKLM:\SOFTWARE\WOW6432Node\OBS Studio", "HKCU:\SOFTWARE\OBS Studio")) {
        try {
            $item = Get-ItemProperty -Path $chave -ErrorAction Stop
            foreach ($p in $item.PSObject.Properties) { if ($p.Name -eq "(default)" -and "$($p.Value)" -ne "") { $cands.Add("$($p.Value)") } }
        } catch { }
    }
    foreach ($pf in @($env:ProgramFiles, $env:ProgramW6432, ${env:ProgramFiles(x86)}, "C:\Program Files", "D:\Program Files")) {
        if ($pf) {
            $cands.Add($pf.TrimEnd('\') + "\obs-studio")
            $cands.Add($pf.TrimEnd('\') + "\Steam\steamapps\common\OBS Studio")
        }
    }
    foreach ($c in $cands) {
        try { if ((Tem-Obs $c) -and -not ($c.TrimEnd('\').StartsWith($Destino, [StringComparison]::OrdinalIgnoreCase))) { return $c.TrimEnd('\') } } catch { }
    }
    # OBS aberto agora (instalado em outro lugar)
    try {
        foreach ($pr in @(Get-Process -Name obs64 -ErrorAction Stop)) {
            $exe = $null
            try { $exe = $pr.Path } catch { }
            if ($exe -and -not $exe.StartsWith($Destino, [StringComparison]::OrdinalIgnoreCase)) {
                $r = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $exe))
                if (Tem-Obs $r) { return $r }
            }
        }
    } catch { }
    return $null
}

# --------------------------------------------------------------- copiar

function Tamanho-Pasta([string] $Pasta) {
    $s = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $Pasta -Recurse -File -Force -ErrorAction SilentlyContinue)) { $s += $f.Length }
    return $s
}
function Copiar-Obs([string] $Origem, [string] $Pasta) {
    $precisa = (Tamanho-Pasta $Origem) + 200MB
    try {
        $drive = New-Object System.IO.DriveInfo((Split-Path -Qualifier $Pasta))
        if ($drive.AvailableFreeSpace -lt $precisa) {
            Escrever-Log ("Pouco espaco em {0}: precisa de {1:N0} MB livres." -f $drive.Name, ($precisa / 1MB)) "Red"
            return $false
        }
    } catch { }
    Escrever-Log ("Copiando o OBS para {0} (so na 1a vez, ~1 minuto)..." -f $Pasta) "Cyan"
    if (-not (Test-Path $Pasta)) { New-Item -ItemType Directory -Path $Pasta -Force | Out-Null }
    & robocopy.exe $Origem $Pasta /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD (Join-Path $Origem "config") | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8 -or -not (Tem-Obs $Pasta)) {
        Escrever-Log ("Falha ao copiar o OBS (robocopy {0})." -f $rc) "Red"
        return $false
    }
    Gravar-Texto (Join-Path $Pasta "portable_mode.txt") "gctse"
    return $true
}

# ------------------------------------------------------- configuracao do OBS

function Configurar-Obs($S) {
    $cfgDir = Join-Path $S.pasta "config\obs-studio"
    $basicoIni = @"
[General]
FirstRun=true
EnableAutoUpdates=false

[Basic]
Profile=$($S.nome)
ProfileDir=$($S.nome)
SceneCollection=$($S.nome)
SceneCollectionFile=$($S.nome)
ConfigOnNewProfile=false

[BasicWindow]
SysTrayEnabled=true
SysTrayWhenStarted=false
"@
    # global.ini / user.ini: so na 1a vez (o OBS guarda coisas dele ali)
    foreach ($ini in @("global.ini", "user.ini")) {
        $arq = Join-Path $cfgDir $ini
        if (-not (Test-Path $arq)) { Gravar-Texto $arq $basicoIni }
    }

    # Perfil e cena: so na 1a vez. Depois, o que foi ajustado no OBS (FPS
    # igual ao modo da DeckLink, fonte, filtros) fica como esta.
    $arqPerfil = Join-Path $cfgDir ("basic\profiles\{0}\basic.ini" -f $S.nome)
    $arqCena = Join-Path $cfgDir ("basic\scenes\{0}.json" -f $S.nome)
    if ((Test-Path $arqPerfil) -and (Test-Path $arqCena)) { return }

    # Perfil: video 1920x1080 no FPS da mesa, audio 48 kHz.
    if (-not (Test-Path $arqPerfil)) { Gravar-Texto $arqPerfil @"
[General]
Name=$($S.nome)

[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
FPSType=0
FPSCommon=$Fps
ScaleType=bicubic
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial

[Audio]
SampleRate=48000
ChannelSetup=Stereo

[Output]
Mode=Simple
"@ }

    # Cena: uma fonte Navegador em tela cheia, travada, muda (sem audio
    # do Windows: a colecao nao tem "Audio do desktop" nem "Mic").
    $item = [ordered]@{
        name = "GCTSE"; visible = $true; locked = $true; rot = 0
        pos = [ordered]@{ x = 0; y = 0 }; scale = [ordered]@{ x = 1; y = 1 }
        align = 5; bounds_type = 0; bounds_align = 0; bounds = [ordered]@{ x = 0; y = 0 }
        crop_left = 0; crop_top = 0; crop_right = 0; crop_bottom = 0
        id = 1; group_item_backup = $false; scale_filter = "disable"
        blend_method = "default"; blend_type = "normal"; private_settings = @{}
    }
    $cena = [ordered]@{
        name = "SAIDA"; id = "scene"; versioned_id = "scene"; enabled = $true; muted = $false
        flags = 0; volume = 1; mixers = 0; sync = 0; monitoring_type = 0
        settings = [ordered]@{ custom_size = $false; id_counter = 1; items = @($item) }
        private_settings = @{}; hotkeys = @{}; filters = @()
    }
    $fonte = [ordered]@{
        name = "GCTSE"; id = "browser_source"; versioned_id = "browser_source"; enabled = $true; muted = $true
        flags = 0; volume = 1; mixers = 0; sync = 0; monitoring_type = 0
        settings = [ordered]@{
            url = $S.url; is_local_file = $false; width = 1920; height = 1080
            fps_custom = $false; reroute_audio = $true; shutdown = $false; restart_when_active = $false
            css = "body { background-color: #0b1220; margin: 0px auto; overflow: hidden; }"
        }
        private_settings = @{}; hotkeys = @{}; filters = @()
    }
    $colecao = [ordered]@{
        name = $S.nome
        current_scene = "SAIDA"; current_program_scene = "SAIDA"
        scene_order = @([ordered]@{ name = "SAIDA" })
        sources = @($cena, $fonte)
        groups = @(); transitions = @(); quick_transitions = @(); saved_projectors = @()
        current_transition = "Fade"; transition_duration = 300
        preview_locked = $false; scaling_enabled = $false; modules = @{}
    }
    if (-not (Test-Path $arqCena)) { Gravar-Texto $arqCena ($colecao | ConvertTo-Json -Depth 10) }
}

function Exe-Obs($S) { return (Join-Path $S.pasta "bin\64bit\obs64.exe") }
function Obs-Aberto($S) {
    $exe = Exe-Obs $S
    foreach ($pr in @(Get-Process -Name obs64 -ErrorAction SilentlyContinue)) {
        $c = $null
        try { $c = $pr.Path } catch { }
        if ($c -and [string]::Equals($c, $exe, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
function DeckLink-Escolhida($S) {
    $arq = Join-Path $S.pasta "config\obs-studio\plugin_config\decklink-output-ui\decklinkOutputProps.json"
    if (-not (Test-Path $arq)) { return $false }
    try { return ((Get-Content $arq -Raw) -match '"auto_start"\s*:\s*true') } catch { return $false }
}

# ------------------------------------------------------------------ rodar

Escrever-Log "gctse - OBS das saidas da DeckLink" "Green"

$faltaCopia = @($Saidas | Where-Object { -not (Tem-Obs $_.pasta) })
if ($faltaCopia.Count -gt 0) {
    $origem = Achar-Obs
    if (-not $origem) {
        Escrever-Log "Nao achei o OBS instalado nesta maquina." "Yellow"
        Escrever-Log "Instale o OBS Studio (obsproject.com) e abra o GERENCIADOR.bat de novo." "Yellow"
        Escrever-Log "Enquanto isso: capture a janela do navegador (ENDERECOS-OBS.bat)." "Yellow"
    } else {
        Escrever-Log ("OBS instalado: {0}" -f $origem)
        foreach ($S in $faltaCopia) { [void] (Copiar-Obs $origem $S.pasta) }
    }
}

$prontas = @($Saidas | Where-Object { Tem-Obs $_.pasta })
if ($prontas.Count -gt 0) {
    # So abre o OBS com o gerenciador no ar (senao a fonte mostra erro).
    # (conexao direta na porta: nao passa por proxy do Windows)
    $noAr = $false
    for ($i = 0; $i -lt 60 -and -not $noAr; $i++) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try { $tcp.Connect("127.0.0.1", $Porta); $noAr = $true } catch { Start-Sleep -Seconds 1 } finally { $tcp.Close() }
    }
    if (-not $noAr) { Escrever-Log "O gerenciador nao respondeu em 60 s; abrindo o OBS mesmo assim (se a fonte mostrar erro: botao direito > Atualizar)." "Yellow" }

    foreach ($S in $prontas) {
        if (Obs-Aberto $S) { Escrever-Log ("OBS {0} ja esta aberto." -f $S.titulo); continue }
        try {
            Configurar-Obs $S
            $argumentos = @("--portable", "--multi", "--disable-shutdown-check", "--disable-updater", "--profile", $S.nome, "--collection", $S.nome)
            $pronta = DeckLink-Escolhida $S
            if ($pronta) { $argumentos += "--minimize-to-tray" }
            $exe = Exe-Obs $S
            Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -ArgumentList $argumentos | Out-Null
            if ($pronta) {
                Escrever-Log ("OBS {0} aberto (minimizado, perto do relogio) - saida DeckLink liga sozinha." -f $S.titulo) "Green"
            } else {
                Escrever-Log ("OBS {0} aberto. FALTA (uma vez): Ferramentas > Saida DeckLink > escolher o canal da saida {0}," -f $S.titulo) "Yellow"
                Escrever-Log "   modo = formato da mesa, marcar 'Iniciar automaticamente', INICIAR." "Yellow"
            }
            Start-Sleep -Seconds 3
        } catch {
            Escrever-Log ("Falha ao abrir o OBS {0}: {1}" -f $S.titulo, $_.Exception.Message) "Red"
        }
    }
}

# Situacao para a tela do gerenciador.
try {
    $sit = [ordered]@{}
    foreach ($S in $Saidas) { $sit[$S.id] = [ordered]@{ exe = (Exe-Obs $S); instalado = [bool] (Tem-Obs $S.pasta) } }
    Gravar-Texto (Join-Path $Raiz "obs-saidas.json") ($sit | ConvertTo-Json -Depth 4)
} catch { }

if ($Auto) {
    # janela fecha sozinha; com aviso, fica 30 s para dar tempo de ler
    if ($script:Problema) { Start-Sleep -Seconds 30 } else { Start-Sleep -Seconds 4 }
}
