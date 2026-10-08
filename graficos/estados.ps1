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
$Versao = "3.17 - 08/10/2026"

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
# Camara: deputado federal so tem 1o turno. No 2o turno, "eleicao_camara"
# continua no codigo do 1o turno e a tela da Camara nao se perde.
$EleicaoCamara = $Eleicao
if ((Tem-Propriedade $cfg.tse "eleicao_camara") -and $cfg.tse.eleicao_camara) { $EleicaoCamara = "$($cfg.tse.eleicao_camara)" }
# 2o TURNO: com "eleicao_estaduais_1turno" diferente de "eleicao_estaduais",
# Governador vem do 2o turno onde houver e do 1o turno nos demais estados
# (eleitos no 1o turno), e Senador sempre do 1o turno (nao tem 2o turno).
$Eleicao1T = ""
if ((Tem-Propriedade $cfg.tse "eleicao_estaduais_1turno") -and $cfg.tse.eleicao_estaduais_1turno -and
    "$($cfg.tse.eleicao_estaduais_1turno)" -ne $Eleicao) { $Eleicao1T = "$($cfg.tse.eleicao_estaduais_1turno)" }
$Modo    = "OFICIAL"
$Ensaio = ((Tem-Propriedade $cfg "ensaio") -and $cfg.ensaio -eq $true)   # ENSAIO.bat
if ($Ensaio) { $Modo = "SIMULADO" }
$Intervalo = 30
if (Tem-Propriedade $cfg "intervalo_estados_segundos") { $Intervalo = [math]::Max(15, [int] $cfg.intervalo_estados_segundos) }
$PastaWeb = Join-Path $Raiz "web"

$UFs = @("ac","al","ap","am","ba","ce","df","es","go","ma","mt","ms","mg","pa",
         "pb","pr","pe","pi","rj","rn","rs","ro","rr","sc","sp","se","to")
$Cargos = @(3, 5)   # 3 = Governador, 5 = Senador

