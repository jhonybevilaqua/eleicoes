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

if ($Porta -le 0) {
    $Porta = 8098
    try {
        $cfg = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $cfg.PSObject.Properties) { if ($p.Name -eq "porta_gerenciador" -and [int] $p.Value -gt 0) { $Porta = [int] $p.Value } }
    } catch { }
}

# ------------------------------------------------------- o que esta no ar
# h = saida horizontal, v = saida vertical. tela = o que mostrar; seq muda a
# cada troca; acao/aseq = comando para o giro e o resumo (proximo, uf:pr...).
# Fica gravado em gerenciador-estado.json: se o servidor reiniciar, as
# saidas voltam no que estava no ar.

$ArqEstado = Join-Path $Raiz "gerenciador-estado.json"
function Estado-Padrao {
    return [ordered]@{
        h = [ordered]@{ tela = "apresentacao"; seq = 1; acao = ""; aseq = 0; quando = "" }
        v = [ordered]@{ tela = "apresentacao"; seq = 1; acao = ""; aseq = 0; quando = "" }
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
                if ("$($x.acao)" -match '^[a-z0-9:-]{1,30}$') { $script:Estado[$s].acao = "$($x.acao)" }
            }
        }
    } catch { $script:Estado = Estado-Padrao }
}
function Salvar-Estado {
    try {
        [IO.File]::WriteAllText($ArqEstado, ($script:Estado | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
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
Escrever-Log "OBS da saida VERTICAL:   http://localhost:$Porta/saida.html?saida=v  (fonte Navegador 1080x1920)" "Cyan"
Escrever-Log ("no ar agora: horizontal = {0} | vertical = {1}" -f $script:Estado.h.tela, $script:Estado.v.tela)
Write-Host ""
Write-Host "  Deixe esta janela ABERTA: sem ela as saidas param de trocar." -ForegroundColor Yellow
Write-Host ""
if ($AbrirPagina) { try { Start-Process "http://localhost:$Porta/gerenciador.html" } catch { } }

while ($ouvinte.IsListening) {
    $ctx = $null
    try {
        $ctx = $ouvinte.GetContext()
        $req = $ctx.Request
        $caminho = $req.Url.AbsolutePath

        if ($caminho -eq "/estado") {
            Responder-Json $ctx $script:Estado
        }
        elseif ($caminho -eq "/definir") {
            # Troca o que vai ao ar numa saida.
            $s = "$($req.QueryString['saida'])"; $tela = "$($req.QueryString['tela'])"; $acao = "$($req.QueryString['acao'])"
            if (($s -eq "h" -or $s -eq "v") -and $tela -match '^[a-z0-9-]{1,40}$' -and ($acao -eq "" -or $acao -match '^[a-z0-9:-]{1,30}$')) {
                $script:Estado[$s].tela = $tela
                $script:Estado[$s].seq = [int] $script:Estado[$s].seq + 1
                $script:Estado[$s].acao = $acao
                $script:Estado[$s].quando = (Get-Date -Format "HH:mm:ss")
                Salvar-Estado
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
            if (($s -eq "h" -or $s -eq "v") -and $acao -match '^[a-z0-9:-]{1,30}$') {
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
