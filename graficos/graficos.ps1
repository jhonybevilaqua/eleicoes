<#
    gctse GRAFICOS - apuracao de PRESIDENTE para graficos (mapa, barras, rosca)

    Le do TSE o boletim de Presidente do Brasil e dos 27 estados e grava
    web\dados.js. As paginas de web\ (abertas no Chrome, ou como fonte de
    navegador no switcher) leem esse arquivo sozinhas a cada 3 segundos.

    Separado de proposito do gctse das tarjas: outro computador, outra
    pasta, nenhum arquivo em comum. Um nao derruba o outro.

    Uso:
        GRAFICOS.bat          ambiente OFICIAL (dia 04/10)
        TESTE-GRAFICOS.bat    ambiente de SIMULADO do TSE (so para conferir)
#>

[CmdletBinding()]
param(
    [switch] $Teste,
    [switch] $UmaVez
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$Versao = "3.13 - 08/10/2026"

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
        Add-Type -Namespace GcTseGraficos -Name JanelaConsole -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $entradaConsole = [GcTseGraficos.JanelaConsole]::GetStdHandle(-10)
        [uint32] $modoConsole = 0
        if ([GcTseGraficos.JanelaConsole]::GetConsoleMode($entradaConsole, [ref] $modoConsole)) {
            if (($modoConsole -band 0x40) -ne 0) { $modoConsole = $modoConsole - 0x40 }
            $modoConsole = $modoConsole -bor 0x80
            [void] [GcTseGraficos.JanelaConsole]::SetConsoleMode($entradaConsole, $modoConsole)
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
        Add-Content -Path (Join-Path "logs" ("graficos-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))) -Value $linha -Encoding UTF8
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
$Eleicao = "$($cfg.tse.eleicao_presidente)"
$Modo    = "OFICIAL"
# ENSAIO (ENSAIO.bat): copia separada da pasta, TSE simulado local. Todas as
# telas saem marcadas "ENSAIO - NAO VAI AO AR".
$Ensaio = ((Tem-Propriedade $cfg "ensaio") -and $cfg.ensaio -eq $true)
if ($Ensaio) { $Modo = "SIMULADO" }
if ($Teste) {
    if (-not ((Tem-Propriedade $cfg.tse "base_url_simulado") -and $cfg.tse.base_url_simulado)) {
        Write-Host "Modo TESTE sem 'base_url_simulado' no config-graficos.json." -ForegroundColor Red
        exit 1
    }
    $Base    = "$($cfg.tse.base_url_simulado)".TrimEnd('/')
    $Eleicao = "$($cfg.tse.eleicao_presidente_simulado)"
    $Modo    = "SIMULADO"
}
# 2o TURNO: com "eleicao_presidente_1turno" diferente de "eleicao_presidente",
# o resultado FINAL do 1o turno (Brasil e 27 estados) continua sendo lido
# (a cada 3 ciclos) para o mapa do 1o turno e as comparacoes.
$Eleicao1T = ""
if ((Tem-Propriedade $cfg.tse "eleicao_presidente_1turno") -and $cfg.tse.eleicao_presidente_1turno -and
    "$($cfg.tse.eleicao_presidente_1turno)" -ne $Eleicao -and ($Modo -eq "OFICIAL" -or $Ensaio)) { $Eleicao1T = "$($cfg.tse.eleicao_presidente_1turno)" }
$Intervalo = 20
if (Tem-Propriedade $cfg "intervalo_segundos") { $Intervalo = [math]::Max(10, [int] $cfg.intervalo_segundos) }
$PastaWeb = Join-Path $Raiz "web"

$UFs = @("ac","al","ap","am","ba","ce","df","es","go","ma","mt","ms","mg","pa",
         "pb","pr","pe","pi","rj","rn","rs","ro","rr","sc","sp","se","to")

function Montar-Url {
    param([string] $Abr, [string] $Pleito = "")
    if (-not $Pleito) { $Pleito = $Eleicao }
    $ele6 = "{0:000000}" -f ([int] $Pleito)
    return "$Base/$Ciclo/$Pleito/dados/$Abr/$Abr-c0001-e$ele6-u.json"
}

# ------------------------------------------------ recebendo do TSE? (alarme)

$script:AbertoEm = Get-Date   # (nao confundir com $inicio do ciclo: PowerShell ignora maiusculas)
$script:UltimaResposta = $null
$script:UltimoErro = ""
$script:ErroFoi404 = $false   # o ultimo erro foi "ainda nao publicado"?
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
    if ((Segundos-Sem-Tse) -lt [math]::Max(60, 3 * $Intervalo)) { return }
    $script:Alarme = $true
    if (((Get-Date) - $script:UltimoQuadro).TotalSeconds -lt 30) { return }
    $script:UltimoQuadro = Get-Date
    $ultimo = "NENHUM desde que abriu"
    if ($null -ne $script:UltimaResposta) { $ultimo = $script:UltimaResposta.ToString("HH:mm:ss") }
    $cor = @{ ForegroundColor = "White"; BackgroundColor = "DarkRed" }
    Write-Host ""
    Write-Host ("  {0,-70}" -f "ATENCAO: NAO ESTAMOS RECEBENDO DADOS DO TSE") @cor
    Write-Host ("  {0,-70}" -f "ultimo dado recebido: $ultimo") @cor
    Write-Host ("  {0,-70}" -f "Os graficos ficam no ultimo dado REAL recebido (ou vazios).") @cor
    if ($script:ErroFoi404) {
        Write-Host "  O TSE RESPONDEU, mas o boletim ainda nao foi publicado (404)." -ForegroundColor Yellow
        Write-Host "  Normal antes da 1a divulgacao (17h). Depois das 17h10, avise." -ForegroundColor Yellow
    } elseif ($script:UltimoErro) { Write-Host "  ultimo erro: $($script:UltimoErro)" -ForegroundColor Yellow }
    Write-Host ""
    Escrever-Log "NAO ESTAMOS RECEBENDO DADOS DO TSE - ultimo: $ultimo" "ERRO"
}

# ------------------------------------------------------------ leitura do TSE

$script:ETags = @{}        # url -> ETag (texto)
$script:Ausentes = @{}     # url -> @{ vezes; pularAte } : recuo depois de 404
$script:NumCiclo = 0
$script:UltimoPedido = [datetime]::MinValue

# COPIA LOCAL (GUARDAR-DADOS-TSE.bat): boletim que o TSE nao entregar (fora
# do ar, 404, erro) e que estiver guardado em tse-local sai da copia - o
# arquivo e o proprio do TSE. Volta ao TSE sozinho quando ele responder.
$script:CopiaLocal = @{}      # url -> objeto lido do disco (le uma vez)
$script:UsandoLocal = @{}     # url -> desde quando
function Copia-Local([string] $Url) {
    if (-not $Url.StartsWith($Base)) { return $null }
    if ($Eleicao1T -and $Url.Contains("/$Eleicao/dados/")) { return $null }   # 2o turno: sempre ao vivo
    if ($script:CopiaLocal.ContainsKey($Url)) { return $script:CopiaLocal[$Url] }
    $arq = Join-Path (Join-Path $Raiz "tse-local") (($Url.Substring($Base.Length).TrimStart('/')) -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $arq)) { return $null }
    try { $obj = [IO.File]::ReadAllText($arq, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return $null }
    $script:CopiaLocal[$Url] = $obj
    return $obj
}
function Obter-Boletim {
    param([string] $Url)
    $r = Obter-Boletim-Tse $Url
    if ($null -ne $r) {
        if ($script:UsandoLocal.ContainsKey($Url)) { $script:UsandoLocal.Remove($Url); Escrever-Log "TSE voltou a entregar: $Url" "OK" }
        return $r
    }
    $loc = Copia-Local $Url
    if ($null -ne $loc) {
        if (-not $script:UsandoLocal.ContainsKey($Url)) { $script:UsandoLocal[$Url] = (Get-Date).ToString("HH:mm:ss"); Escrever-Log "TSE nao entregou - usando a COPIA LOCAL (GUARDAR-DADOS-TSE): $Url" "AVISO" }
        return $loc
    }
    return $null
}
function Obter-Boletim-Tse {
    # Devolve o objeto do boletim, "SEM-MUDANCA" (304) ou $null.
    param([string] $Url)
    if ($script:Ausentes.ContainsKey($Url) -and $script:NumCiclo -lt $script:Ausentes[$Url].pularAte) { return $null }
    # respiro entre pedidos: bem abaixo das 100 req/s do TSE
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
            # O TSE avisa que muitos 404 podem bloquear o IP: espaca (1, 2,
            # 3 ciclos). Teto de 3 ciclos = no maximo ~1 min de atraso
            # quando o boletim aparece.
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

$script:CamposVistos = @{}

function Numero-De {
    param($Bloco, [string[]] $Chaves)
    if ($null -eq $Bloco) { return $null }
    foreach ($k in $Chaves) {
        if (Tem-Propriedade $Bloco $k) {
            $v = $Bloco.$k
            if ($null -ne $v -and "$v" -ne "") { return $v }
        }
    }
    return $null
}

function Inteiro-Ou-Nulo { param($V) if ($null -eq $V) { return $null } return (Converter-Inteiro $V) }
function Decimal-Ou-Nulo { param($V) if ($null -eq $V) { return $null } return (Converter-Decimal $V) }

function Resumir-Boletim {
    param($Bruto, [string] $Abr)
    $fase = "$(Obter-Campo $Bruto @('f') '')".ToUpper()
    $s = $null; $e = $null; $v = $null
    if (Tem-Propriedade $Bruto "s") { $s = $Bruto.s }
    if (Tem-Propriedade $Bruto "e") { $e = $Bruto.e }
    if (Tem-Propriedade $Bruto "v") { $v = $Bruto.v }
    # Os nomes dos campos de totais nao estao todos confirmados no arquivo
    # de 2026: registra uma vez o que veio, para conferencia.
    foreach ($par in @(@("s", $s), @("e", $e), @("v", $v))) {
        $chaveV = "$Abr-$($par[0])"
        if ($null -ne $par[1] -and -not $script:CamposVistos.ContainsKey($chaveV) -and $Abr -eq "br") {
            $script:CamposVistos[$chaveV] = $true
            Escrever-Log ("campos do bloco '{0}' no boletim do TSE: {1}" -f $par[0], (($par[1].PSObject.Properties | ForEach-Object { $_.Name }) -join ", "))
        }
    }

    $cands = @()
    if (Tem-Propriedade $Bruto "carg") {
        foreach ($cargo in $Bruto.carg) {
            if ("$(Obter-Campo $cargo @('cd') '1')" -ne "1") { continue }
            if (-not (Tem-Propriedade $cargo "agr")) { continue }
            foreach ($agr in $cargo.agr) {
                if (-not (Tem-Propriedade $agr "par")) { continue }
                foreach ($par in $agr.par) {
                    $sigla = Decodificar-Entidades "$(Obter-Campo $par @('sg','nm') '')"
                    if (-not (Tem-Propriedade $par "cand")) { continue }
                    foreach ($c in $par.cand) {
                        $st = Decodificar-Entidades "$(Obter-Campo $c @('st') '')"
                        $marcaE = "$(Obter-Campo $c @('e') '')".ToLower()
                        # ELEITO so com a palavra do TSE (mesma regra do gctse 6.x):
                        # no simulado, e=s veio tambem para quem ia ao 2o turno.
                        # Com o texto "st", so ele decide: "Eleito", "Eleita",
                        # "Matematicamente eleito", "Eleito por QP" (nunca "Nao eleito"
                        # nem 2o turno). A marca e=s so vale sem "st" - no simulado
                        # veio e=s para os DOIS primeiros de cargo de uma vaga.
                        $naoEleito = ($st -match 'n\S{1,2}o\s+eleit')
                        $vaiTurno = ($st -match 'turno')
                        if ($st) { $eleito = (-not $naoEleito) -and (-not $vaiTurno) -and ($st -match 'eleit') }
                        else { $eleito = ($marcaE -eq "s") }
                        $cands += [pscustomobject]@{
                            numero  = "$(Obter-Campo $c @('n') '')"
                            sqcand  = "$(Obter-Campo $c @('sqcand') '')"
                            nome    = Decodificar-Entidades "$(Obter-Campo $c @('nmu','nm') '')"
                            partido = $sigla
                            votos   = Converter-Inteiro (Obter-Campo $c @('vap') 0)
                            pct     = Converter-Decimal (Obter-Campo $c @('pvap') 0)
                            eleito  = $eleito
                            segundo_turno = $vaiTurno
                            destinacao = Decodificar-Entidades "$(Obter-Campo $c @('dvt') '')"
                        }
                    }
                }
            }
        }
    }
    $cands = @($cands | Sort-Object -Property @{Expression = "votos"; Descending = $true}, numero)

    $validos = Inteiro-Ou-Nulo (Numero-De $v @('vv'))
    $brancos = Inteiro-Ou-Nulo (Numero-De $v @('vb'))
    $nulos   = Inteiro-Ou-Nulo (Numero-De $v @('tvn','vn'))
    $pValidos = Decimal-Ou-Nulo (Numero-De $v @('pvv'))
    $pBrancos = Decimal-Ou-Nulo (Numero-De $v @('pvb'))
    $pNulos   = Decimal-Ou-Nulo (Numero-De $v @('ptvn','pvn'))
    if ($null -eq $validos -and $cands.Count -gt 0) { $validos = [int64] (($cands | Measure-Object -Property votos -Sum).Sum) }
    # Percentuais sobre os votos apurados (validos + brancos + nulos), quando
    # o TSE nao manda pronto.
    if ($null -ne $validos -and $null -ne $brancos -and $null -ne $nulos) {
        $tot = [double] ($validos + $brancos + $nulos)
        if ($tot -gt 0) {
            if ($null -eq $pValidos) { $pValidos = [math]::Round(100.0 * $validos / $tot, 2) }
            if ($null -eq $pBrancos) { $pBrancos = [math]::Round(100.0 * $brancos / $tot, 2) }
            if ($null -eq $pNulos)   { $pNulos   = [math]::Round(100.0 * $nulos / $tot, 2) }
        }
    }

    return [pscustomobject]@{
        tem        = $true
        fase       = $fase
        andamento  = "$(Obter-Campo $Bruto @('and') '')".ToLower()
        geracao    = "$(Obter-Campo $Bruto @('dg') '') $(Obter-Campo $Bruto @('hg') '')"
        hora       = "$(Obter-Campo $Bruto @('hg') '')"
        secoes     = [pscustomobject]@{
            total       = Inteiro-Ou-Nulo (Numero-De $s @('ts'))
            totalizadas = Inteiro-Ou-Nulo (Numero-De $s @('st'))
            pct         = Decimal-Ou-Nulo (Numero-De $s @('pst'))
        }
        eleitorado = [pscustomobject]@{
            aptos          = Inteiro-Ou-Nulo (Numero-De $e @('te'))
            comparecimento = Inteiro-Ou-Nulo (Numero-De $e @('c'))
            pct_comparec   = Decimal-Ou-Nulo (Numero-De $e @('pc'))
            abstencao      = Inteiro-Ou-Nulo (Numero-De $e @('a'))
            pct_abstencao  = Decimal-Ou-Nulo (Numero-De $e @('pa'))
            # eleitores em secoes ja totalizadas / ainda NAO totalizadas
            # (TSE: est / esnt) - base do "Ainda da para virar?"
            em_totalizadas = Inteiro-Ou-Nulo (Numero-De $e @('est'))
            faltam         = Inteiro-Ou-Nulo (Numero-De $e @('esnt'))
        }
        votos      = [pscustomobject]@{
            validos = $validos; pct_validos = $pValidos
            brancos = $brancos; pct_brancos = $pBrancos
            nulos   = $nulos;   pct_nulos   = $pNulos
        }
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

$script:Cache = @{}           # abr -> ultimo resumo aceito
$script:Regressao = @{}       # abr -> vezes que o numero menor foi visto
$script:FaseAvisada = @{}

function Ler-Abrangencia {
    param([string] $Abr)
    $url = Montar-Url $Abr
    $bruto = Obter-Boletim $url
    if ($null -eq $bruto -or "$bruto" -eq "SEM-MUDANCA") { return }
    $r = Resumir-Boletim $bruto $Abr
    # No ar, so dado oficial: o ambiente OFICIAL nao pode passar simulado
    # (S) nem teste (T).
    if ($Modo -eq "OFICIAL" -and ($r.fase -eq "S" -or $r.fase -eq "T")) {
        if (-not $script:FaseAvisada.ContainsKey($r.fase)) {
            $script:FaseAvisada[$r.fase] = $true
            Escrever-Log "boletim de fase '$($r.fase)' no ambiente oficial - NAO vai para os graficos" "ERRO"
        }
        return
    }
    # Anti-regressao: numero menor com geracao mais ANTIGA e copia velha de
    # CDN - segura. Com geracao mais nova e o TSE corrigindo/reiniciando.
    if ($script:Cache.ContainsKey($Abr)) {
        $velho = $script:Cache[$Abr]
        $pNovo = $r.secoes.pct; $pVelho = $velho.secoes.pct
        if ($null -ne $pNovo -and $null -ne $pVelho -and $pNovo -lt $pVelho - 0.001) {
            $gN = Converter-Geracao $r.geracao; $gV = Converter-Geracao $velho.geracao
            if (-not ($null -ne $gN -and $null -ne $gV -and $gN -gt $gV)) {
                $n = 1
                if ($script:Regressao.ContainsKey($Abr)) { $n = $script:Regressao[$Abr] + 1 }
                $script:Regressao[$Abr] = $n
                if ($n -lt 3) {
                    if ($script:ETags.ContainsKey($url)) { $script:ETags.Remove($url) }
                    Escrever-Log ("{0}: urnas voltaram de {1}% para {2}% - mantendo o ultimo bom ({3}a vez)" -f $Abr, $pVelho, $pNovo, $n) "AVISO"
                    return
                }
            }
        }
    }
    if ($script:Regressao.ContainsKey($Abr)) { $script:Regressao.Remove($Abr) }
    $script:Cache[$Abr] = $r
}

# 1o turno guardado (so no 2o turno): resumo enxuto de Brasil e estados.
$script:Turno1 = [ordered]@{}
function Ler-Turno1 {
    foreach ($abr in @("br") + $UFs + @("zz")) {
        $bruto = Obter-Boletim (Montar-Url $abr $Eleicao1T)
        if ($null -eq $bruto -or "$bruto" -eq "SEM-MUDANCA") { continue }
        $r = Resumir-Boletim $bruto "t1-$abr"
        if ($r.fase -eq "S" -or $r.fase -eq "T") { continue }
        $script:Turno1[$abr] = [pscustomobject]@{
            tem = $true; andamento = $r.andamento; geracao = $r.geracao; secoes = $r.secoes; votos = $r.votos
            eleitorado = $r.eleitorado
            candidatos = @($r.candidatos | Select-Object -First 8)
        }
    }
}

# ------------------------------------- CAPITAIS e EXTERIOR (Presidente)
# Lista de municipios do TSE: {ciclo}/{eleicao}/config/mun-e{eleicao}-cm.json
# (especificacao do TSE 2026). Boletim do municipio:
# dados/{uf}/{uf}{codigo TSE}-c0001-e{eleicao}-u.json. Exterior = "uf" zz;
# cada cidade no exterior e um "municipio" dela. Capital: marca do TSE no
# arquivo (c = S) ou, sem ela, o nome da capital de cada estado.
$NomesCapitais = @{ ac = "RIO BRANCO"; al = "MACEIO"; ap = "MACAPA"; am = "MANAUS"; ba = "SALVADOR"; ce = "FORTALEZA"; df = "BRASILIA"
    es = "VITORIA"; go = "GOIANIA"; ma = "SAO LUIS"; mt = "CUIABA"; ms = "CAMPO GRANDE"; mg = "BELO HORIZONTE"; pa = "BELEM"
    pb = "JOAO PESSOA"; pr = "CURITIBA"; pe = "RECIFE"; pi = "TERESINA"; rj = "RIO DE JANEIRO"; rn = "NATAL"; rs = "PORTO ALEGRE"
    ro = "PORTO VELHO"; rr = "BOA VISTA"; sc = "FLORIANOPOLIS"; sp = "SAO PAULO"; se = "ARACAJU"; to = "PALMAS" }
function Sem-Acento([string] $T) {
    $n = $T.Normalize([Text.NormalizationForm]::FormD); $sb = New-Object Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void] $sb.Append($ch) } }
    return $sb.ToString().ToUpper().Trim()
}
$script:Mun = $null                 # @{ capitais = @{uf=@{cd;nome}}; exterior = @(@{cd;nome;pais}) }
$script:ProxMun = [datetime]::MinValue
$script:Capitais = [ordered]@{}     # uf -> resumo do boletim da capital
$script:Capitais1T = [ordered]@{}   # uf -> lider do 1o turno na capital (2o turno)
$script:Exterior = [ordered]@{}     # cd -> resumo da cidade
$script:ExteriorVez = 0
function Visitar-Mun($o, [string] $uf, $saida) {
    if ($null -eq $o) { return }
    if ($o -is [array]) { foreach ($x in $o) { Visitar-Mun $x $uf $saida }; return }
    if ($o -isnot [System.Management.Automation.PSCustomObject]) { return }
    $nomes = @($o.PSObject.Properties | ForEach-Object { $_.Name })
    if ($nomes -contains "cd" -and $nomes -contains "mu") { Visitar-Mun $o.mu ("$($o.cd)".ToLower()) $saida; return }
    if ($uf -and $nomes -contains "cd" -and $nomes -contains "nm") {
        $pais = ""
        foreach ($p in $o.PSObject.Properties) { if ($p.Name -match '^(pa[ií]s|nmpais|nmp|ps)$' -and "$($p.Value)") { $pais = Decodificar-Entidades "$($p.Value)" } }
        [void] $saida.Add([pscustomobject]@{ uf = $uf; cd = "$($o.cd)"; nome = Decodificar-Entidades "$($o.nm)"; capital = ("$(Obter-Campo $o @('c') '')".ToUpper() -eq "S"); pais = $pais })
        return
    }
    foreach ($p in $o.PSObject.Properties) { if ($p.Value -is [array] -or $p.Value -is [pscustomobject]) { Visitar-Mun $p.Value $uf $saida } }
}
function Ler-Municipios {
    if ($null -ne $script:Mun -or (Get-Date) -lt $script:ProxMun) { return }
    $script:ProxMun = (Get-Date).AddMinutes(10)
    foreach ($ele in @($Eleicao, $Eleicao1T) | Where-Object { $_ } | Select-Object -Unique) {
        $e6 = "{0:000000}" -f ([int] $ele)
        $bruto = Obter-Boletim "$Base/$Ciclo/$ele/config/mun-e$e6-cm.json"
        if ($null -eq $bruto -or "$bruto" -eq "SEM-MUDANCA") { continue }
        $lista = New-Object System.Collections.ArrayList
        Visitar-Mun $bruto "" $lista
        if ($lista.Count -lt 27) { continue }
        $caps = @{}
        foreach ($u in $UFs) {
            $c = @($lista | Where-Object { $_.uf -eq $u -and $_.capital }) | Select-Object -First 1
            if ($null -eq $c) { $c = @($lista | Where-Object { $_.uf -eq $u -and (Sem-Acento $_.nome) -eq $NomesCapitais[$u] }) | Select-Object -First 1 }
            if ($c) { $caps[$u] = $c }
        }
        $ext = @($lista | Where-Object { $_.uf -eq "zz" })
        $script:Mun = @{ capitais = $caps; exterior = $ext }
        Escrever-Log ("municipios do TSE (eleicao {0}): {1} lidos | capitais achadas: {2}/27 | cidades no exterior: {3}" -f $ele, $lista.Count, $caps.Count, $ext.Count) $(if ($caps.Count -lt 27) { "AVISO" } else { "OK" })
        return
    }
    Escrever-Log "lista de municipios do TSE (mun-e...-cm.json) nao encontrada - capitais e exterior por cidade ficam de fora; tento de novo em 10 min" "AVISO"
}
function Url-Mun([string] $Uf, [string] $Cd, [string] $Ele) {
    $e6 = "{0:000000}" -f ([int] $Ele)
    return "$Base/$Ciclo/$Ele/dados/$Uf/$Uf$Cd-c0001-e$e6-u.json"
}
function Resumo-Mun($bruto, [string] $chave, $m) {
    $r = Resumir-Boletim $bruto $chave
    if ($r.fase -eq "S" -or $r.fase -eq "T") { if ($Modo -eq "OFICIAL") { return $null } }
    return [pscustomobject]@{ tem = $true; cd = $m.cd; nome = $m.nome; pais = $m.pais; andamento = $r.andamento; secoes = $r.secoes
        eleitorado = $r.eleitorado; votos = $r.votos; candidatos = @($r.candidatos | Select-Object -First 12) }
}
function Ler-Capitais {
    if ($null -eq $script:Mun) { return }
    foreach ($u in $script:Mun.capitais.Keys) {
        $m = $script:Mun.capitais[$u]
        $bruto = Obter-Boletim (Url-Mun $u $m.cd $Eleicao)
        if ($null -ne $bruto -and "$bruto" -ne "SEM-MUDANCA") { $x = Resumo-Mun $bruto "cap-$u" $m; if ($x) { $script:Capitais[$u] = $x } }
        if ($Eleicao1T -and -not $script:Capitais1T.Contains($u)) {
            $b1 = Obter-Boletim (Url-Mun $u $m.cd $Eleicao1T)
            if ($null -ne $b1 -and "$b1" -ne "SEM-MUDANCA") { $x1 = Resumo-Mun $b1 "cap1-$u" $m; if ($x1 -and $x1.andamento -eq "f") { $script:Capitais1T[$u] = $x1 } }
        }
    }
}
function Ler-Exterior {
    if ($null -eq $script:Mun -or -not $script:Mun.exterior.Count) { return }
    $ext = $script:Mun.exterior; $n = $ext.Count
    for ($i = 0; $i -lt [math]::Min(30, $n); $i++) {            # 30 cidades por ciclo, em rodizio
        $m = $ext[($script:ExteriorVez + $i) % $n]
        $bruto = Obter-Boletim (Url-Mun "zz" $m.cd $Eleicao)
        if ($null -ne $bruto -and "$bruto" -ne "SEM-MUDANCA") { $x = Resumo-Mun $bruto "zz-$($m.cd)" $m; if ($x) { $script:Exterior[$m.cd] = $x } }
    }
    $script:ExteriorVez = ($script:ExteriorVez + 30) % [math]::Max(1, $n)
}

# ------------------------------------------------------ cor de cada candidato
# A cor segue o CANDIDATO, nunca a posicao: se fosse pela colocacao, o mapa
# repintaria os estados quando o 2o passasse o 1o. As 3 primeiras cores da
# paleta sao as unicas que continuam distinguiveis entre si num mapa
# (validado, inclusive para daltonismo) - entao vao para os primeiros que
# aparecem na frente, e a atribuicao fica CONGELADA em cores-atribuidas.json
# (sobrevive a reiniciar o programa). Quem aparece depois pega a proxima.

$ArquivoCores = Join-Path $Raiz "cores-atribuidas-$($Modo.ToLower()).json"
$script:Slots = @{}
if (Test-Path $ArquivoCores) {
    try {
        $lido = Get-Content $ArquivoCores -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $lido.PSObject.Properties) { $script:Slots[$p.Name] = [int] $p.Value }
    } catch { }
}

function Atribuir-Cores {
    if (-not $script:Cache.ContainsKey("br")) { return }
    $mudou = $false
    foreach ($c in $script:Cache["br"].candidatos) {
        if ($c.votos -le 0 -or -not $c.numero) { continue }
        if ($script:Slots.ContainsKey($c.numero)) { continue }
        $script:Slots["$($c.numero)"] = $script:Slots.Count
        $mudou = $true
    }
    if ($mudou) {
        try {
            $obj = [ordered]@{}
            foreach ($k in ($script:Slots.Keys | Sort-Object { $script:Slots[$_] })) { $obj["$k"] = $script:Slots[$k] }
            [IO.File]::WriteAllText($ArquivoCores, ($obj | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        } catch { }
    }
}

# ------------------------------------------- evolucao minuto a minuto (Brasil)
# Cada boletim NOVO do Brasil (hora de geracao do TSE diferente) vira um ponto:
# hora do TSE, % de urnas e % dos validos de cada candidato. So o que o TSE
# publicou - nada interpolado. Fica guardado em evolucao-<ciclo>-<eleicao>-<modo>.json
# (sobrevive a fechar o programa; o 2o turno, outra eleicao, comeca um
# arquivo novo) e vai para a tela dentro do dados.js.

$ArquivoEvolucao = Join-Path $Raiz ("evolucao-{0}-{1}-{2}.json" -f $Ciclo, $Eleicao, $Modo.ToLower())
$script:Evolucao = New-Object System.Collections.ArrayList
$script:EvolucaoNomes = [ordered]@{}
$script:EvolucaoOrigem = ""
$script:EvolucaoNovoEm = $null
$script:EvolucaoLidaEm = [datetime]::MinValue
# Le (ou rele) o arquivo. O IMPORTAR-EVOLUCAO.bat pode gravar nele com este
# programa aberto: quando a data do arquivo muda, a lista e recarregada.
function Carregar-Evolucao {
    if (-not (Test-Path $ArquivoEvolucao)) { return }
    try {
        $quandoArq = (Get-Item $ArquivoEvolucao).LastWriteTimeUtc
        if ($quandoArq -eq $script:EvolucaoLidaEm) { return }
        $lidoEv = Get-Content $ArquivoEvolucao -Raw -Encoding UTF8 | ConvertFrom-Json
        $novaLista = New-Object System.Collections.ArrayList
        foreach ($pt in @($lidoEv.pontos)) {
            if ($null -eq $pt) { continue }
            # PowerShell 7 transforma "2026-10-04T18:00:00" em data: volta a texto.
            if ($pt.t -is [datetime]) { $pt.t = $pt.t.ToString("yyyy-MM-ddTHH:mm:ss") }
            [void] $novaLista.Add($pt)
        }
        $script:Evolucao = $novaLista
        if (Tem-Propriedade $lidoEv "nomes") { foreach ($pn in $lidoEv.nomes.PSObject.Properties) { $script:EvolucaoNomes[$pn.Name] = $pn.Value } }
        if (Tem-Propriedade $lidoEv "origem") { $script:EvolucaoOrigem = "$($lidoEv.origem)" }
        $script:EvolucaoLidaEm = $quandoArq
        if ($script:Evolucao.Count -gt 0) { Escrever-Log ("evolucao: {0} pontos no historico ({1})" -f $script:Evolucao.Count, (Split-Path -Leaf $ArquivoEvolucao)) }
    } catch { Escrever-Log "evolucao: nao li $ArquivoEvolucao ($($_.Exception.Message))" "AVISO" }
}
Carregar-Evolucao

function Registrar-Evolucao {
    Carregar-Evolucao
    if (-not $script:Cache.ContainsKey("br")) { return }
    $b = $script:Cache["br"]
    if ($null -eq $b.secoes.pct -or $b.secoes.pct -le 0) { return }
    $quando = Converter-Geracao $b.geracao
    $marca = $(if ($null -ne $quando) { $quando.ToString("yyyy-MM-ddTHH:mm:ss") } else { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") })
    $porCand = [ordered]@{}
    foreach ($c in $b.candidatos) {
        if (-not $c.numero -or $c.votos -le 0) { continue }
        $porCand["$($c.numero)"] = $c.pct
        $script:EvolucaoNomes["$($c.numero)"] = [pscustomobject]@{ nome = $c.nome; partido = $c.partido }
    }
    if ($porCand.Count -eq 0) { return }
    if ($script:Evolucao.Count -gt 0) {
        $ultimoPt = $script:Evolucao[$script:Evolucao.Count - 1]
        if ("$($ultimoPt.t)" -ge $marca) { return }           # mesmo boletim (ou copia mais velha)
        if ([double] $ultimoPt.u -eq [double] $b.secoes.pct -and
            (($ultimoPt.c | ConvertTo-Json -Compress) -eq ([pscustomobject] $porCand | ConvertTo-Json -Compress))) { return }
    }
    [void] $script:Evolucao.Add([pscustomobject]@{ t = $marca; u = $b.secoes.pct; c = [pscustomobject] $porCand })
    $script:EvolucaoNovoEm = Get-Date
    while ($script:Evolucao.Count -gt 3000) { $script:Evolucao.RemoveAt(0) }
    try {
        $objEv = [ordered]@{ ciclo = $Ciclo; eleicao = $Eleicao; modo = $Modo; origem = $script:EvolucaoOrigem; nomes = [pscustomobject] $script:EvolucaoNomes; pontos = @($script:Evolucao) }
        $tmpEv = "$ArquivoEvolucao.tmp"
        [IO.File]::WriteAllText($tmpEv, ($objEv | ConvertTo-Json -Depth 6 -Compress), (New-Object System.Text.UTF8Encoding($false)))
        [void] (Promover-Temporario $tmpEv $ArquivoEvolucao)
        $script:EvolucaoLidaEm = (Get-Item $ArquivoEvolucao).LastWriteTimeUtc
    } catch { Escrever-Log "evolucao: nao gravei o historico ($($_.Exception.Message))" "AVISO" }
}

# ------------------------------------------------------------- gravar dados

function Gravar-Dados {
    Atribuir-Cores
    $porEstado = [ordered]@{}
    foreach ($u in $UFs) {
        if ($script:Cache.ContainsKey($u)) { $porEstado["$u"] = $script:Cache[$u] }
        else { $porEstado["$u"] = [pscustomobject]@{ tem = $false } }
    }
    $br = [pscustomobject]@{ tem = $false }
    if ($script:Cache.ContainsKey("br")) { $br = $script:Cache["br"] }
    $ult = ""
    if ($null -ne $script:UltimaResposta) { $ult = $script:UltimaResposta.ToString("HH:mm:ss") }
    $dados = [ordered]@{
        versao        = $Versao
        modo          = $Modo
        ensaio        = $Ensaio
        pid           = $PID
        gravado_em    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        copia_local   = $script:UsandoLocal.Count
        evolucao_novo_em = $(if ($script:EvolucaoNovoEm) { $script:EvolucaoNovoEm.ToString("yyyy-MM-ddTHH:mm:ss") } else { "" })
        recebendo_tse = (-not $script:Alarme)
        tse_nao_publicou = ($script:Alarme -and $script:ErroFoi404)
        ultimo_tse    = $ult
        cores         = $(if (Tem-Propriedade $cfg "cores") { $cfg.cores } else { [pscustomobject]@{} })
        cor_slot      = [pscustomobject] $script:Slots
        # Foto oficial: {base}/{ciclo}/{eleicao}/fotos/br/{sqcand}.jpeg
        tse           = [pscustomobject]@{ base = $Base; ciclo = $Ciclo; eleicao = $Eleicao }
        br            = $br
        ufs           = $porEstado
        exterior_total = $(if ($script:Cache.ContainsKey("zz")) { $script:Cache["zz"] } else { [pscustomobject]@{ tem = $false } })
        capitais      = [pscustomobject] $script:Capitais
        capitais_1t   = [pscustomobject] $script:Capitais1T
        exterior      = @($script:Exterior.Values)
        exterior_cidades = $(if ($script:Mun) { $script:Mun.exterior.Count } else { 0 })
        turno1        = $(if ($Eleicao1T) { [pscustomobject]@{ eleicao = $Eleicao1T; br = $(if ($script:Turno1.Contains("br")) { $script:Turno1["br"] } else { [pscustomobject]@{ tem = $false } }); ufs = [pscustomobject] $script:Turno1 } } else { $null })
        evolucao      = [pscustomobject]@{ origem = $script:EvolucaoOrigem; nomes = [pscustomobject] $script:EvolucaoNomes; pontos = @($script:Evolucao) }
    }
    $json = $dados | ConvertTo-Json -Depth 8 -Compress
    $conteudo = "window.GCTSE_DADOS = $json;"
    $destino = Join-Path $PastaWeb "dados.js"
    $tmp = "$destino.tmp"
    [IO.File]::WriteAllText($tmp, $conteudo, (New-Object System.Text.UTF8Encoding($false)))
    [void] (Promover-Temporario $tmp $destino)
}

# ------------------------------------------------- um coletor por pasta
# OFICIAL e TESTE gravam o mesmo web\dados.js. Se os dois estiverem abertos,
# a tela fica trocando entre oficial e simulado (visto em 02/10: monitores
# parados com "SIMULADO" porque o TESTE ficou aberto). Regra: o OFICIAL
# sempre ganha - o TESTE ve que o oficial esta gravando e se encerra.

function Outro-Coletor-Oficial {
    $arq = Join-Path $PastaWeb "dados.js"
    if (-not (Test-Path $arq)) { return $false }
    try {
        if (((Get-Date) - (Get-Item $arq).LastWriteTime).TotalSeconds -gt 60) { return $false }
        $txt = [IO.File]::ReadAllText($arq)
        $m = [regex]::Match($txt, '"modo":"(\w+)".*?"pid":(\d+)')
        if (-not $m.Success) { return $false }
        return ($m.Groups[1].Value -eq "OFICIAL" -and [int] $m.Groups[2].Value -ne $PID)
    } catch { return $false }
}

# ---------------------------------------------------------------- execucao

Escrever-Log "gctse GRAFICOS versao $Versao" "OK"
Escrever-Log "modo $Modo | intervalo ${Intervalo}s | Presidente: Brasil + 27 estados"
Escrever-Log "caminho: $(Montar-Url 'br')"
if ($Modo -eq "SIMULADO") { Escrever-Log "SIMULADO do TSE: os graficos saem com 'SIMULADO - NAO OFICIAL'. Nao use no ar." "AVISO" }
Escrever-Log "Abra no Chrome: $(Join-Path $PastaWeb 'index.html')"
if ($Modo -eq "SIMULADO" -and (Outro-Coletor-Oficial)) {
    Escrever-Log "a coleta OFICIAL (GRAFICOS.bat) ja esta rodando nesta pasta - o TESTE nao abre para nao misturar." "ERRO"
    exit 2
}
Gravar-Dados

do {
    $inicio = Get-Date
    $script:NumCiclo++
    if ($Modo -eq "SIMULADO" -and (Outro-Coletor-Oficial)) {
        Escrever-Log "a coleta OFICIAL (GRAFICOS.bat) abriu nesta pasta - o TESTE se encerra aqui." "AVISO"
        break
    }
    try {
        Ler-Abrangencia "br"
        if ($Eleicao1T -and (($script:NumCiclo % 3) -eq 1)) {
            try { Ler-Turno1; Escrever-Log ("1o turno guardado: {0} de 29 boletins (eleicao {1})" -f $script:Turno1.Count, $Eleicao1T) } catch { Escrever-Log "1o turno: $($_.Exception.Message)" "AVISO" }
        }
        Registrar-Evolucao
        Gravar-Dados                       # o Brasil vai para a tela antes dos estados
        # Estados so depois que o Brasil saiu: antes das 17h seriam 27
        # pedidos com 404 por ciclo (o TSE avisa que 404 em excesso bloqueia
        # o IP). Antes, so o Brasil e consultado.
        if ($script:Cache.ContainsKey("br")) {
            foreach ($u in $UFs) { Ler-Abrangencia $u }
            # exterior (total), capitais (a cada 2 ciclos) e cidades do exterior (30 por ciclo)
            try {
                Ler-Abrangencia "zz"
                Ler-Municipios
                if (($script:NumCiclo % 2) -eq 0) { Ler-Capitais }
                Ler-Exterior
            } catch { Escrever-Log "capitais/exterior: $($_.Exception.Message)" "AVISO" }
        }
        Conferir-Recebimento
        Gravar-Dados
        $comDado = @($UFs | Where-Object { $script:Cache.ContainsKey($_) }).Count
        $txt = "Brasil: sem boletim"
        if ($script:ErroFoi404) { $txt = "Brasil: TSE ainda nao publicou (normal antes das 17h)" }
        if ($script:Cache.ContainsKey("br")) {
            $b = $script:Cache["br"]
            $l = ""
            if ($b.candidatos.Count -gt 0) { $l = " | 1o $($b.candidatos[0].nome) $($b.candidatos[0].pct)%" }
            $txt = "Brasil: urnas $($b.secoes.pct)%$l"
        }
        $situ = "TSE: recebendo"
        if ($script:Alarme) {
            $situ = "TSE: SEM RESPOSTA ha $(Segundos-Sem-Tse) s"
            if ($script:ErroFoi404) { $situ = "TSE: responde, mas sem boletim ha $(Segundos-Sem-Tse) s" }
        }
        Escrever-Log "$txt | estados com boletim: $comDado de 27 | $situ" $(if ($script:Alarme) { "ERRO" } else { "INFO" })
        # Evolucao minuto a minuto: mostra que esta gravando; alerta se a
        # apuracao anda (urnas < 100%) e nenhum ponto novo ha 5 minutos.
        if ($script:Cache.ContainsKey("br") -and $script:Cache["br"].secoes.pct -gt 0) {
            $semNovo = $(if ($script:EvolucaoNovoEm) { ((Get-Date) - $script:EvolucaoNovoEm).TotalMinutes } else { 999 })
            if ($script:Cache["br"].secoes.pct -lt 100 -and $semNovo -gt 5) {
                Escrever-Log ("EVOLUCAO: nenhum ponto novo ha {0:N0} min ({1} pontos gravados) - confira se o TSE esta atualizando" -f [math]::Min($semNovo, 999), $script:Evolucao.Count) "AVISO"
            } else {
                Escrever-Log ("GRAVANDO EVOLUCAO: {0} pontos (ultimo {1})" -f $script:Evolucao.Count, $(if ($script:Evolucao.Count) { "$($script:Evolucao[$script:Evolucao.Count - 1].t)".Substring(11, 5) } else { "-" }))
            }
        }
    } catch {
        Escrever-Log "erro no ciclo: $($_.Exception.Message)" "ERRO"
    }
    if ($UmaVez) { break }
    $gasto = ((Get-Date) - $inicio).TotalSeconds
    $espera = [math]::Max(1, $Intervalo - $gasto)
    Start-Sleep -Seconds ([int] $espera)
} while ($true)