function Montar-Url {
    param([string] $Abr, [int] $Cargo, [string] $Pleito = "")
    if (-not $Pleito) { $Pleito = $Eleicao }
    $ele6 = "{0:000000}" -f ([int] $Pleito)
    $c4 = "{0:0000}" -f $Cargo
    return "$Base/$Ciclo/$Pleito/dados/$Abr/$Abr-c$c4-e$ele6-u.json"
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
                            situacao = $st
                            valido  = ("$(Obter-Campo $c @('dvt') '')" -eq "" -or "$(Obter-Campo $c @('dvt') '')" -match '^V')
                            calculado = $false
                        }
                    }
                }
            }
        }
    }
    $cands = @($cands | Sort-Object -Property @{Expression = "votos"; Descending = $true}, numero)

    # MATEMATICAMENTE ELEITO (conta com os numeros do proprio TSE), so se o
    # TSE ainda nao escreveu a situacao. Pior caso para quem lidera: TODOS os
    # eleitores das secoes ainda nao totalizadas votam no adversario.
    #   Governador: votos do 1o > metade de (todos os votos de candidatos + faltam)
    #   Senador (nv vagas): votos do k-esimo > votos do (nv+1)-esimo + faltam
    $faltam = $null
    if (Tem-Propriedade $Bruto "e") {
        $blocoE = $Bruto.e
        if ($null -ne $blocoE -and (Tem-Propriedade $blocoE "esnt")) { $faltam = [double] (Converter-Inteiro $blocoE.esnt) }
        elseif ($null -ne $blocoE -and (Tem-Propriedade $blocoE "te") -and (Tem-Propriedade $blocoE "est")) {
            $faltam = [double] ((Converter-Inteiro $blocoE.te) - (Converter-Inteiro $blocoE.est))
        }
        elseif ($null -ne $blocoE -and (Tem-Propriedade $blocoE "te") -and (Tem-Propriedade $blocoE "c")) {
            # total - comparecimento: maior que o real, so deixa a conta mais dificil
            $faltam = [double] ((Converter-Inteiro $blocoE.te) - (Converter-Inteiro $blocoE.c))
        }
    }
    if ($null -eq $faltam -and "$(Obter-Campo $Bruto @('and') '')".ToLower() -eq "f") { $faltam = 0.0 }
    $tseJaDisse = @($cands | Where-Object { $_.eleito -or $_.segundo_turno }).Count -gt 0
    if (-not $tseJaDisse -and $null -ne $faltam -and $faltam -ge 0 -and $cands.Count -gt 0) {
        $somaVotos = 0.0
        foreach ($k in $cands) { $somaVotos += [double] $k.votos }
        if ($Cargo -eq 3) {
            $lider = $cands[0]
            if ($lider.valido -and $lider.votos -gt 0 -and (2.0 * $lider.votos) -gt ($somaVotos + $faltam)) {
                $lider.eleito = $true; $lider.calculado = $true
            } elseif ($cands.Count -ge 2) {
                # 2o TURNO definido: (1) ninguem passa de 50% nem com TODOS os que
                # faltam (so votos validos na conta, o caso mais dificil para
                # afirmar 2o turno) e (2) o 3o nao alcanca o 2o nem com todos
                # os que faltam - os dois finalistas estao garantidos.
                $somaValidos = 0.0
                foreach ($k in $cands) { if ($k.valido) { $somaValidos += [double] $k.votos } }
                $maior = 0.0
                foreach ($k in $cands) { if ($k.valido -and [double] $k.votos -gt $maior) { $maior = [double] $k.votos } }
                $semMaioria = (2.0 * ($maior + $faltam)) -le ($somaValidos + $faltam)
                $terceiro = 0.0
                if ($cands.Count -ge 3) { $terceiro = [double] $cands[2].votos }
                $segundo = $cands[1]
                $finalistas = $lider.valido -and $segundo.valido -and [double] $segundo.votos -gt ($terceiro + $faltam)
                if ($semMaioria -and $finalistas) {
                    $lider.segundo_turno = $true; $lider.calculado = $true
                    $segundo.segundo_turno = $true; $segundo.calculado = $true
                }
            }
        } else {
            $desafiante = 0.0
            if ($cands.Count -gt $vagas) { $desafiante = [double] $cands[$vagas].votos }
            for ($i = 0; $i -lt [math]::Min($vagas, $cands.Count); $i++) {
                $k = $cands[$i]
                if ($k.valido -and $k.votos -gt 0 -and [double] $k.votos -gt ($desafiante + $faltam)) {
                    $k.eleito = $true; $k.calculado = $true
                }
            }
        }
    }
    $s = $null
    if (Tem-Propriedade $Bruto "s") { $s = $Bruto.s }
    $pctUrnas = $null
    if ($null -ne $s -and (Tem-Propriedade $s "pst")) { $pctUrnas = Converter-Decimal $s.pst }
    # Comparecimento do estado (bloco "e" do boletim: pc = % de eleitores que votaram)
    $pctComparec = $null
    if (Tem-Propriedade $Bruto "e") {
        $eleitorado = $Bruto.e
        if ($null -ne $eleitorado -and (Tem-Propriedade $eleitorado "pc")) { $pctComparec = Converter-Decimal $eleitorado.pc }
    }
    return [pscustomobject]@{
        tem        = $true
        fase       = $fase
        andamento  = "$(Obter-Campo $Bruto @('and') '')".ToLower()
        geracao    = "$(Obter-Campo $Bruto @('dg') '') $(Obter-Campo $Bruto @('hg') '')"
        hora       = "$(Obter-Campo $Bruto @('hg') '')"
        urnas_pct  = $pctUrnas
        comparec_pct = $pctComparec
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
    param([string] $Abr, [int] $Cargo, [string] $Pleito = "", [string] $Chave = "")
    $url = Montar-Url $Abr $Cargo $Pleito
    if (-not $Chave) { $Chave = "$Abr-$Cargo" }
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
    if ($script:Cache.ContainsKey($Chave)) {
        $velho = $script:Cache[$Chave]
        $pNovo = $r.urnas_pct; $pVelho = $velho.urnas_pct
        if ($null -ne $pNovo -and $null -ne $pVelho -and $pNovo -lt $pVelho - 0.001) {
            $gN = Converter-Geracao $r.geracao; $gV = Converter-Geracao $velho.geracao
            if (-not ($null -ne $gN -and $null -ne $gV -and $gN -gt $gV)) {
                $n = 1
                if ($script:Regressao.ContainsKey($Chave)) { $n = $script:Regressao[$Chave] + 1 }
                $script:Regressao[$Chave] = $n
                if ($n -lt 3) {
                    if ($script:ETags.ContainsKey($url)) { $script:ETags.Remove($url) }
                    Escrever-Log ("{0}: urnas voltaram de {1}% para {2}% - mantendo o ultimo bom ({3}a vez)" -f $Chave, $pVelho, $pNovo, $n) "AVISO"
                    return
                }
            }
        }
    }
    if ($script:Regressao.ContainsKey($Chave)) { $script:Regressao.Remove($Chave) }
    $script:Cache[$Chave] = $r
}

