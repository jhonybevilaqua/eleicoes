<#
    gctse GRAFICOS - COPIA DE SEGURANCA (COPIA-DE-SEGURANCA.bat ou botao no
    gerenciador)

    Guarda a pasta inteira num .zip com data e hora no nome, dentro de
    "copias-de-seguranca": programas, configuracoes, dados do TSE ja lidos
    (web\dados.js, web\estados.js), a evolucao minuto a minuto
    (evolucao-*.json), as cores atribuidas, o estado do gerenciador e os logs.
    Pode rodar com tudo aberto: arquivo em uso e lido assim mesmo.
    Fica fora: a pasta do ensaio e as copias anteriores.
#>
param([switch] $SemPausa)
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$Pasta = Join-Path $Raiz "copias-de-seguranca"
$Status = Join-Path $Raiz "copia-seguranca.json"
if (-not (Test-Path $Pasta)) { New-Item -ItemType Directory -Path $Pasta | Out-Null }
$nome = "GCTSE-COPIA-{0}.zip" -f (Get-Date -Format "yyyy-MM-dd_HH'h'mm'm'ss")
$zip = Join-Path $Pasta $nome
$fora = @("ensaio", "copias-de-seguranca", "arquivo-historico")

function Gravar-Status($ok, $msg) {
    $o = [ordered]@{ ok = $ok; quando = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); arquivo = $nome; pasta = $Pasta; mensagem = $msg }
    try { [IO.File]::WriteAllText($Status, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) } catch { }
}

Write-Host "Copia de seguranca: $zip" -ForegroundColor Cyan
Gravar-Status $null "copiando..."
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $n = 0; $pulados = @()
    $fs = [IO.File]::Open($zip, [IO.FileMode]::CreateNew)
    $arquivo = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($item in Get-ChildItem -LiteralPath $Raiz -Recurse -Force -File) {
            $rel = $item.FullName.Substring($Raiz.Length).TrimStart('\', '/')
            if ($fora -contains (($rel -split '[\\/]')[0])) { continue }
            if ($item.Name -eq "copia-seguranca.json") { continue }
            try {
                # FileShare.ReadWrite: le mesmo o arquivo que o coletor esta gravando
                $orig = New-Object IO.FileStream($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                try {
                    $ent = $arquivo.CreateEntry(($rel -replace '\\', '/'), [IO.Compression.CompressionLevel]::Optimal)
                    $ent.LastWriteTime = $item.LastWriteTime
                    $dst = $ent.Open(); try { $orig.CopyTo($dst) } finally { $dst.Dispose() }
                } finally { $orig.Dispose() }
                $n++
            } catch { $pulados += $rel }
        }
    } finally { $arquivo.Dispose(); $fs.Dispose() }
    $mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    $msg = "$n arquivos, $mb MB" + $(if ($pulados.Count) { " (sem: " + ($pulados -join ", ") + ")" } else { "" })
    Gravar-Status $true $msg
    Write-Host "PRONTO: $nome  ($msg)" -ForegroundColor Green
    Write-Host "Pasta: $Pasta" -ForegroundColor Green
    Write-Host "Dica: copie tambem para um pendrive ou outra maquina." -ForegroundColor Gray
} catch {
    Gravar-Status $false $_.Exception.Message
    Write-Host "FALHOU: $($_.Exception.Message)" -ForegroundColor Red
}
if (-not $SemPausa) { Read-Host "ENTER para fechar" | Out-Null }
