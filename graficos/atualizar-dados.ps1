<#
    gctse GRAFICOS - ATUALIZAR DADOS DO TSE (ATUALIZAR-DADOS.bat ou botao
    "dados do TSE" no gerenciador)

    Roda, um depois do outro, os programas que buscam no TSE os dados que
    nao vem do boletim ao vivo:
      tse ......... GUARDAR-DADOS-TSE (copia local do 1o turno, 2022, fotos)
      candidatos .. IMPORTAR-CANDIDATOS (genero: deputadas, senadoras, perfil
                    da Camara)
      perfil ...... IMPORTAR-PERFIL-ELEITOR (perfil do eleitorado e, depois da
                    eleicao, quem foi as urnas)
    Grava o andamento em atualizar-dados.json (o gerenciador mostra).
    Os coletores ao vivo (GRAFICOS.bat e ESTADOS.bat) NAO sao mexidos.

    Uso: ATUALIZAR-DADOS.bat              (todos)
         ATUALIZAR-DADOS.bat perfil       (so um; ou "tse candidatos")
#>
[CmdletBinding(PositionalBinding = $false)]
param([switch] $SemPausa, [Parameter(ValueFromRemainingArguments = $true)] [string[]] $Etapas = @())
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
$Status = Join-Path $Raiz "atualizar-dados.json"

$TODAS = @(
    [ordered]@{ id = "tse"; nome = "Guardar dados do TSE"; ps1 = "guardar-tse.ps1"; args = @("-SemPausa"); log = "GUARDAR-DADOS-TSE.txt" },
    [ordered]@{ id = "candidatos"; nome = "Importar candidatos (genero)"; ps1 = "importar-candidatos.ps1"; args = @(); log = "IMPORTAR-CANDIDATOS.txt" },
    [ordered]@{ id = "perfil"; nome = "Importar perfil do eleitor"; ps1 = "importar-perfil-eleitor.ps1"; args = @(); log = "IMPORTAR-PERFIL-ELEITOR.txt" }
)
$pedidas = @($Etapas | ForEach-Object { "$_".Split(",") } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
if ($pedidas.Count -eq 0 -or $pedidas -contains "tudo") { $pedidas = @($TODAS | ForEach-Object { $_.id }) }
$fila = @($TODAS | Where-Object { $pedidas -contains $_.id })
if ($fila.Count -eq 0) { Write-Host "etapa desconhecida: $($Etapas -join ', ') (use tse, candidatos, perfil ou tudo)" -ForegroundColor Red; exit 1 }

$psExe = "powershell"
if ($env:WINDIR -and (Test-Path (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"))) { $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe" }
elseif (-not (Get-Command $psExe -ErrorAction SilentlyContinue)) { $psExe = "pwsh" }

$st = [ordered]@{ rodando = $true; pid = $PID; inicio = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); fim = $null; etapa = ""; etapas = @() }
foreach ($e in $fila) { $st.etapas += [ordered]@{ id = $e.id; nome = $e.nome; situacao = "na fila"; ok = $null; inicio = $null; fim = $null; resumo = "" } }
function Gravar() { try { [IO.File]::WriteAllText($Status, ($st | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false))) } catch { } }
# ultima linha util do log de cada programa (o que ele achou / por que parou)
function Resumo([string] $Log) {
    $arq = Join-Path $Raiz $Log
    if (-not (Test-Path $arq)) { return "" }
    $ls = @(Get-Content -LiteralPath $arq -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    if (-not $ls.Count) { return "" }
    $ls = @($ls | ForEach-Object { ($_ -replace '^\W*\d\d:\d\d:\d\d\s+', '').Trim() })
    # GUARDAR-DADOS-TSE: as linhas de resultado (quantos boletins, fotos, 2022)
    $res = @($ls | Where-Object { $_ -cmatch '^(GUARDADO:|FOTOS:|NAO VIERAM \d+ arquivos|2022 (Presidente|Governador))' } | ForEach-Object { $_.TrimEnd(':') })
    if ($res.Count) { return ($res -join " | ") }
    return $ls[-1]
}
Gravar

Write-Host ""
Write-Host "  ATUALIZAR DADOS DO TSE - $($fila.Count) etapa(s): $(($fila | ForEach-Object { $_.nome }) -join ' > ')" -ForegroundColor Yellow
Write-Host "  (os coletores ao vivo continuam rodando normalmente)" -ForegroundColor Gray
for ($i = 0; $i -lt $fila.Count; $i++) {
    $e = $fila[$i]; $et = $st.etapas[$i]
    $st.etapa = $e.nome; $et.situacao = "rodando"; $et.inicio = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); Gravar
    Write-Host ""; Write-Host ("=== {0}/{1}: {2} ===" -f ($i + 1), $fila.Count, $e.nome) -ForegroundColor Cyan
    $codigo = 1
    try {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Raiz $e.ps1) @($e.args)
        $codigo = $LASTEXITCODE; if ($null -eq $codigo) { $codigo = 0 }
    } catch { Write-Host "falhou: $($_.Exception.Message)" -ForegroundColor Red }
    $et.ok = ($codigo -eq 0); $et.fim = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $et.situacao = $(if ($et.ok) { "concluido" } else { "com problema" })
    $et.resumo = Resumo $e.log
    if ($e.id -eq "tse" -and $et.resumo -match 'GUARDADO: 0 ') { $et.ok = $false; $et.situacao = "nada veio do TSE" }
    Gravar
}
$st.rodando = $false; $st.etapa = ""; $st.fim = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); Gravar
$nOk = @($st.etapas | Where-Object { $_.ok }).Count
Write-Host ""
Write-Host ("PRONTO: {0} de {1} etapa(s) sem problema. No gerenciador, clique de novo nas telas para carregar." -f $nOk, $fila.Count) -ForegroundColor $(if ($nOk -eq $fila.Count) { "Green" } else { "Yellow" })
if (-not $SemPausa) { Read-Host "ENTER para fechar" | Out-Null }