# ------------------------------------------- CAMARA: deputados federais eleitos
# Mesmo pleito estadual, cargo 6. Conta, em cada estado, os candidatos que o
# TSE marcou como eleitos (Eleito por QP / Eleito por media), por partido.
# Nada calculado: so a palavra do TSE. A cada 3 ciclos (o arquivo de SP e
# grande) e, com o resultado final, o TSE responde "sem mudanca" (304).
$script:Camara = @{}
$script:CamaraMotivo = [ordered]@{}   # estado sem eleitos na tela -> por que (vai para o log e o gerenciador)
# ASSEMBLEIAS LEGISLATIVAS: o mesmo, cargo 7 (Deputado Estadual) e, no DF,
# cargo 8 (Deputado Distrital). Mesmo pleito e mesmo codigo da Camara.
$script:Assembleia = @{}
$script:AssembleiaMotivo = [ordered]@{}
function Ler-Camara {
    param([string] $Abr, [int] $Cargo = 6)
    $alvo = $script:Camara; $motivos = $script:CamaraMotivo; $nomeCargo = "Deputado Federal"
    if ($Cargo -ne 6) { $alvo = $script:Assembleia; $motivos = $script:AssembleiaMotivo; $nomeCargo = $(if ($Cargo -eq 8) { "Deputado Distrital" } else { "Deputado Estadual" }) }
    $url = Montar-Url $Abr $Cargo $EleicaoCamara
    $bruto = Obter-Boletim $url
    # "sem mudanca" (304) sem nunca ter guardado este estado: pede de novo sem cache
    if ("$bruto" -eq "SEM-MUDANCA" -and -not $alvo.ContainsKey($Abr)) {
        if ($script:ETags.ContainsKey($url)) { $script:ETags.Remove($url) }
        $bruto = Obter-Boletim $url
    }
    if ("$bruto" -eq "SEM-MUDANCA") { return }
    if ($null -eq $bruto) {
        if ($script:Ausentes.ContainsKey($url)) { $motivos[$Abr] = "TSE ainda nao publicou o arquivo (404)" }
        else { $motivos[$Abr] = "sem resposta do TSE ($($script:UltimoErro))" }
        return
    }
    $fase = "$(Obter-Campo $bruto @('f') '')".ToUpper()
    if ($fase -eq "S" -or $fase -eq "T") { $motivos[$Abr] = "boletim de simulado/teste (fase $fase) - ignorado"; return }
    $porPartido = [ordered]@{}
    $vagas = 0; $eleitos = 0
    $listaEleitos = New-Object System.Collections.ArrayList   # tela "Deputados federais eleitos"
    if (Tem-Propriedade $bruto "carg") {
        foreach ($cg in $bruto.carg) {
            if ("$(Obter-Campo $cg @('cd') '')" -ne "$Cargo") { continue }
            $vagas = Converter-Inteiro (Obter-Campo $cg @('nv') 0)
            if (-not (Tem-Propriedade $cg "agr")) { continue }
            foreach ($agr in $cg.agr) {
                if (-not (Tem-Propriedade $agr "par")) { continue }
                foreach ($pa in $agr.par) {
                    $sigla = Decodificar-Entidades "$(Obter-Campo $pa @('sg','nm') '')"
                    if (-not (Tem-Propriedade $pa "cand")) { continue }
                    foreach ($c in $pa.cand) {
                        $st = Decodificar-Entidades "$(Obter-Campo $c @('st') '')"
                        $eleitoDep = $false
                        if ($st) { $eleitoDep = ($st -match 'eleit') -and -not ($st -match 'n\S{1,2}o\s+eleit') -and -not ($st -match 'turno') }
                        else { $eleitoDep = ("$(Obter-Campo $c @('e') '')".ToLower() -eq "s") }
                        if ($eleitoDep) {
                            if (-not $porPartido.Contains($sigla)) { $porPartido[$sigla] = 0 }
                            $porPartido[$sigla] = [int] $porPartido[$sigla] + 1
                            $eleitos++
                            [void] $listaEleitos.Add([pscustomobject]@{
                                nome = Decodificar-Entidades "$(Obter-Campo $c @('nmu','nm') '')"
                                partido = $sigla
                                numero = "$(Obter-Campo $c @('n') '')"
                                sqcand = "$(Obter-Campo $c @('sqcand') '')"
                                votos = Converter-Inteiro (Obter-Campo $c @('vap') 0)
                                situacao = $st
                            })
                        }
                    }
                }
            }
        }
    }
    $pctUrnas = $null
    if (Tem-Propriedade $bruto "s") { $pctUrnas = Converter-Decimal $bruto.s.pst }
    $nCand = 0
    if (Tem-Propriedade $bruto "carg") { foreach ($cg in $bruto.carg) { if ((Tem-Propriedade $cg "agr")) { foreach ($agr in $cg.agr) { if (Tem-Propriedade $agr "par") { foreach ($pa in $agr.par) { if (Tem-Propriedade $pa "cand") { $nCand += @($pa.cand).Count } } } } } } }
    if ($eleitos -gt 0) { if ($motivos.Contains($Abr)) { $motivos.Remove($Abr) } }
    elseif ($nCand -eq 0) { $motivos[$Abr] = "arquivo do TSE sem candidatos de $nomeCargo (cargo $Cargo)" }
    else { $motivos[$Abr] = "o TSE ainda nao marcou eleitos ($nCand candidatos lidos, nenhum com situacao Eleito)" }
    $alvo[$Abr] = [pscustomobject]@{
        vagas = $vagas; eleitos = $eleitos; urnas_pct = $pctUrnas
        andamento = "$(Obter-Campo $bruto @('and') '')".ToLower()
        partidos = [pscustomobject] $porPartido
        lista = @($listaEleitos | Sort-Object -Property @{Expression = "votos"; Descending = $true}, nome | Select-Object -First $(if ($Cargo -eq 6) { 100000 } else { 5 }))
    }
}

