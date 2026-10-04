<#
    gctse GRAFICOS - GOVERNADOR e SENADOR dos 27 estados (giro final)

    Le do TSE o boletim de Governador e de Senador de cada estado e grava
    web\estados.js, que a tela giro-estados.html le sozinha.

    Separado do graficos.ps1 (Presidente) de proposito: se este parar, os
    graficos de Presidente continuam. So o ambiente OFICIAL.

    Uso:  ESTADOS.bat (ou o GIRO-ESTADOS.bat, que abre este junto)
#>

[CmdletBinding()]
param(
    [switch] $UmaVez
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$Versao = "1.8 - 04/10/2026"

# TLS 1.2: o Windows PowerShell 5.1 ainda oferece TLS 1.0 por padrao.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }
# O .NET Framework abre so 2 conexoes por servidor; resposta nao fechada
# prende uma. Ver Fechar-Resposta.
try { [Net.ServicePointManager]::DefaultConnectionLimit = 64 } catch { }
$ProgressPreference = "SilentlyContinue"

# Um clique na janela preta a poe em modo "Selecionar" e CONGELA o programa
# (visto na maquina do GC em 28/09). Desliga a edicao rapida desta janela.
if ($env:OS -eq "Windows_NT") {
    try {
        Add-Type -Namespace GcTseEstados -Name JanelaConsole -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $entradaConsole = [GcTseEstados.JanelaConsole]::GetStdHandle(-10)
        [uint32] $modoConsole = 0
        if ([GcTseEstados.JanelaConsole]::GetConsoleMode($entradaConsole, [ref] $modoConsole)) {
            if (($modoConsole -band 0x40) -ne 0) { $modoConsole = $modoConsole - 0x40 }
            $modoConsole = $modoConsole -bor 0x80
            [void] [GcTseEstados.JanelaConsole]::SetConsoleMode($entradaConsole, $modoConsole)
        }
    } catch { }
}

$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz

function Escrever-Log {
    param([string] $Texto, [string] $Nivel = "INFO")
    $linha = "{0} {1,-5} {2}" -f (Get-Date -Format "HH:mm:ss"), $Nivel, $Texto
    switch ($Nivel) {
        "ERRO"  { Write-Host $linha -ForegroundColor Red }
        "AVISO" { Write-Host $linha -ForegroundColor Yellow }
        "OK"    { Write-Host $linha -ForegroundColor Green }
        default { Write-Host $linha }
    }
    try {
        if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" | Out-Null }
        Add-Content -Path (Join-Path "logs" ("estados-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))) -Value $linha -Encoding UTF8
    } catch { }
}

# ---------------------------------------------------------------- utilidades
# (copiadas sem alteracao do gctse.ps1, onde foram validadas na maquina do GC)

function Tem-Propriedade {
    # $obj.PSObject.Properties.Name quebra sob StrictMode quando o objeto nao
    # tem propriedade nenhuma (ex.: "cores_partido": {} no config).
    param($Objeto, [string] $Nome)
    if ($null -eq $Objeto) { return $false }
    foreach ($prop in $Objeto.PSObject.Properties) {
        if ($prop.Name -eq $Nome) { return $true }
    }
    return $false
}

function Obter-Campo {
    # O TSE usa chaves abreviadas e ja as renomeou entre pleitos: tenta varias.
    param($Objeto, [string[]] $Chaves, $Padrao = $null)
    if ($null -eq $Objeto) { return $Padrao }
    foreach ($chave in $Chaves) {
        if (Tem-Propriedade $Objeto $chave) {
            $valor = $Objeto.$chave
            if ($null -ne $valor -and "$valor" -ne "") { return $valor }
        }
    }
    return $Padrao
}

function Converter-Inteiro {
    # "12.345.678" -> 12345678 (o TSE manda numero como texto pt-BR)
    param($Valor)
    if ($null -eq $Valor) { return 0 }
    $limpo = ([string] $Valor) -replace '[^\d\-]', ''
    if ($limpo -eq '' -or $limpo -eq '-') { return 0 }
    try { return [int64] $limpo } catch { return 0 }
}

function Converter-Decimal {
    # "49,10" -> 49.10   |   "1.234,56" -> 1234.56
    param($Valor)
    if ($null -eq $Valor) { return 0.0 }
    $texto = ([string] $Valor).Trim().Replace('%', '').Replace(' ', '')
    if ($texto -eq '') { return 0.0 }
    if ($texto.Contains(',')) { $texto = $texto.Replace('.', '').Replace(',', '.') }
    try { return [double]::Parse($texto, [Globalization.CultureInfo]::InvariantCulture) }
    catch { return 0.0 }
}

function Decodificar-Entidades {
    # O proprio TSE manda entidade HTML dentro do JSON ("1&#186; Turno").
    # Sem isto a tarja mostra "1&#186; TURNO" no ar, e a entidade ainda
    # consome 6 dos caracteres do limite de nome.
    param([string] $Texto)
    if (-not $Texto) { return "" }
    $t = $Texto
    if ($t -notmatch '&') { return $t }
    $t = [regex]::Replace($t, '&#(\d{1,6});', {
        param($m)
        try { return [char][int] $m.Groups[1].Value } catch { return $m.Value }
    })
    $t = [regex]::Replace($t, '&#[xX]([0-9a-fA-F]{1,5});', {
        param($m)
        try { return [char][Convert]::ToInt32($m.Groups[1].Value, 16) } catch { return $m.Value }
    })
    $t = $t -replace '&aacute;', [char] 225 -replace '&eacute;', [char] 233
    $t = $t -replace '&iacute;', [char] 237 -replace '&oacute;', [char] 243
    $t = $t -replace '&uacute;', [char] 250 -replace '&ccedil;', [char] 231
    $t = $t -replace '&atilde;', [char] 227 -replace '&otilde;', [char] 245
    $t = $t -replace '&acirc;',  [char] 226 -replace '&ecirc;',  [char] 234
    $t = $t -replace '&ocirc;',  [char] 244 -replace '&ordm;',   [char] 186
    $t = $t -replace '&nbsp;', " " -replace '&quot;', '"'
    $t = $t -replace '&lt;', "<" -replace '&gt;', ">" -replace '&amp;', "&"
    return $t
}

function Ler-Texto-Resposta {
    # O TSE serve JSON em UTF-8 SEM declarar charset no cabecalho. O
    # Invoke-WebRequest do PowerShell 5.1, sem charset, decodifica como
    # ISO-8859-1 - e "SAO PAULO" com til vira "SAƒO PAULO" no ar. Por isso
    # lemos os BYTES e decodificamos como UTF-8 na mao.
    param($Resposta)
    try {
        $fluxo = $Resposta.RawContentStream
        if ($fluxo) {
            $bytes = $fluxo.ToArray()
            if ($bytes.Length -gt 0) {
                $texto = [Text.Encoding]::UTF8.GetString($bytes)
                if ($texto.Length -gt 0 -and [int] $texto[0] -eq 65279) {
                    $texto = $texto.Substring(1)   # descarta BOM
                }
                return $texto
            }
        }
    } catch { }
    return "$($Resposta.Content)"
}

function Fechar-Resposta {
    # Toda resposta de ERRO do Invoke-WebRequest (304, 404, 500) vem dentro
    # da excecao, com a conexao ainda presa a ela. No Windows PowerShell 5.1,
    # se ninguem fecha, a conexao so volta quando o coletor de lixo passar -
    # e com o limite de duas por servidor, duas respostas esquecidas bastam
    # para travar TODA a coleta. Com ETag, o TSE responde 304 para cada
    # arquivo que nao mudou: do segundo ciclo em diante, quase toda resposta
    # e 304. Esta funcao e a diferenca entre funcionar e travar.
    param($Erro)
    try {
        if ($null -ne $Erro -and $null -ne $Erro.Exception) {
            $resp = $null
            if (Tem-Propriedade $Erro.Exception "Response") { $resp = $Erro.Exception.Response }
            if ($null -ne $resp) {
                if ($resp -is [Net.WebResponse]) { $resp.Close() }
                elseif ($resp -is [IDisposable]) { $resp.Dispose() }
            }
        }
    } catch { }
}

function Promover-Temporario {
    # Poe o .tmp no lugar do arquivo que o GC le.
    #
    # Em 29/09 a tarja do presidente ficou SEM GRAVAR das 16:00 as 16:03 e
    # das 16:28 as 16:34 ("Nao e possivel criar um arquivo ja existente"),
    # com o LiveBoard mostrando o numero velho. Causa: o Move-Item -Force
    # APAGA o destino antes de mover; com o LiveBoard (Java) segurando o
    # arquivo aberto, o Windows deixa o apagado "pendente" e o nome fica
    # ocupado ate o leitor soltar - minutos.
    #
    # Agora: 1) File.Replace, que troca o arquivo RENOMEANDO o antigo (e o
    # jeito do Windows de substituir arquivo em uso); 2) se o destino nao
    # existe, File.Move; 3) repete algumas vezes; 4) se ainda nao der,
    # escreve POR CIMA do arquivo aberto (o leitor Java compartilha
    # escrita). Nunca apaga o destino.
    param([string] $Temporario, [string] $Caminho)
    $tentativas = 0
    while ($true) {
        $tentativas++
        try {
            if (Test-Path -LiteralPath $Caminho) {
                [IO.File]::Replace($Temporario, $Caminho, [NullString]::Value, $true)
            } else {
                [IO.File]::Move($Temporario, $Caminho)
            }
            return $true
        } catch {
            $erroTroca = $_.Exception.Message
            if ($tentativas -lt 6) { Start-Sleep -Milliseconds (80 * $tentativas); continue }
        }
        # Plano B: escrever no proprio arquivo aberto, sem apagar nada.
        try {
            $bytes = [IO.File]::ReadAllBytes($Temporario)
            $fluxo = New-Object IO.FileStream($Caminho, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write,
                                              ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            try {
                $fluxo.Write($bytes, 0, $bytes.Length)
                $fluxo.SetLength($bytes.Length)
                $fluxo.Flush()
            } finally { $fluxo.Dispose() }
            try { Remove-Item -LiteralPath $Temporario -Force -ErrorAction SilentlyContinue } catch { }
            Escrever-Log "$(Split-Path -Leaf $Caminho): arquivo preso pelo leitor ($erroTroca) - gravado por cima" "AVISO"
            return $true
        } catch {
            Escrever-Log "nao consegui gravar $Caminho : $erroTroca / $($_.Exception.Message)" "AVISO"
            try { Remove-Item -LiteralPath $Temporario -Force -ErrorAction SilentlyContinue } catch { }
            # Falso, e nao excecao: perder ESTA gravacao nao pode levar junto
            # o resto do ciclo. Quem chama nao guarda a impressao, entao o
            # proximo ciclo tenta de novo sozinho.
            return $false
        }
    }
}



# -------------------------------------------------------------------- config

if (-not (Test-Path "config-graficos.json")) {
    Write-Host "config-graficos.json nao encontrado nesta pasta." -ForegroundColor Red
    exit 1
}
$cfg = Get-Content "config-graficos.json" -Raw -Encoding UTF8 | ConvertFrom-Json

$Base    = "$($cfg.tse.base_url)".TrimEnd('/')
$Ciclo   = "$($cfg.tse.ciclo)"
# 6259 = Eleicoes Gerais Estaduais (Governador e Senador), pagina oficial do TSE
$Eleicao = "6259"
if ((Tem-Propriedade $cfg.tse "eleicao_estaduais") -and $cfg.tse.eleicao_estaduais) { $Eleicao = "$($cfg.tse.eleicao_estaduais)" }
$Modo    = "OFICIAL"
$Intervalo = 30
if (Tem-Propriedade $cfg "intervalo_estados_segundos") { $Intervalo = [math]::Max(15, [int] $cfg.intervalo_estados_segundos) }
$PastaWeb = Join-Path $Raiz "web"

$UFs = @("ac","al","ap","am","ba","ce","df","es","go","ma","mt","ms","mg","pa",
         "pb","pr","pe","pi","rj","rn","rs","ro","rr","sc","sp","se","to")
$Cargos = @(3, 5)   # 3 = Governador, 5 = Senador

function Montar-Url {
    param([string] $Abr, [int] $Cargo)
    $ele6 = "{0:000000}" -f ([int] $Eleicao)
    $c4 = "{0:0000}" -f $Cargo
    return "$Base/$Ciclo/$Eleicao/dados/$Abr/$Abr-c$c4-e$ele6-u.json"
}

# ------------------------------------------------ recebendo do TSE? (alarme)

$script:AbertoEm = Get-Date   # (nao confundir com $inicio do ciclo: PowerShell ignora maiusculas)
$script:UltimaResposta = $null
$script:UltimoErro = ""
$script:ErroFoi404 = $false
$script:Alarme = $false
$script:UltimoQuadro = [datetime]::MinValue

function Registrar-Resposta {
    $script:UltimaResposta = Get-Date
    if ($script:Alarme) { $script:Alarme = $false; Escrever-Log "VOLTAMOS A RECEBER DADOS DO TSE" "OK" }
}

function Segundos-Sem-Tse {
    $desde = $script:AbertoEm
    if ($null -ne $script:UltimaResposta) { $desde = $script:UltimaResposta }
    return [int] ((Get-Date) - $desde).TotalSeconds
}

function Conferir-Recebimento {
    if ((Segundos-Sem-Tse) -lt [math]::Max(90, 3 * $Intervalo)) { return }
    $script:Alarme = $true
    if (((Get-Date) - $script:UltimoQuadro).TotalSeconds -lt 30) { return }
    $script:UltimoQuadro = Get-Date
    $ultimo = "NENHUM desde que abriu"
    if ($null -ne $script:UltimaResposta) { $ultimo = $script:UltimaResposta.ToString("HH:mm:ss") }
    $cor = @{ ForegroundColor = "White"; BackgroundColor = "DarkRed" }
    Write-Host ""
    Write-Host ("  {0,-70}" -f "ATENCAO: NAO ESTAMOS RECEBENDO DADOS DO TSE (estados)") @cor
    Write-Host ("  {0,-70}" -f "ultimo dado recebido: $ultimo") @cor
    Write-Host ("  {0,-70}" -f "A tela fica no ultimo dado REAL recebido (ou vazia).") @cor
    if ($script:ErroFoi404) {
        Write-Host "  O TSE RESPONDEU, mas o boletim ainda nao foi publicado (404)." -ForegroundColor Yellow
    } elseif ($script:UltimoErro) { Write-Host "  ultimo erro: $($script:UltimoErro)" -ForegroundColor Yellow }
    Write-Host ""
    Escrever-Log "NAO ESTAMOS RECEBENDO DADOS DO TSE - ultimo: $ultimo" "ERRO"
}

# ------------------------------------------------------------ leitura do TSE

$script:ETags = @{}
$script:Ausentes = @{}
$script:NumCiclo = 0
$script:UltimoPedido = [datetime]::MinValue

function Obter-Boletim {
    # Devolve o objeto do boletim, "SEM-MUDANCA" (304) ou $null.
    param([string] $Url)
    if ($script:Ausentes.ContainsKey($Url) -and $script:NumCiclo -lt $script:Ausentes[$Url].pularAte) { return $null }
    $passou = ((Get-Date) - $script:UltimoPedido).TotalMilliseconds
    if ($passou -lt 150) { Start-Sleep -Milliseconds ([int] (150 - $passou)) }
    $script:UltimoPedido = Get-Date
    $cab = @{ "User-Agent" = "gctse-graficos/1.0"; "Accept" = "application/json,*/*" }
    if ($script:ETags.ContainsKey($Url) -and "$($script:ETags[$Url])") { $cab["If-None-Match"] = "$($script:ETags[$Url])" }
    try {
        $resp = Invoke-WebRequest -Uri $Url -Headers $cab -TimeoutSec 15 -UseBasicParsing
    } catch {
        $codigo = 0
        try { $codigo = [int] $_.Exception.Response.StatusCode } catch { }
        Fechar-Resposta $_
        if ($codigo -eq 304) {
            if ($script:Ausentes.ContainsKey($Url)) { $script:Ausentes.Remove($Url) }
            Registrar-Resposta
            return "SEM-MUDANCA"
        }
        if ($codigo -eq 404) {
            $vezes = 1
            if ($script:Ausentes.ContainsKey($Url)) { $vezes = $script:Ausentes[$Url].vezes + 1 }
            $espera = [math]::Min($vezes, 3)
            $script:Ausentes[$Url] = @{ vezes = $vezes; pularAte = $script:NumCiclo + [int] $espera }
            $script:UltimoErro = "HTTP 404 (ainda nao publicado) em $Url"
            $script:ErroFoi404 = $true
            return $null
        }
        $script:ErroFoi404 = $false
        if ($codigo -gt 0) { $script:UltimoErro = "HTTP $codigo em $Url" } else { $script:UltimoErro = "$($_.Exception.Message)" }
        return $null
    }
    if ($script:Ausentes.ContainsKey($Url)) { $script:Ausentes.Remove($Url) }
    try {
        $etag = $resp.Headers["ETag"]
        if ($etag -is [array]) { $etag = $etag | Select-Object -First 1 }
        if ($etag) { $script:ETags[$Url] = "$etag" } elseif ($script:ETags.ContainsKey($Url)) { $script:ETags.Remove($Url) }
    } catch { }
    $texto = Ler-Texto-Resposta $resp
    try { $obj = $texto | ConvertFrom-Json } catch {
        if ($script:ETags.ContainsKey($Url)) { $script:ETags.Remove($Url) }
        $script:UltimoErro = "resposta nao e JSON em $Url"
        return $null
    }
    Registrar-Resposta
    return $obj
}

# ----------------------------------------------------------- leitura do boletim

function Resumir-Boletim {
    param($Bruto, [int] $Cargo)
    $fase = "$(Obter-Campo $Bruto @('f') '')".ToUpper()
    $vagas = 1
    $cands = @()
    if (Tem-Propriedade $Bruto "carg") {
        foreach ($cg in $Bruto.carg) {
            if ("$(Obter-Campo $cg @('cd') '')" -ne "$Cargo") { continue }
            $nv = Converter-Inteiro (Obter-Campo $cg @('nv') 1)
            if ($nv -ge 1) { $vagas = $nv }
            if (-not (Tem-Propriedade $cg "agr")) { continue }
            foreach ($agr in $cg.agr) {
                if (-not (Tem-Propriedade $agr "par")) { continue }
                foreach ($pa in $agr.par) {
                    $sigla = Decodificar-Entidades "$(Obter-Campo $pa @('sg','nm') '')"
                    if (-not (Tem-Propriedade $pa "cand")) { continue }
                    foreach ($c in $pa.cand) {
                        $st = Decodificar-Entidades "$(Obter-Campo $c @('st') '')"
                        $marcaE = "$(Obter-Campo $c @('e') '')".ToLower()
                        # ELEITO so com a palavra do TSE (mesma regra do gctse 6.x).
                        $eleito = $false
                        if ($st) { $eleito = ($st -match '^Eleito') } elseif ($marcaE -eq "s") { $eleito = $true }
                        $cands += [pscustomobject]@{
                            numero  = "$(Obter-Campo $c @('n') '')"
                            sqcand  = "$(Obter-Campo $c @('sqcand') '')"
                            nome    = Decodificar-Entidades "$(Obter-Campo $c @('nmu','nm') '')"
                            partido = $sigla
                            votos   = Converter-Inteiro (Obter-Campo $c @('vap') 0)
                            pct     = Converter-Decimal (Obter-Campo $c @('pvap') 0)
                            eleito  = $eleito
                            segundo_turno = ($st -match 'turno')
                            situacao = $st
                        }
                    }
                }
            }
        }
    }
    $cands = @($cands | Sort-Object -Property @{Expression = "votos"; Descending = $true}, numero)
    $s = $null
    if (Tem-Propriedade $Bruto "s") { $s = $Bruto.s }
    $pctUrnas = $null
    if ($null -ne $s -and (Tem-Propriedade $s "pst")) { $pctUrnas = Converter-Decimal $s.pst }
    return [pscustomobject]@{
        tem        = $true
        fase       = $fase
        andamento  = "$(Obter-Campo $Bruto @('and') '')".ToLower()
        geracao    = "$(Obter-Campo $Bruto @('dg') '') $(Obter-Campo $Bruto @('hg') '')"
        hora       = "$(Obter-Campo $Bruto @('hg') '')"
        urnas_pct  = $pctUrnas
        vagas      = $vagas
        candidatos = $cands
    }
}

function Converter-Geracao {
    param([string] $Texto)
    $data = [datetime]::MinValue
    $formatos = [string[]] @("dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm")
    if ([datetime]::TryParseExact("$Texto".Trim(), $formatos, [Globalization.CultureInfo]::InvariantCulture,
                                  [Globalization.DateTimeStyles]::None, [ref] $data)) { return $data }
    return $null
}

$script:Cache = @{}
$script:Regressao = @{}
$script:FaseAvisada = @{}

function Ler-Abrangencia {
    param([string] $Abr, [int] $Cargo)
    $url = Montar-Url $Abr $Cargo
    $chave = "$Abr-$Cargo"
    $bruto = Obter-Boletim $url
    if ($null -eq $bruto -or "$bruto" -eq "SEM-MUDANCA") { return }
    $r = Resumir-Boletim $bruto $Cargo
    # No ar, so dado oficial: nada de simulado (S) nem teste (T).
    if ($r.fase -eq "S" -or $r.fase -eq "T") {
        if (-not $script:FaseAvisada.ContainsKey($r.fase)) {
            $script:FaseAvisada[$r.fase] = $true
            Escrever-Log "boletim de fase '$($r.fase)' no ambiente oficial - NAO vai para a tela" "ERRO"
        }
        return
    }
    # Anti-regressao: numero menor com geracao mais ANTIGA e copia velha de CDN.
    if ($script:Cache.ContainsKey($chave)) {
        $velho = $script:Cache[$chave]
        $pNovo = $r.urnas_pct; $pVelho = $velho.urnas_pct
        if ($null -ne $pNovo -and $null -ne $pVelho -and $pNovo -lt $pVelho - 0.001) {
            $gN = Converter-Geracao $r.geracao; $gV = Converter-Geracao $velho.geracao
            if (-not ($null -ne $gN -and $null -ne $gV -and $gN -gt $gV)) {
                $n = 1
                if ($script:Regressao.ContainsKey($chave)) { $n = $script:Regressao[$chave] + 1 }
                $script:Regressao[$chave] = $n
                if ($n -lt 3) {
                    if ($script:ETags.ContainsKey($url)) { $script:ETags.Remove($url) }
                    Escrever-Log ("{0}: urnas voltaram de {1}% para {2}% - mantendo o ultimo bom ({3}a vez)" -f $chave, $pVelho, $pNovo, $n) "AVISO"
                    return
                }
            }
        }
    }
    if ($script:Regressao.ContainsKey($chave)) { $script:Regressao.Remove($chave) }
    $script:Cache[$chave] = $r
}

# ------------------------------------------------------------- gravar dados

function Gravar-Dados {
    $porEstado = [ordered]@{}
    foreach ($u in $UFs) {
        $g = [pscustomobject]@{ tem = $false }; $s = [pscustomobject]@{ tem = $false }
        if ($script:Cache.ContainsKey("$u-3")) { $g = $script:Cache["$u-3"] }
        if ($script:Cache.ContainsKey("$u-5")) { $s = $script:Cache["$u-5"] }
        $porEstado["$u"] = [pscustomobject]@{ gov = $g; sen = $s }
    }
    $ult = ""
    if ($null -ne $script:UltimaResposta) { $ult = $script:UltimaResposta.ToString("HH:mm:ss") }
    $dados = [ordered]@{
        versao        = $Versao
        modo          = $Modo
        pid           = $PID
        gravado_em    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        recebendo_tse = (-not $script:Alarme)
        tse_nao_publicou = ($script:Alarme -and $script:ErroFoi404)
        ultimo_tse    = $ult
        # Para a tela montar o endereco da foto oficial do TSE:
        # {base}/{ciclo}/{eleicao}/fotos/{uf}/{sqcand}.jpeg
        tse           = [pscustomobject]@{ base = $Base; ciclo = $Ciclo; eleicao = $Eleicao }
        ufs           = $porEstado
    }
    $json = $dados | ConvertTo-Json -Depth 8 -Compress
    $conteudo = "window.GCTSE_ESTADOS = $json;"
    $destino = Join-Path $PastaWeb "estados.js"
    $tmp = "$destino.tmp"
    [IO.File]::WriteAllText($tmp, $conteudo, (New-Object System.Text.UTF8Encoding($false)))
    [void] (Promover-Temporario $tmp $destino)
}

# ---------------------------------------------------------------- execucao

Escrever-Log "gctse ESTADOS (Governador e Senador) versao $Versao" "OK"
Escrever-Log "modo $Modo | intervalo ${Intervalo}s | 27 estados x 2 cargos"
Escrever-Log "caminho: $(Montar-Url 'pr' 3)"
Gravar-Dados

do {
    $inicio = Get-Date
    $script:NumCiclo++
    try {
        foreach ($u in $UFs) { foreach ($cg in $Cargos) { Ler-Abrangencia $u $cg } }
        Conferir-Recebimento
        Gravar-Dados
        $nG = @($UFs | Where-Object { $script:Cache.ContainsKey("$_-3") }).Count
        $nS = @($UFs | Where-Object { $script:Cache.ContainsKey("$_-5") }).Count
        $eleG = 0; $segG = 0; $eleS = 0
        foreach ($u in $UFs) {
            if ($script:Cache.ContainsKey("$u-3")) {
                $cs = @($script:Cache["$u-3"].candidatos)
                if (@($cs | Where-Object { $_.eleito }).Count -gt 0) { $eleG++ }
                elseif (@($cs | Where-Object { $_.segundo_turno }).Count -gt 0) { $segG++ }
            }
            if ($script:Cache.ContainsKey("$u-5")) {
                $eleS += @(@($script:Cache["$u-5"].candidatos) | Where-Object { $_.eleito }).Count
            }
        }
        $situ = "TSE: recebendo"
        if ($script:Alarme) {
            $situ = "TSE: SEM RESPOSTA ha $(Segundos-Sem-Tse) s"
            if ($script:ErroFoi404) { $situ = "TSE: responde, mas sem boletim ha $(Segundos-Sem-Tse) s" }
        }
        $pr = ""
        if ($script:Cache.ContainsKey("pr-3")) { $pr = " | PR gov: urnas $($script:Cache['pr-3'].urnas_pct)%" }
        Escrever-Log ("governador: {0}/27 estados ({1} eleitos, {2} no 2o turno) | senador: {3}/27 ({4} eleitos){5} | {6}" -f $nG, $eleG, $segG, $nS, $eleS, $pr, $situ) $(if ($script:Alarme) { "ERRO" } else { "INFO" })
    } catch {
        Escrever-Log "erro no ciclo: $($_.Exception.Message)" "ERRO"
    }
    if ($UmaVez) { break }
    $gasto = ((Get-Date) - $inicio).TotalSeconds
    $espera = [math]::Max(1, $Intervalo - $gasto)
    Start-Sleep -Seconds ([int] $espera)
} while ($true)
