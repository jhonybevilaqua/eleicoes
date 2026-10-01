<#
    gctse GRAFICOS - abre a APRESENTACAO em tela cheia e fica VIGIANDO:
    se o navegador fechar ou cair, reabre sozinho em 10 segundos.

    Chamado pelo APRESENTACAO-HORIZONTAL.bat / APRESENTACAO-VERTICAL.bat.
    Se a coleta (GRAFICOS.bat) nao estiver rodando nesta maquina, abre ela
    tambem - cada computador precisa da sua.
#>

[CmdletBinding()]
param(
    [string] $Formato = "h",
    [int] $MonitorX = 0,
    [int] $MonitorY = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# Um clique na janela preta a poe em modo "Selecionar" e CONGELA o programa.
if ($env:OS -eq "Windows_NT") {
    try {
        Add-Type -Namespace GcTseApresentacao -Name JanelaConsole -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $entradaConsole = [GcTseApresentacao.JanelaConsole]::GetStdHandle(-10)
        [uint32] $modoConsole = 0
        if ([GcTseApresentacao.JanelaConsole]::GetConsoleMode($entradaConsole, [ref] $modoConsole)) {
            if (($modoConsole -band 0x40) -ne 0) { $modoConsole = $modoConsole - 0x40 }
            $modoConsole = $modoConsole -bor 0x80
            [void] [GcTseApresentacao.JanelaConsole]::SetConsoleMode($entradaConsole, $modoConsole)
        }
    } catch { }
}

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
$NomeFormato = "horizontal"
if ($Formato -eq "v") { $NomeFormato = "vertical" }
try { $Host.UI.RawUI.WindowTitle = "gctse APRESENTACAO $($NomeFormato.ToUpper()) - deixe esta janela aberta" } catch { }

function Escrever-Log {
    param([string] $Texto, [string] $Cor = "Gray")
    $linha = "{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $Texto
    Write-Host $linha -ForegroundColor $Cor
    try {
        if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" | Out-Null }
        Add-Content -Path (Join-Path "logs" ("apresentacao-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))) -Value "$linha [$NomeFormato]" -Encoding UTF8
    } catch { }
}

# ------------------------------------------------------------------ navegador

$Candidatos = @()
foreach ($par in @(
        @("$env:ProgramFiles", "Google\Chrome\Application\chrome.exe"),
        @("${env:ProgramFiles(x86)}", "Google\Chrome\Application\chrome.exe"),
        @("$env:LOCALAPPDATA", "Google\Chrome\Application\chrome.exe"),
        @("${env:ProgramFiles(x86)}", "Microsoft\Edge\Application\msedge.exe"),
        @("$env:ProgramFiles", "Microsoft\Edge\Application\msedge.exe"))) {
    # pasta vazia (ex.: Windows 32 bits nao tem ProgramFiles(x86)): pula
    if ($par[0]) { $Candidatos += (Join-Path $par[0] $par[1]) }
}
$Navegador = $null
foreach ($c in $Candidatos) { if ($c -and (Test-Path $c)) { $Navegador = $c; break } }
$Pagina = Join-Path $Raiz "web\apresentacao-$NomeFormato.html"
if (-not $Navegador) {
    Escrever-Log "Nao achei o Chrome nem o Edge neste computador." "Red"
    Escrever-Log "Abra no navegador o arquivo abaixo e aperte F11:" "Red"
    Escrever-Log "  $Pagina" "Red"
    Read-Host "Enter para sair"
    exit 1
}
$NomeProcesso = [IO.Path]::GetFileName($Navegador)
# Perfil proprio: e por ele que se acha a janela da apresentacao entre os
# outros Chrome abertos, e abre em tela cheia mesmo com o Chrome ja aberto.
$Perfil = Join-Path $Raiz "navegador-$NomeFormato"
$Argumentos = @(
    "--user-data-dir=`"$Perfil`"",
    "--kiosk", "--edge-kiosk-type=fullscreen",
    "--no-first-run", "--no-default-browser-check",
    "--hide-crash-restore-bubble", "--disable-session-crashed-bubble", "--disable-background-mode",
    "--disable-translate", "--disable-features=Translate",
    "--window-position=$MonitorX,$MonitorY",
    "`"$Pagina`""
) -join " "

function Achar-Apresentacao {
    # O processo principal do navegador com o NOSSO perfil (os filhos tem --type=).
    $perfilMin = $Perfil.ToLower()
    try {
        $lista = @(Get-CimInstance Win32_Process -Filter "Name='$NomeProcesso'" -ErrorAction Stop)
    } catch {
        $lista = @(Get-WmiObject Win32_Process -Filter "Name='$NomeProcesso'")
    }
    foreach ($p in $lista) {
        $cmd = "$($p.CommandLine)".ToLower()
        if ($cmd.Contains($perfilMin) -and -not $cmd.Contains("--type=")) { return [int] $p.ProcessId }
    }
    return $null
}

# -------------------------------------------------------------- coleta (TSE)

$Dados = Join-Path $Raiz "web\dados.js"
$idade = 99999
if (Test-Path $Dados) { $idade = ((Get-Date) - (Get-Item $Dados).LastWriteTime).TotalSeconds }
if ($idade -gt 60) {
    Escrever-Log "a coleta (GRAFICOS.bat) nao esta rodando nesta maquina: abrindo agora." "Yellow"
    Start-Process -FilePath (Join-Path $Raiz "GRAFICOS.bat") -WorkingDirectory $Raiz
    Start-Sleep -Seconds 5
} else {
    Escrever-Log "coleta rodando (dados gravados ha $([int] $idade) s)." "Green"
}

# ------------------------------------------------------------------- vigia

Escrever-Log "gctse APRESENTACAO $($NomeFormato.ToUpper()) - navegador: $NomeProcesso - monitor $MonitorX,$MonitorY" "Green"
Write-Host ""
Write-Host "  Esta janela VIGIA a apresentacao: se ela fechar, reabre sozinha." -ForegroundColor Cyan
Write-Host "  Para encerrar de vez: Alt+F4 na apresentacao e depois S aqui." -ForegroundColor Cyan
Write-Host ""

$rapidas = 0
while ($true) {
    $id = Achar-Apresentacao
    $inicioAberta = Get-Date
    if ($null -ne $id) {
        Escrever-Log "apresentacao ja aberta (processo $id): vigiando."
    } else {
        Escrever-Log "abrindo a apresentacao em tela cheia."
        Start-Process -FilePath $Navegador -ArgumentList $Argumentos | Out-Null
        for ($i = 0; $i -lt 20 -and $null -eq $id; $i++) { Start-Sleep -Milliseconds 500; $id = Achar-Apresentacao }
    }
    if ($null -ne $id) {
        try { Wait-Process -Id $id -ErrorAction Stop } catch { }
    }
    $durou = [int] ((Get-Date) - $inicioAberta).TotalSeconds

    $espera = 10
    if ($durou -lt 20) { $rapidas++ } else { $rapidas = 0 }
    if ($rapidas -ge 3) {
        $espera = 60
        Escrever-Log "o navegador fecha logo que abre ($rapidas vezes seguidas). Tentando de novo a cada 60 s." "Red"
    } else {
        Escrever-Log "a apresentacao FECHOU (ficou aberta $durou s)." "Yellow"
    }
    Write-Host "  Reabrindo em $espera s. Para NAO reabrir (encerrar de vez), aperte S." -ForegroundColor Yellow
    $fim = (Get-Date).AddSeconds($espera)
    $sair = $false
    while ((Get-Date) -lt $fim) {
        try {
            if ([Console]::KeyAvailable) {
                $tecla = [Console]::ReadKey($true)
                if ($tecla.Key -eq [ConsoleKey]::S) { $sair = $true; break }
            }
        } catch { }
        Start-Sleep -Milliseconds 200
    }
    if ($sair) { Escrever-Log "apresentacao encerrada pelo operador."; break }
}