# ------------------------------------------------- 2022, para comparacao
# Abstencao, brancos, nulos e comparecimento do 1o turno de 2022 (Presidente,
# Brasil), lidos dos arquivos do PROPRIO TSE - nada digitado a mao. Tenta os
# dois formatos de endereco 1 vez a cada 10 minutos ate achar; sem 2022 a
# tela de comparacao diz "indisponivel".

$script:Ref2022 = $null
$script:Prox2022 = [datetime]::MinValue
$Ciclo2022 = "ele2022"; $Eleicao2022 = "544"
if (Tem-Propriedade $cfg "comparar_2022") {
    if ((Tem-Propriedade $cfg.comparar_2022 "ciclo") -and $cfg.comparar_2022.ciclo) { $Ciclo2022 = "$($cfg.comparar_2022.ciclo)" }
    if ((Tem-Propriedade $cfg.comparar_2022 "eleicao") -and $cfg.comparar_2022.eleicao) { $Eleicao2022 = "$($cfg.comparar_2022.eleicao)" }
}

function Campo-2022 {
    # O arquivo de 2022 pode trazer o campo no topo ou dentro de s/e/v.
    param($Obj, [string[]] $Nomes)
    foreach ($n in $Nomes) {
        if (Tem-Propriedade $Obj $n) {
            $v = $Obj.$n
            if (($v -is [string] -or $v -is [ValueType]) -and "$v" -ne "") { return Converter-Decimal $v }
        }
        foreach ($bl in @("s", "e", "v")) {
            if ((Tem-Propriedade $Obj $bl) -and $null -ne $Obj.$bl -and (Tem-Propriedade $Obj.$bl $n)) {
                $v = $Obj.$bl.$n
                if ($null -ne $v -and "$v" -ne "") { return Converter-Decimal $v }
            }
        }
    }
    return $null
}

function Buscar-2022 {
    if ($null -ne $script:Ref2022 -or (Get-Date) -lt $script:Prox2022) { return }
    $script:Prox2022 = (Get-Date).AddMinutes(10)
    $e6 = "{0:000000}" -f ([int] $Eleicao2022)
    $urls = @("$Base/$Ciclo2022/$Eleicao2022/dados-simplificados/br/br-c0001-e$e6-r.json",
              "$Base/$Ciclo2022/$Eleicao2022/dados/br/br-c0001-e$e6-u.json")
    foreach ($url in $urls) {
        try {
            $resp = Invoke-WebRequest -Uri $url -Headers @{ "User-Agent" = "gctse-graficos/1.0"; "Accept" = "application/json,*/*" } -TimeoutSec 15 -UseBasicParsing
            $obj = (Ler-Texto-Resposta $resp) | ConvertFrom-Json
        } catch {
            Fechar-Resposta $_
            $obj = Copia-Local $url            # GUARDAR-DADOS-TSE
            if ($null -eq $obj) { continue }
        }
        $r = [pscustomobject]@{
            pct_comparec  = Campo-2022 $obj @("pc")
            pct_abstencao = Campo-2022 $obj @("pa")
            pct_brancos   = Campo-2022 $obj @("pvb")
            pct_nulos     = Campo-2022 $obj @("ptvn", "pvn")
            urnas_pct     = Campo-2022 $obj @("pst")
            fonte         = $url
        }
        if ($null -ne $r.pct_abstencao -and $null -ne $r.pct_brancos -and $null -ne $r.pct_nulos -and $null -ne $r.pct_comparec) {
            $script:Ref2022 = $r
            Escrever-Log ("2022 (TSE) para comparacao: abstencao {0}% | brancos {1}% | nulos {2}% | comparecimento {3}%" -f $r.pct_abstencao, $r.pct_brancos, $r.pct_nulos, $r.pct_comparec) "OK"
            return
        }
    }
    Escrever-Log "2022 (TSE) para comparacao: ainda nao encontrado - tento de novo em 10 min" "AVISO"
}

