<#
    gctse GRAFICOS - prepara o Windows de uma maquina que vai ao ar:
      - tela nunca desliga, computador nunca suspende/hiberna (na tomada e na bateria)
      - protecao de tela desligada
      - notificacoes do Windows desligadas (nao aparecem por cima da tela cheia)
    Guarda os valores de ANTES em windows-antes.json; a opcao D volta tudo.
    Chamado pelo PREPARAR-WINDOWS.bat.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$Backup = Join-Path $Raiz "windows-antes.json"

$Energia = @(
    @{ nome = "desligar a tela";  sub = "SUB_VIDEO"; cfg = "VIDEOIDLE";     chave = "monitor-timeout" },
    @{ nome = "suspender";        sub = "SUB_SLEEP"; cfg = "STANDBYIDLE";   chave = "standby-timeout" },
    @{ nome = "hibernar";         sub = "SUB_SLEEP"; cfg = "HIBERNATEIDLE"; chave = "hibernate-timeout" }
)
$RegTela = "HKCU:\Control Panel\Desktop"
$RegNotif = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"

function Ler-Energia {
    # Devolve @(segundos na tomada, segundos na bateria) ou $null.
    # Le os numeros 0x........ da saida (funciona com o Windows em portugues
    # ou ingles): os dois ultimos sao o valor atual na tomada e na bateria.
    param($Item)
    $saida = (& powercfg /q SCHEME_CURRENT $Item.sub $Item.cfg 2>$null) -join "`n"
    $hex = @([regex]::Matches($saida, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return $null }
    return @([Convert]::ToInt64($hex[$hex.Count - 2], 16), [Convert]::ToInt64($hex[$hex.Count - 1], 16))
}

function Mudar-Energia {
    param($Item, [long] $Tomada, [long] $Bateria)
    $ok = $true
    & powercfg /change "$($Item.chave)-ac" ([math]::Ceiling($Tomada / 60)) 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $ok = $false }
    & powercfg /change "$($Item.chave)-dc" ([math]::Ceiling($Bateria / 60)) 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $ok = $false }
    return $ok
}

function Ler-Registro {
    param([string] $Caminho, [string] $Nome)
    try {
        $v = Get-ItemProperty -Path $Caminho -Name $Nome -ErrorAction Stop
        return "$($v.$Nome)"
    } catch { return $null }
}

function Mostrar-Situacao {
    foreach ($item in $Energia) {
        $v = Ler-Energia $item
        $txt = "nao consegui ler"
        if ($null -ne $v) {
            $f = { param($s) if ($s -eq 0) { "NUNCA" } else { "$([math]::Ceiling($s / 60)) min" } }
            $txt = "tomada: $(& $f $v[0])   bateria: $(& $f $v[1])"
        }
        Write-Host ("   {0,-18} {1}" -f $item.nome, $txt)
    }
    $pt = Ler-Registro $RegTela "ScreenSaveActive"
    Write-Host ("   {0,-18} {1}" -f "protecao de tela", $(if ($pt -eq "0") { "DESLIGADA" } else { "ligada (se houver uma escolhida)" }))
    $nt = Ler-Registro $RegNotif "ToastEnabled"
    Write-Host ("   {0,-18} {1}" -f "notificacoes", $(if ($nt -eq "0") { "DESLIGADAS" } else { "ligadas" }))
}

Write-Host ""
Write-Host "  gctse GRAFICOS - preparar o Windows desta maquina para ir ao ar" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Como esta agora:"
Mostrar-Situacao
Write-Host ""
Write-Host "  P = PREPARAR (tela sempre ligada, sem suspender, sem protecao de tela, sem notificacoes)"
Write-Host "  D = DESFAZER (volta ao que estava antes do P)"
Write-Host "  S = sair sem mudar nada"
$op = "$(Read-Host '  Escolha')".Trim().ToUpper()

if ($op -eq "P") {
    if (-not (Test-Path $Backup)) {
        # Guarda o ANTES so na primeira vez: rodar P de novo nao apaga o original.
        $antes = [ordered]@{ gravado_em = (Get-Date).ToString("dd/MM/yyyy HH:mm") }
        foreach ($item in $Energia) {
            $v = Ler-Energia $item
            if ($null -ne $v) { $antes[$item.cfg] = @($v[0], $v[1]) }
        }
        $antes["ScreenSaveActive"] = Ler-Registro $RegTela "ScreenSaveActive"
        $antes["ToastEnabled"] = Ler-Registro $RegNotif "ToastEnabled"
        [IO.File]::WriteAllText($Backup, ($antes | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  valores de antes guardados em windows-antes.json" -ForegroundColor Green
    }
    $falhou = @()
    foreach ($item in $Energia) {
        if ($null -eq (Ler-Energia $item)) { continue }   # ex.: maquina sem hibernacao
        if (-not (Mudar-Energia $item 0 0)) { $falhou += $item.nome }
    }
    try { Set-ItemProperty -Path $RegTela -Name "ScreenSaveActive" -Value "0" } catch { $falhou += "protecao de tela" }
    try {
        if (-not (Test-Path $RegNotif)) { New-Item -Path $RegNotif -Force | Out-Null }
        New-ItemProperty -Path $RegNotif -Name "ToastEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
    } catch { $falhou += "notificacoes" }
    Write-Host ""
    if ($falhou.Count -gt 0) {
        Write-Host "  NAO consegui mudar: $($falhou -join ', ')" -ForegroundColor Red
        Write-Host "  Faca na mao: Configuracoes > Sistema > Energia (tela e suspensao: Nunca)" -ForegroundColor Red
        Write-Host "  e Configuracoes > Sistema > Notificacoes (desligar)." -ForegroundColor Red
    }
    Write-Host "  Como ficou:"
    Mostrar-Situacao
    Write-Host ""
    Write-Host "  FALTA UMA COISA, na mao: pausar o Windows Update (para nao reiniciar" -ForegroundColor Yellow
    Write-Host "  sozinho durante a apuracao). Vou abrir a tela: clique em 'Pausar'." -ForegroundColor Yellow
    try { Start-Process "ms-settings:windowsupdate" } catch { }
}
elseif ($op -eq "D") {
    if (-not (Test-Path $Backup)) {
        Write-Host "  Nao ha windows-antes.json: o P nunca rodou nesta pasta. Nada a desfazer." -ForegroundColor Yellow
    } else {
        $antes = Get-Content $Backup -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($item in $Energia) {
            if ($antes.PSObject.Properties.Name -contains $item.cfg) {
                $v = @($antes.($item.cfg))
                [void] (Mudar-Energia $item ([long] $v[0]) ([long] $v[1]))
            }
        }
        if ($null -ne $antes.ScreenSaveActive) { Set-ItemProperty -Path $RegTela -Name "ScreenSaveActive" -Value "$($antes.ScreenSaveActive)" }
        if ($null -ne $antes.ToastEnabled) {
            New-ItemProperty -Path $RegNotif -Name "ToastEnabled" -Value ([int] $antes.ToastEnabled) -PropertyType DWord -Force | Out-Null
        } else {
            try { Remove-ItemProperty -Path $RegNotif -Name "ToastEnabled" -ErrorAction Stop } catch { }
        }
        Remove-Item $Backup
        Write-Host "  Voltou ao que estava em $($antes.gravado_em). Como ficou:" -ForegroundColor Green
        Mostrar-Situacao
        Write-Host "  Lembre de retomar o Windows Update (Configuracoes > Windows Update)." -ForegroundColor Yellow
    }
}
else {
    Write-Host "  Nada foi mudado."
}
Write-Host ""
Read-Host "  Enter para fechar"