# --------------------------------- 2o TURNO DE 2022 (Presidente), por estado
# Para a tela "2o turno: 2022 x 2026": % de cada partido no 2o turno de 2022
# (Brasil e 27 estados), do boletim que o TSE mantem publicado. Codigo da
# eleicao: comparar_2022.eleicao_2turno no config (padrao 545). So no modo 2o
# turno; tenta a cada 10 min ate ter os 28; sem o do Brasil, nem pede os estados.
$script:Ref2022T2 = $null
$script:Prox2022T2 = [datetime]::MinValue
$Eleicao2022T2 = "545"
if ((Tem-Propriedade $cfg "comparar_2022") -and (Tem-Propriedade $cfg.comparar_2022 "eleicao_2turno") -and $cfg.comparar_2022.eleicao_2turno) { $Eleicao2022T2 = "$($cfg.comparar_2022.eleicao_2turno)" }
function Partidos-2022([object] $Obj) {
    $r = [ordered]@{}
    if (-not (Tem-Propriedade $Obj "carg")) { return $r }
    foreach ($cg in $Obj.carg) {
        if (-not (Tem-Propriedade $cg "agr")) { continue }
        foreach ($agr in $cg.agr) {
            if (-not (Tem-Propriedade $agr "par")) { continue }
            foreach ($pa in $agr.par) {
                $sg = Decodificar-Entidades "$(Obter-Campo $pa @('sg') '')"
                if (-not $sg -or -not (Tem-Propriedade $pa "cand")) { continue }
                foreach ($c in $pa.cand) { $v = Converter-Decimal (Obter-Campo $c @('pvap') ''); if ($null -ne $v) { $r[$sg] = $v; $r["_nome_$sg"] = Decodificar-Entidades "$(Obter-Campo $c @('nmu','nm') '')"; $r["_votos_$sg"] = Converter-Inteiro (Obter-Campo $c @('vap') 0) } }
            }
        }
    }
    # comparecimento, abstencao, brancos e nulos do mesmo boletim (2022 x 2026)
    foreach ($par in @(@("_pc", @("pc")), @("_pa", @("pa")), @("_pvb", @("pvb")), @("_pvn", @("ptvn", "pvn")), @("_aptos", @("te")))) { $x = Campo-2022 $Obj $par[1]; if ($null -ne $x) { $r[$par[0]] = $x } }
    return $r
}

# --------------------------- GOVERNADORES ELEITOS EM 2022 (por partido)
# Boletim de Governador de 2022 que o TSE mantem publicado: 1o turno
# (comparar_2022.eleicao_estaduais, padrao 546) e, nos estados com 2o turno,
# o 2o (comparar_2022.eleicao_estaduais_2turno, padrao 547). Eleito = marca
# do proprio TSE. Sem o arquivo, a tela diz "2022 indisponivel".
$script:Ref2022Gov = $null
$script:Prox2022Gov = [datetime]::MinValue
$Est2022 = "546"; $Est2022T2 = "547"
if (Tem-Propriedade $cfg "comparar_2022") {
    if ((Tem-Propriedade $cfg.comparar_2022 "eleicao_estaduais") -and $cfg.comparar_2022.eleicao_estaduais) { $Est2022 = "$($cfg.comparar_2022.eleicao_estaduais)" }
    if ((Tem-Propriedade $cfg.comparar_2022 "eleicao_estaduais_2turno") -and $cfg.comparar_2022.eleicao_estaduais_2turno) { $Est2022T2 = "$($cfg.comparar_2022.eleicao_estaduais_2turno)" }
}
function Obter-2022([string] $Url) {
    try {
        $resp = Invoke-WebRequest -Uri $Url -Headers @{ "User-Agent" = "gctse-graficos/1.0"; "Accept" = "application/json,*/*" } -TimeoutSec 15 -UseBasicParsing
        return (Ler-Texto-Resposta $resp) | ConvertFrom-Json
    } catch { Fechar-Resposta $_; return (Copia-Local $Url) }
}
function Eleito-2022($Obj) {
    $r = @{ eleito = $null; turno2 = $false }
    if ($null -eq $Obj -or -not (Tem-Propriedade $Obj "carg")) { return $r }
    foreach ($cg in $Obj.carg) { foreach ($agr in @($cg.agr)) { foreach ($pa in @($agr.par)) {
        if ($null -eq $pa) { continue }
        $sg = Decodificar-Entidades "$(Obter-Campo $pa @('sg') '')"
        foreach ($c in @($pa.cand)) {
            if ($null -eq $c) { continue }
            $st = Decodificar-Entidades "$(Obter-Campo $c @('st') '')"
            if ($st -match 'turno') { $r.turno2 = $true }
            $el = $(if ($st) { ($st -match 'eleit') -and -not ($st -match 'n\S{1,2}o\s+eleit') -and -not ($st -match 'turno') } else { "$(Obter-Campo $c @('e') '')".ToLower() -eq "s" })
            if ($el) { $r.eleito = [pscustomobject]@{ partido = $sg; nome = Decodificar-Entidades "$(Obter-Campo $c @('nmu','nm') '')"; pct = Converter-Decimal (Obter-Campo $c @('pvap') '') } }
        } } } }
    return $r
}
function Buscar-2022-Gov {
    if ($null -ne $script:Ref2022Gov -and $script:Ref2022Gov.completo) { return }
    if ((Get-Date) -lt $script:Prox2022Gov) { return }
    $script:Prox2022Gov = (Get-Date).AddMinutes(10)
    $e1 = "{0:000000}" -f ([int] $Est2022); $e2 = "{0:000000}" -f ([int] $Est2022T2)
    $porUf = [ordered]@{}
    foreach ($u in $UFs) {
        $b1 = Obter-2022 "$Base/$Ciclo2022/$Est2022/dados/$u/$u-c0003-e$e1-u.json"
        if ($null -eq $b1) { if ($u -eq "ac") { Escrever-Log "governadores de 2022 (TSE, eleicao $Est2022): nao encontrado - tento de novo em 10 min (outro codigo: comparar_2022.eleicao_estaduais no config)" "AVISO"; return }; continue }
        $x = Eleito-2022 $b1; $turno = 1
        if ($null -eq $x.eleito -and $x.turno2) { $x = Eleito-2022 (Obter-2022 "$Base/$Ciclo2022/$Est2022T2/dados/$u/$u-c0003-e$e2-u.json"); $turno = 2 }
        if ($x.eleito) { $porUf[$u] = [pscustomobject]@{ partido = $x.eleito.partido; nome = $x.eleito.nome; pct = $x.eleito.pct; turno = $turno } }
    }
    $script:Ref2022Gov = [pscustomobject]@{ eleicao = $Est2022; eleicao_2turno = $Est2022T2; ufs = [pscustomobject] $porUf; completo = ($porUf.Count -ge 27) }
    Escrever-Log ("governadores de 2022 (TSE): {0} de 27 estados" -f $porUf.Count) $(if ($porUf.Count -ge 27) { "OK" } else { "AVISO" })
}
function Buscar-2022-2T {
    if (-not $Eleicao1T) { return }                      # so no modo 2o turno
    if ($null -ne $script:Ref2022T2 -and $script:Ref2022T2.completo) { return }
    if ((Get-Date) -lt $script:Prox2022T2) { return }
    $script:Prox2022T2 = (Get-Date).AddMinutes(10)
    $e6 = "{0:000000}" -f ([int] $Eleicao2022T2)
    $porUf = [ordered]@{}; $br = $null
    foreach ($abr in @("br") + $UFs + @("zz")) {
        $url = "$Base/$Ciclo2022/$Eleicao2022T2/dados/$abr/$abr-c0001-e$e6-u.json"
        try {
            $resp = Invoke-WebRequest -Uri $url -Headers @{ "User-Agent" = "gctse-graficos/1.0"; "Accept" = "application/json,*/*" } -TimeoutSec 15 -UseBasicParsing
            $ps = Partidos-2022 ((Ler-Texto-Resposta $resp) | ConvertFrom-Json)
        } catch { Fechar-Resposta $_; $loc = Copia-Local $url; $ps = $(if ($null -ne $loc) { Partidos-2022 $loc } else { $null }) }
        if ($abr -eq "br") { if ($null -eq $ps -or $ps.Count -lt 2) { Escrever-Log "2o turno de 2022 (TSE, eleicao $Eleicao2022T2): nao encontrado - tento de novo em 10 min" "AVISO"; return }; $br = $ps }
        elseif ($null -ne $ps -and $ps.Count -ge 2) { $porUf[$abr] = [pscustomobject] $ps }
    }
    $nUf = @($porUf.Keys | Where-Object { $_ -ne "zz" }).Count
    $script:Ref2022T2 = [pscustomobject]@{ eleicao = $Eleicao2022T2; br = [pscustomobject] $br; ufs = [pscustomobject] $porUf; completo = ($nUf -ge 27) }
    Escrever-Log ("2o turno de 2022 (TSE) para comparacao: Brasil + {0} de 27 estados{1}" -f $nUf, $(if ($porUf.Contains("zz")) { " + exterior" } else { "" })) $(if ($nUf -ge 27) { "OK" } else { "AVISO" })
}

# ------------------------------------------------------------- gravar dados

function Gravar-Dados {
    $porEstado = [ordered]@{}
    foreach ($u in $UFs) {
        $g = [pscustomobject]@{ tem = $false }; $s = [pscustomobject]@{ tem = $false }
        if ($script:Cache.ContainsKey("$u-3")) { $g = $script:Cache["$u-3"] }
        if ($script:Cache.ContainsKey("$u-5")) { $s = $script:Cache["$u-5"] }
        $turnoG = 1; $eleG = $Eleicao
        if ($Eleicao1T) {
            # estado com 2o turno (boletim do 2o turno com candidatos) ou o 1o turno
            $tem2 = ($g.tem -and @($g.candidatos).Count -gt 0)
            if ($tem2) { $turnoG = 2 }
            else {
                $eleG = $Eleicao1T
                if ($script:Cache.ContainsKey("$u-3-1t")) { $g = $script:Cache["$u-3-1t"] } else { $g = [pscustomobject]@{ tem = $false } }
            }
        }
        $g = $g | Select-Object *, @{ n = "turno"; e = { $turnoG } }, @{ n = "eleicao"; e = { $eleG } }
        $porEstado["$u"] = [pscustomobject]@{ gov = $g; sen = $s }
    }
    $ult = ""
    if ($null -ne $script:UltimaResposta) { $ult = $script:UltimaResposta.ToString("HH:mm:ss") }
    $dados = [ordered]@{
        versao        = $Versao
        modo          = $Modo
        ensaio        = $Ensaio
        pid           = $PID
        gravado_em    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        copia_local   = $script:UsandoLocal.Count
        recebendo_tse = (-not $script:Alarme)
        tse_nao_publicou = ($script:Alarme -and $script:ErroFoi404)
        ultimo_tse    = $ult
        # Para a tela montar o endereco da foto oficial do TSE:
        # {base}/{ciclo}/{eleicao}/fotos/{uf}/{sqcand}.jpeg
        tse           = [pscustomobject]@{ base = $Base; ciclo = $Ciclo; eleicao = $Eleicao; eleicao_camara = $EleicaoCamara; eleicao_1turno = $(if ($Eleicao1T) { $Eleicao1T } else { $Eleicao }) }
        turno         = $(if ($Eleicao1T) { 2 } else { 1 })
        ref2022       = $script:Ref2022
        ref2022_2t    = $script:Ref2022T2
        ref2022_gov   = $script:Ref2022Gov
        ufs           = $porEstado
        camara        = [pscustomobject] $script:Camara
        camara_motivos = [pscustomobject] $script:CamaraMotivo
        assembleia    = [pscustomobject] $script:Assembleia
        assembleia_motivos = [pscustomobject] $script:AssembleiaMotivo
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
        if (-not $Eleicao1T) { foreach ($u in $UFs) { foreach ($cg in $Cargos) { Ler-Abrangencia $u $cg } } }
        else {
            # 2o turno: Governador do 2o turno (so os estados que tem) a cada
            # ciclo; 1o turno (Governador e Senador, resultado final) a cada 3.
            foreach ($u in $UFs) { Ler-Abrangencia $u 3 }
            if (($script:NumCiclo % 3) -eq 1) {
                foreach ($u in $UFs) { Ler-Abrangencia $u 3 $Eleicao1T "$u-3-1t"; Ler-Abrangencia $u 5 $Eleicao1T }
            }
        }
        try { Buscar-2022 } catch { Escrever-Log "2022: $($_.Exception.Message)" "AVISO" }
        try { Buscar-2022-2T } catch { Escrever-Log "2o turno de 2022: $($_.Exception.Message)" "AVISO" }
        try { Buscar-2022-Gov } catch { Escrever-Log "governadores de 2022: $($_.Exception.Message)" "AVISO" }
        # Todos a cada 3 ciclos; estado que ainda nao tem eleitos, a CADA ciclo.
        $faltam = @($UFs | Where-Object { -not $script:Camara.ContainsKey($_) -or $script:Camara[$_].eleitos -le 0 })
        if (($script:NumCiclo % 3) -eq 1 -or $faltam.Count -gt 0) {
            try {
                $lerAgora = $(if (($script:NumCiclo % 3) -eq 1) { $UFs } else { $faltam })
                foreach ($u in $lerAgora) { Ler-Camara $u }
                $nE = 0; $nV = 0; $comEleitos = 0
                foreach ($k in $script:Camara.Keys) { $nE += $script:Camara[$k].eleitos; $nV += $script:Camara[$k].vagas; if ($script:Camara[$k].eleitos -gt 0) { $comEleitos++ } }
                Escrever-Log ("camara: {0}/27 estados com eleitos, {1} deputados federais eleitos (de {2} vagas lidas)" -f $comEleitos, $nE, $nV) $(if ($comEleitos -lt 27) { "AVISO" } else { "INFO" })
                foreach ($k in $script:CamaraMotivo.Keys) { Escrever-Log ("   camara {0}: {1}" -f $k.ToUpper(), $script:CamaraMotivo[$k]) "AVISO" }
            } catch { Escrever-Log "camara: $($_.Exception.Message)" "AVISO" }
        }
        # Assembleias (cargo 7; DF cargo 8): a cada 3 ciclos, ou a cada ciclo
        # enquanto faltar estado com eleitos.
        $faltamA = @($UFs | Where-Object { -not $script:Assembleia.ContainsKey($_) -or $script:Assembleia[$_].eleitos -le 0 })
        if (($script:NumCiclo % 3) -eq 2 -or ($faltamA.Count -gt 0 -and ($script:NumCiclo % 3) -ne 1)) {
            try {
                $lerA = $(if (($script:NumCiclo % 3) -eq 2) { $UFs } else { $faltamA })
                foreach ($u in $lerA) { Ler-Camara $u $(if ($u -eq "df") { 8 } else { 7 }) }
                $nE = 0; $nV = 0; $comEleitos = 0
                foreach ($k in $script:Assembleia.Keys) { $nE += $script:Assembleia[$k].eleitos; $nV += $script:Assembleia[$k].vagas; if ($script:Assembleia[$k].eleitos -gt 0) { $comEleitos++ } }
                Escrever-Log ("assembleias: {0}/27 estados com eleitos, {1} deputados estaduais/distritais eleitos (de {2} vagas lidas)" -f $comEleitos, $nE, $nV) $(if ($comEleitos -lt 27) { "AVISO" } else { "INFO" })
            } catch { Escrever-Log "assembleias: $($_.Exception.Message)" "AVISO" }
        }
        Conferir-Recebimento
        Gravar-Dados
        $nG = @($UFs | Where-Object { $script:Cache.ContainsKey("$_-3") }).Count
        $nS = @($UFs | Where-Object { $script:Cache.ContainsKey("$_-5") }).Count
        $eleG = 0; $segG = 0; $eleS = 0
        $tem1T = 0
        foreach ($u in $UFs) {
            # 2o turno: estado sem boletim do 2o turno conta pelo 1o turno
            $chG = "$u-3"
            if ($Eleicao1T -and -not ($script:Cache.ContainsKey($chG) -and @($script:Cache[$chG].candidatos).Count -gt 0)) { $chG = "$u-3-1t" }
            if ($script:Cache.ContainsKey($chG)) {
                if ($chG -like "*-1t") { $tem1T++ }
                $cs = @($script:Cache[$chG].candidatos)
                if (@($cs | Where-Object { $_.eleito }).Count -gt 0) { $eleG++ }
                elseif ($Eleicao1T -or @($cs | Where-Object { $_.segundo_turno }).Count -gt 0) { $segG++ }
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
        if ($Eleicao1T) { $nG = $nG + $tem1T; $pr = " | 2o TURNO: $(@($UFs | Where-Object { $script:Cache.ContainsKey("$_-3") -and @($script:Cache["$_-3"].candidatos).Count -gt 0 }).Count) estados com 2o turno$pr" }
        Escrever-Log ("governador: {0}/27 estados ({1} eleitos, {2} no 2o turno) | senador: {3}/27 ({4} eleitos){5} | {6}" -f $nG, $eleG, $segG, $nS, $eleS, $pr, $situ) $(if ($script:Alarme) { "ERRO" } else { "INFO" })
    } catch {
        Escrever-Log "erro no ciclo: $($_.Exception.Message)" "ERRO"
    }
    if ($UmaVez) { break }
    $gasto = ((Get-Date) - $inicio).TotalSeconds
    $espera = [math]::Max(1, $Intervalo - $gasto)
    Start-Sleep -Seconds ([int] $espera)
} while ($true)
