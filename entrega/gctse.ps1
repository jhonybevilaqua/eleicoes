<#
    gctse - Apuracao do TSE para o gerador de caracteres
    ------------------------------------------------------------------
    Roda direto no Windows. Nao instala nada, nao precisa de Python e nao
    precisa de internet alem do proprio TSE.

    Escrito para Windows PowerShell 5.1 (o que ja vem no Windows), sem
    recursos de versoes mais novas.

        .\gctse.ps1 -Preencher    enche TARJAS com exemplos, para montar a cena
        .\gctse.ps1 -Descobrir    mostra os codigos do pleito
        .\gctse.ps1 -Conferir     testa a conexao e grava CONFERIR.txt
        .\gctse.ps1 -Validar      confere numero por numero contra o TSE
        .\gctse.ps1 -Ensaio       dados ficticios, nao consulta o TSE
        .\gctse.ps1 -Teste        aceita o simulado do TSE (fase S)
        .\gctse.ps1               no ar: so boletim oficial
#>

[CmdletBinding()]
param(
    [switch] $Descobrir,
    [switch] $Conferir,
    [switch] $Validar,
    [switch] $Preencher,
    [switch] $Ensaio,
    [switch] $Teste,
    [switch] $UmaVez,
    [int]    $DuracaoEnsaio = 600,
    [string] $Config = "config.json"
)

# Versao impressa na partida e no painel. Sem carimbo, "qual versao esta
# rodando ai?" so se responde abrindo arquivo e comparando a olho - e no
# meio de um teste com janela de horario ninguem faz isso.
$Versao = "2.3 - 15/09/2026"

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# TLS 1.2: o Windows PowerShell 5.1 ainda negocia TLS 1.0 por padrao em
# maquina antiga, e o TSE recusa. Sem esta linha a coleta falha sem explicar.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Trabalha sempre a partir da pasta do proprio script: duplo clique herda um
# diretorio qualquer, e ai os caminhos relativos apontam para o lugar errado.
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz

# ---------------------------------------------------------------- utilidades

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
        Add-Content -Path ("logs\gctse-{0}.log" -f (Get-Date -Format "yyyy-MM-dd")) -Value $linha
    } catch { }
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

function Formatar-Inteiro {
    param([int64] $Valor)
    return $Valor.ToString("N0", [Globalization.CultureInfo]::GetCultureInfo("pt-BR"))
}

function Formatar-Percentual {
    param([double] $Valor)
    return ($Valor.ToString("N2", [Globalization.CultureInfo]::GetCultureInfo("pt-BR")) + "%")
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

function Limitar-Texto {
    # Corta no limite sem quebrar palavra no meio.
    param([string] $Texto, [int] $Limite)
    if ($null -eq $Texto) { return "" }
    $t = ((Decodificar-Entidades $Texto) -replace '\s+', ' ').Trim().ToUpper()
    if ($Limite -le 0 -or $t.Length -le $Limite) { return $t }
    $corte = $t.Substring(0, $Limite)
    if ($corte.Contains(' ')) { $corte = $corte.Substring(0, $corte.LastIndexOf(' ')) }
    return $corte.TrimEnd()
}

function Escrever-Arquivo {
    # Escrita atomica: o GC pode ler a qualquer instante, e um arquivo lido
    # pela metade vira placar truncado no ar. Grava em .tmp e promove.
    param([string] $Caminho, [string] $Conteudo)
    $pasta = Split-Path -Parent $Caminho
    if ($pasta -and -not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    $temporario = "$Caminho.tmp"
    $utf8 = New-Object System.Text.UTF8Encoding($false)   # sem BOM
    [IO.File]::WriteAllText($temporario, $Conteudo, $utf8)
    Move-Item -Path $temporario -Destination $Caminho -Force
}

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

function Obter-Hash {
    param([string] $Texto)
    $sha = [Security.Cryptography.SHA1]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Texto))
    return -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

# ------------------------------------------------------------------- config

if (-not (Test-Path $Config)) {
    Escrever-Log "Arquivo $Config nao encontrado nesta pasta." "ERRO"
    exit 1
}
# Um erro de virgula no config derrubava o programa com pilha do PowerShell
# na tela - ilegivel para quem so precisa saber qual linha consertar.
try {
    $cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Escrever-Log "O arquivo $Config esta com erro de digitacao." "ERRO"
    Write-Host ""
    Write-Host "  O Windows nao conseguiu ler o config.json. Quase sempre e"
    Write-Host "  virgula a mais, virgula a menos ou aspas faltando."
    Write-Host ""
    Write-Host "  Detalhe tecnico: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "  Se nao achar o erro, cole o config.json em jsonlint.com ou"
    Write-Host "  peca uma copia nova."
    Write-Host ""
    exit 1
}
$UrlOficial = $cfg.tse.base_url

# O simulado do TSE fica em OUTRO endereco (resultados-sim..., prefixo
# /simulado) e nao no endereco oficial. O -Teste troca os dois de uma vez:
# aponta para o ambiente de simulado E aceita boletins de fase S.
if ($Teste -and (Tem-Propriedade $cfg.tse "base_url_simulado") -and $cfg.tse.base_url_simulado) {
    $cfg.tse.base_url = $cfg.tse.base_url_simulado
    if ((Tem-Propriedade $cfg.tse "pleito_simulado") -and $cfg.tse.pleito_simulado) {
        $cfg.tse.pleito = $cfg.tse.pleito_simulado
    }
    if ((Tem-Propriedade $cfg.tse "eleicao_simulado") -and $cfg.tse.eleicao_simulado) {
        $cfg.tse.eleicao = $cfg.tse.eleicao_simulado
    }
    if (Tem-Propriedade $cfg.tse "eleicao_por_cargo_simulado") {
        $cfg.tse.eleicao_por_cargo = $cfg.tse.eleicao_por_cargo_simulado
    }
    Escrever-Log "MODO TESTE: lendo o ambiente de SIMULADO em $($cfg.tse.base_url)"
}

$PastaSaida = $cfg.pasta_saida
$LimiteNome = $cfg.texto.limite_nome
$LimitePartido = $cfg.texto.limite_partido
$SeloNaoOficial = $cfg.texto.selo_nao_oficial
$PadraoFoto = $cfg.texto.padrao_foto
$PastaFotos = ""
if (Tem-Propriedade $cfg.texto "pasta_fotos") { $PastaFotos = "$($cfg.texto.pasta_fotos)" }
if ($PastaFotos -and -not [IO.Path]::IsPathRooted($PastaFotos)) {
    $PastaFotos = Join-Path (Get-Location) $PastaFotos
}
$FotoReserva = ""
if (Tem-Propriedade $cfg.texto "foto_reserva") { $FotoReserva = "$($cfg.texto.foto_reserva)" }
$CorPadrao = $cfg.texto.cor_padrao

function Obter-Cor {
    param([string] $Partido)
    $sigla = ([string] $Partido).Trim().ToUpper()
    if ($sigla -and (Tem-Propriedade $cfg.texto.cores_partido $sigla)) {
        return $cfg.texto.cores_partido.$sigla
    }
    return $CorPadrao
}

# Caminho de 2026, confirmado pelas URLs do simulado: o diretorio e o
# codigo da ELEICAO e a pasta e "dados". Em 2022 era o codigo do pleito e
# "dados-simplificados" - por isso o caminho vive no config, nao aqui.
$PadraoUrlPadrao = "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-c{cargo4}-e{eleicao6}-u.json"

function Obter-Eleicao {
    # Presidente e Governador/Senador NAO ficam na mesma eleicao. O TSE
    # divide o pleito em eleicoes por esfera - no simulado de 2026, 21270 e
    # a Federal (Presidente) e 21272 a Estadual (Governador, Senador). Usar
    # um codigo so para tudo devolve 404 em metade das tarjas, e a tela fica
    # sem governador sem ninguem entender por que.
    param([int] $Cargo)
    if (Tem-Propriedade $cfg.tse "eleicao_por_cargo") {
        $mapa = $cfg.tse.eleicao_por_cargo
        if (Tem-Propriedade $mapa "$Cargo") {
            $v = $mapa."$Cargo"
            if ($v) { return "$v" }
        }
    }
    return "$($cfg.tse.eleicao)"
}

function Montar-Url {
    # O caminho dos arquivos mudou entre 2022 e 2026 (de dados-simplificados
    # com o codigo do PLEITO, para dados com o codigo da ELEICAO), e o TSE
    # pode mexer nisso de novo antes de outubro. Por isso o caminho e um
    # molde no config.json, e nao codigo: descobrir o caminho certo no
    # CONFERIR e usa-lo vira edicao de uma linha, nao versao nova.
    param([string] $Abrangencia, [int] $Cargo, [string] $Molde = "")
    $dir = $Abrangencia
    if ($Abrangencia.Length -gt 2) { $dir = $Abrangencia.Substring(0, 2) }
    if (-not $Molde) {
        $Molde = $PadraoUrlPadrao
        if ((Tem-Propriedade $cfg.tse "padrao_url") -and $cfg.tse.padrao_url) {
            $Molde = "$($cfg.tse.padrao_url)"
        }
    }
    $u = $Molde
    $u = $u.Replace("{base}", $cfg.tse.base_url.TrimEnd('/'))
    $u = $u.Replace("{ciclo}", "$($cfg.tse.ciclo)")
    $u = $u.Replace("{pleito}", "$($cfg.tse.pleito)")
    $ele = Obter-Eleicao $Cargo
    $u = $u.Replace("{eleicao6}", ("{0:000000}" -f ([int] $ele)))
    $u = $u.Replace("{eleicao}", "$ele")
    $u = $u.Replace("{cargo4}", ("{0:0000}" -f $Cargo))
    $u = $u.Replace("{cargo}", "$Cargo")
    $u = $u.Replace("{dir}", $dir)
    $u = $u.Replace("{abr}", $Abrangencia)
    return $u
}

# ------------------------------------------------------------------- coleta

$Cache = @{}    # url -> ETag, para nao rebaixar a origem do TSE
$script:Requisicoes = New-Object System.Collections.ArrayList
$script:MudancasTotal = 0
$script:BoletinsOk = 0
$script:UltimaSelecao = $null
$script:DesdeUltimaOlhada = 0
$script:UltimaMudanca = $null
$script:TotalRequisicoes = 0

function Atender-Troca-De-Praca {
    # A troca de praca nao pode esperar o ciclo terminar. Uma varredura das
    # 27 pracas leva varios segundos, e se o operador escolhe um estado no
    # meio dela, a tarja so acompanharia depois - tempo demais com o estado
    # errado no ar. Esta funcao so le cache e grava arquivo, nao faz
    # requisicao nenhuma, entao pode ser chamada de dentro do ciclo.
    if (-not (Tem-Propriedade $cfg "selecao")) { return $false }
    $agora = (($cfg.selecao.saidas | ForEach-Object { (Ler-Selecao $_.cargo).uf }) -join ",")
    if ($agora -eq $script:UltimaSelecao) { return $false }
    $script:UltimaSelecao = $agora
    $null = Publicar-Selecionada $script:CacheBoletins
    foreach ($saida in $cfg.selecao.saidas) {
        $praca = Ler-Selecao $saida.cargo
        if ($null -ne $praca) { Limpar-Alerta $praca.uf $saida.cargo }
    }
    Escrever-Alertas
    Escrever-Log "selecao trocada: $agora" "OK"
    return $true
}

function Aguardar-Vez {
    # O TSE bloqueia IP que passa do limite de requisicoes por minuto, e uma
    # resposta 304 CONTA como requisicao - o cache por ETag economiza banda,
    # nao contagem. Este controle e o que impede o bloqueio: segura a fila
    # antes de estourar, em vez de descobrir no ar que o IP caiu.
    $limite = 80
    if (Tem-Propriedade $cfg "limite_requisicoes_por_minuto") {
        $limite = [int] $cfg.limite_requisicoes_por_minuto
    }
    while ($true) {
        $agora = Get-Date
        while ($script:Requisicoes.Count -gt 0 -and
               ($agora - $script:Requisicoes[0]).TotalSeconds -ge 60) {
            $script:Requisicoes.RemoveAt(0)
        }
        if ($script:Requisicoes.Count -lt $limite) { break }
        $esperar = 60 - ($agora - $script:Requisicoes[0]).TotalSeconds
        if ($esperar -gt 0) {
            Escrever-Log ("limite de {0} req/min atingido: aguardando {1:N1}s" -f $limite, $esperar) "AVISO"
            # Espera vigiando a selecao: e justamente aqui que o coletor passa
            # mais tempo parado, e seria o pior momento para ignorar o operador.
            $restante = [int] [math]::Ceiling($esperar)
            for ($e = 0; $e -lt $restante; $e++) {
                Start-Sleep -Milliseconds 1000
                $null = Atender-Troca-De-Praca
            }
            Start-Sleep -Milliseconds 200
        }
    }
    $null = $script:Requisicoes.Add((Get-Date))
    $script:TotalRequisicoes++
    # respiro minimo entre requisicoes, para nao chegar em rajada
    $gap = 120
    if (Tem-Propriedade $cfg "intervalo_minimo_ms") { $gap = [int] $cfg.intervalo_minimo_ms }
    if ($gap -gt 0) { Start-Sleep -Milliseconds $gap }
    # A cada requisicao, um olhar na selecao: numa varredura de 55 leituras
    # isso da ao operador resposta em fracao de segundo em vez de ciclo.
    $script:DesdeUltimaOlhada = $script:DesdeUltimaOlhada + 1
    if ($script:DesdeUltimaOlhada -ge 5) {
        $script:DesdeUltimaOlhada = 0
        $null = Atender-Troca-De-Praca
    }
}

function Contar-Requisicoes-Por-Ciclo {
    # Quantas requisicoes um ciclo faz, contando cada par praca+cargo uma vez.
    $pares = @{}
    if (Tem-Propriedade $cfg "tarjas") {
        foreach ($tj in $cfg.tarjas) { $pares["$($tj.abrangencia)-$($tj.cargo)"] = $true }
    }
    if (Tem-Propriedade $cfg "selecao") {
        foreach ($p in $cfg.selecao.pracas) {
            foreach ($s in $cfg.selecao.saidas) { $pares["$($p.uf)-$($s.cargo)"] = $true }
        }
    }
    if (Tem-Propriedade $cfg "listas") {
        foreach ($l in $cfg.listas) {
            foreach ($p in $l.pracas) { $pares["$($p.uf)-$($l.cargo)"] = $true }
        }
    }
    return $pares.Count
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

function Obter-Boletim {
    param([string] $Url)
    Aguardar-Vez
    # Configuravel porque CDN de governo as vezes recusa cliente que nao se
    # parece com navegador, e trocar isso no ar nao pode depender de recompilar.
    $ua = "gctse/1.0"
    if ((Tem-Propriedade $cfg.tse "user_agent") -and $cfg.tse.user_agent) { $ua = "$($cfg.tse.user_agent)" }
    $cabecalhos = @{ "User-Agent" = $ua; "Accept" = "application/json,text/plain,*/*" }
    if ($Cache.ContainsKey($Url)) { $cabecalhos["If-None-Match"] = $Cache[$Url] }
    try {
        $resposta = Invoke-WebRequest -Uri $Url -Headers $cabecalhos -TimeoutSec 15 -UseBasicParsing
    } catch {
        $codigo = 0
        try { $codigo = [int] $_.Exception.Response.StatusCode } catch { }
        if ($codigo -eq 304) { return "SEM-MUDANCA" }
        if ($codigo -eq 404) { return $null }        # ainda nao publicado
        Escrever-Log "falha em $Url : $($_.Exception.Message)" "AVISO"
        return $null
    }
    try { $Cache[$Url] = $resposta.Headers["ETag"] } catch { }
    # CDN sob carga responde HTTP 200 com pagina de erro em HTML, e conexao
    # interrompida entrega JSON pela metade. Sem esta protecao, uma resposta
    # ruim derrubava o ciclo INTEIRO - as 55 pracas - em vez de custar so a
    # praca que veio errada. Numa noite de apuracao isso e a diferenca entre
    # perder um numero e perder a tela.
    $texto = Ler-Texto-Resposta $resposta
    try {
        $objeto = $texto | ConvertFrom-Json
    } catch {
        $inicio = ""
        if ($texto) { $inicio = $texto.Substring(0, [math]::Min(80, $texto.Length)) -replace '\s+', ' ' }
        Escrever-Log "resposta nao e JSON em $Url : $inicio" "AVISO"
        # ETag de resposta ruim nao serve: forca releitura no proximo ciclo.
        if ($Cache.ContainsKey($Url)) { $Cache.Remove($Url) }
        return $null
    }
    $script:BoletinsOk = $script:BoletinsOk + 1
    return $objeto
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

function Montar-Candidato {
    param($C, [string] $Sigla, [int] $Validos)
    $votos = Converter-Inteiro (Obter-Campo $C @("vap", "votos"))
    $perc = Converter-Decimal (Obter-Campo $C @("pvap"))
    if ($perc -eq 0 -and $Validos -gt 0) { $perc = [math]::Round(100.0 * $votos / $Validos, 2) }
    $eleito = "0"
    if ("$(Obter-Campo $C @('e'))".ToLower() -eq "s") { $eleito = "1" }
    if ("$(Obter-Campo $C @('st'))" -match "^Eleito") { $eleito = "1" }
    $partido = $Sigla
    if (-not $partido) { $partido = "$(Obter-Campo $C @('cc','sgp') '')" }
    return [pscustomobject]@{
        Numero     = "$(Obter-Campo $C @('n') '')"
        Nome       = "$(Obter-Campo $C @('nmu','nm','nmurna') '')"
        Partido    = "$partido"
        Votos      = $votos
        Percentual = $perc
        Eleito     = $eleito
    }
}

function Normalizar-Boletim {
    # JSON do TSE -> objeto simples, com o que as tarjas usam.
    param($Bruto, [string] $Praca)

    $secoes = Obter-Campo $Bruto @("s")
    $pct = Converter-Decimal (Obter-Campo $secoes @("pst") (Obter-Campo $Bruto @("pst")))
    $validos = Converter-Inteiro (Obter-Campo $Bruto @("vv", "vvc"))
    if ($validos -eq 0) {
        # No formato de 2026 os votos validos ficam no bloco "v" (votacao).
        $votacao = Obter-Campo $Bruto @("v")
        $validos = Converter-Inteiro (Obter-Campo $votacao @("vv", "tvv", "vnom"))
    }

    # Em 2022 os candidatos vinham numa lista rasa no topo ("cand"). Em 2026
    # vem aninhados: carg[] -> agr[] -> par[] -> cand[], e a SIGLA DO PARTIDO
    # nao esta no candidato, esta no nivel do partido que o contem. Por isso
    # o achatamento precisa carregar a sigla para baixo em vez de so juntar
    # as listas.
    $candidatos = @()

    $lista = Obter-Campo $Bruto @("cand", "candidatos")
    if ($lista) {
        foreach ($c in $lista) {
            $candidatos += Montar-Candidato $c "$(Obter-Campo $c @('cc') '')" $validos
        }
    } elseif (Tem-Propriedade $Bruto "carg") {
        foreach ($cargo in $Bruto.carg) {
            if (-not (Tem-Propriedade $cargo "agr")) { continue }
            foreach ($agr in $cargo.agr) {
                if (-not (Tem-Propriedade $agr "par")) { continue }
                foreach ($par in $agr.par) {
                    $sigla = "$(Obter-Campo $par @('sg','nm') '')"
                    if (-not (Tem-Propriedade $par "cand")) { continue }
                    foreach ($c in $par.cand) {
                        $candidatos += Montar-Candidato $c $sigla $validos
                    }
                }
            }
        }
    }
    $candidatos = @($candidatos | Sort-Object -Property @{Expression = "Votos"; Descending = $true}, Numero)

    $fase = "$(Obter-Campo $Bruto @('f') '')".ToUpper()
    $nome = "$(Obter-Campo $Bruto @('nmabr') $Praca)"
    if ($Praca) { $nome = $Praca }

    return [pscustomobject]@{
        Fase        = $fase
        Oficial     = ($fase -eq "O")
        Praca       = $nome
        PctUrnas    = $pct
        Geracao     = "$(Obter-Campo $Bruto @('dg') '') $(Obter-Campo $Bruto @('hg') '')"
        Candidatos  = $candidatos
    }
}

# ------------------------------------------------------------------ simulador

$ScriptInicio = Get-Date
function Gerar-Simulado {
    param([string] $Abrangencia, [int] $Cargo, [string] $Praca)
    if ($DuracaoEnsaio -le 0) {
        $pct = 63.0    # retrato de meia apuracao, para montar a cena
    } else {
        $decorrido = ((Get-Date) - $ScriptInicio).TotalSeconds / $DuracaoEnsaio
        $pct = [math]::Round(100.0 * [math]::Min(1.0, $decorrido), 2)
    }

    $semente = ($Abrangencia + $Cargo).GetHashCode()
    $rnd = New-Object System.Random($semente)
    $nomes = @("CANDIDATO ENSAIO A", "CANDIDATO ENSAIO B", "CANDIDATO ENSAIO C", "CANDIDATO ENSAIO D")
    $siglas = @("PVL", "PDR", "PSU", "PNA")

    $forcas = @(); for ($i = 0; $i -lt $nomes.Count; $i++) { $forcas += $rnd.NextDouble() * 0.5 + 0.5 }
    $soma = ($forcas | Measure-Object -Sum).Sum
    $validos = [int] (4000000 * $pct / 100.0)

    $cands = @()
    for ($i = 0; $i -lt $nomes.Count; $i++) {
        $votos = [int] ($validos * $forcas[$i] / $soma)
        $perc = 0.0
        if ($validos -gt 0) { $perc = [math]::Round(100.0 * $votos / $validos, 2) }
        $cands += [pscustomobject]@{
            Numero = "$((($i + 1) * 11))"; Nome = $nomes[$i]; Partido = $siglas[$i]
            Votos = $votos; Percentual = $perc
            Eleito = $(if ($pct -ge 100 -and $i -eq 0) { "1" } else { "0" })
        }
    }
    $cands = @($cands | Sort-Object -Property @{Expression = "Votos"; Descending = $true})

    return [pscustomobject]@{
        Fase = "S"; Oficial = $false; Praca = $Praca; PctUrnas = $pct
        Geracao = (Get-Date -Format "dd/MM/yyyy HH:mm:ss"); Candidatos = $cands
    }
}

# --------------------------------------------------------------- montar tarja

function Montar-Tarja {
    param($Boletim, $Tarja)

    $selo = ""
    if (-not $Boletim.Oficial) { $selo = $SeloNaoOficial }

    $saida = [ordered]@{
        cargo            = Limitar-Texto (Obter-NomeCargo $Tarja.cargo) 24
        abrangencia      = Limitar-Texto $Boletim.Praca 24
        apuracao_pct     = Formatar-Percentual $Boletim.PctUrnas
        selo             = $selo
        hora_atualizacao = (Get-Date -Format "HH:mm")
    }

    $trilho = 0
    if (Tem-Propriedade $Tarja "trilho_px") { $trilho = [int] $Tarja.trilho_px }

    for ($i = 1; $i -le 2; $i++) {
        $c = $null
        if ($Boletim.Candidatos.Count -ge $i) { $c = $Boletim.Candidatos[$i - 1] }
        $p = "cand$i" + "_"
        if ($null -eq $c) {
            $saida[$p + "visivel"] = "0"
            $saida[$p + "nome"] = ""
            $saida[$p + "partido"] = ""
            if ($Tarja.modelo -eq "presidente") {
                $saida[$p + "foto"] = ""
                $saida[$p + "foto_existe"] = "0"
            }
            $saida[$p + "percentual"] = ""
            $saida[$p + "barra_px"] = 0
            $saida[$p + "cor"] = ""
            $saida[$p + "eleito"] = "0"
        } else {
            $largura = 0
            if ($trilho -gt 0) {
                $largura = [int] [math]::Round($trilho * $c.Percentual / 100.0)
                if ($c.Percentual -gt 0 -and $largura -lt 6) { $largura = 6 }
            }
            # Candidato sem nome vira linha em branco na tela, que e pior do
            # que slot escondido: o operador ve um espaco vazio no ar e nao
            # tem como saber se e defeito ou se e o dado.
            $nomeCand = Limitar-Texto $c.Nome $LimiteNome
            if (-not $nomeCand) {
                $saida[$p + "visivel"] = "0"
                $saida[$p + "nome"] = ""
                $saida[$p + "partido"] = ""
                if ($Tarja.modelo -eq "presidente") {
                    $saida[$p + "foto"] = ""
                    $saida[$p + "foto_existe"] = "0"
                }
                $saida[$p + "percentual"] = ""
                $saida[$p + "barra_px"] = 0
                $saida[$p + "cor"] = ""
                $saida[$p + "eleito"] = "0"
                continue
            }
            $saida[$p + "visivel"] = "1"
            $saida[$p + "nome"] = $nomeCand
            $saida[$p + "partido"] = Limitar-Texto $c.Partido $LimitePartido
            if ($Tarja.modelo -eq "presidente") {
                # O TSE nao manda imagem nos arquivos de resultado: a foto e
                # arquivo local, nomeado pelo numero do candidato. Entregamos
                # o caminho e dizemos se o arquivo existe, para a cena poder
                # esconder a moldura em vez de exibir um quadro quebrado.
                $arquivo = $PadraoFoto.Replace("{numero}", $c.Numero)
                $completo = $arquivo
                if ($PastaFotos) { $completo = Join-Path $PastaFotos (Split-Path -Leaf $arquivo) }
                $existe = "0"
                try { if (Test-Path $completo) { $existe = "1" } } catch { }
                if ($existe -eq "0" -and $FotoReserva) {
                    $reserva = $FotoReserva
                    if ($PastaFotos) { $reserva = Join-Path $PastaFotos (Split-Path -Leaf $FotoReserva) }
                    try { if (Test-Path $reserva) { $completo = $reserva } } catch { }
                }
                $saida[$p + "foto"] = $completo
                $saida[$p + "foto_existe"] = $existe
            }
            $saida[$p + "percentual"] = Formatar-Percentual $c.Percentual
            $saida[$p + "barra_px"] = $largura
            $saida[$p + "cor"] = Obter-Cor $c.Partido
            $saida[$p + "eleito"] = $c.Eleito
        }
    }
    return $saida
}

function Obter-NomeCargo {
    param([int] $Codigo)
    switch ($Codigo) {
        1  { return "PRESIDENTE" }
        3  { return "GOVERNADOR" }
        5  { return "SENADOR" }
        6  { return "DEPUTADO FEDERAL" }
        7  { return "DEPUTADO ESTADUAL" }
        8  { return "DEPUTADO DISTRITAL" }
        11 { return "PREFEITO" }
        13 { return "VEREADOR" }
        default { return "CARGO $Codigo" }
    }
}

# ------------------------------------------------------------------- rodizio

function Montar-Lista {
    # Uma lista de pracas num arquivo so, um registro por praca.
    # Serve tanto para o rodizio automatico quanto para o operador escolher
    # o estado na hora: trocar de estado = trocar de registro, sem trocar
    # de arquivo e sem refazer vinculo.
    param($Lista, $Boletins)
    $limite = 14
    if (Tem-Propriedade $Lista "limite_nome") { $limite = [int] $Lista.limite_nome }

    $pracas = @()
    $ordem = 0
    foreach ($p in $Lista.pracas) {
        $ordem++
        $b = $null
        if ($Boletins.ContainsKey($p.uf)) { $b = $Boletins[$p.uf] }

        $registro = [ordered]@{
            ordem = $ordem; visivel = "0"; praca = Limitar-Texto $p.nome 24
            cargo = Obter-NomeCargo $Lista.cargo
            apuracao_pct = ""; selo = ""
            cand1_nome = ""; cand1_partido = ""; cand1_percentual = ""; cand1_cor = ""
            cand2_nome = ""; cand2_partido = ""; cand2_percentual = ""; cand2_cor = ""
        }
        if ($null -ne $b) {
            $registro.visivel = "1"
            $registro.apuracao_pct = Formatar-Percentual $b.PctUrnas
            if (-not $b.Oficial) { $registro.selo = $SeloNaoOficial }
            for ($i = 1; $i -le 2; $i++) {
                if ($b.Candidatos.Count -ge $i) {
                    $c = $b.Candidatos[$i - 1]
                    $registro."cand${i}_nome" = Limitar-Texto $c.Nome $limite
                    $registro."cand${i}_partido" = Limitar-Texto $c.Partido $LimitePartido
                    $registro."cand${i}_percentual" = Formatar-Percentual $c.Percentual
                    $registro."cand${i}_cor" = Obter-Cor $c.Partido
                }
            }
        }
        $pracas += [pscustomobject] $registro
    }
    $comDado = @($pracas | Where-Object { $_.visivel -eq "1" }).Count
    return [ordered]@{ lista = $Lista.arquivo; total = $pracas.Count; com_dado = $comDado; pracas = $pracas }
}

# -------------------------------------------------------------------- painel

function Escrever-Painel {
    param($Linhas, [int] $Intervalo, [string] $Modo)
    $corpo = ""
    foreach ($l in $Linhas) {
        $classe = "ok"
        if ($l.Situacao -like "falha*") { $classe = "erro" }
        elseif ($l.Situacao -like "bloqueado*" -or $l.Situacao -like "sem*") { $classe = "aviso" }
        $corpo += "<tr class='$classe'><td class='n'>$($l.Tarja)</td><td>$($l.Praca)</td>" +
                  "<td class='num'>$($l.Urnas)</td><td>$($l.Primeiro)</td><td class='num'>$($l.Pct1)</td>" +
                  "<td>$($l.Segundo)</td><td class='num'>$($l.Pct2)</td>" +
                  "<td><span class='tag $classe'>$($l.Situacao)</span></td></tr>`n"
    }
    $faixa = ""
    if ($Modo -ne "AR") {
        $faixa = "<div class='faixa'>MODO $Modo - dados nao oficiais. Nao use no ar.</div>"
    }
    $html = @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="$Intervalo"><title>Painel de apuracao</title><style>
body{margin:0;background:#0d1420;color:#e6ecf6;font:14px/1.5 "Segoe UI",sans-serif}
.topo{padding:18px 26px;border-bottom:1px solid #243247;display:flex;gap:18px;align-items:baseline}
h1{margin:0;font-size:19px}.m{color:#93a3bb;font-size:13px;margin-left:auto}
.faixa{background:#4a3410;color:#f0c674;padding:9px 26px;font-weight:600;letter-spacing:.05em}
main{padding:22px 26px}table{width:100%;border-collapse:collapse;font-size:13.5px}
th{text-align:left;font-size:11px;letter-spacing:.09em;color:#93a3bb;text-transform:uppercase;
padding:0 12px 8px 0;border-bottom:1px solid #243247}
td{padding:9px 12px 9px 0;border-bottom:1px solid #243247}
tr.erro td{background:#2a1416}tr.aviso td{background:#2a2312}
.n{font-weight:600}.num{text-align:right;font-variant-numeric:tabular-nums}
.tag{padding:2px 9px;border-radius:3px;font-size:11.5px;font-weight:600}
.tag.ok{background:#13341f;color:#5fce93}.tag.aviso{background:#3a2f12;color:#f0c674}
.tag.erro{background:#3a1a1c;color:#ef8d8d}
</style></head><body>
<div class="topo"><h1>Painel de apuracao</h1>
<div class="m">modo <b>$Modo</b> &middot; atualizado <b>$(Get-Date -Format 'HH:mm:ss')</b>
&middot; recarrega a cada <b>${Intervalo}s</b></div></div>
$faixa
<main><table><thead><tr><th>Tarja</th><th>Praca</th><th class="num">Urnas</th>
<th>1o colocado</th><th class="num">%</th><th>2o colocado</th><th class="num">%</th>
<th>Situacao</th></tr></thead><tbody>
$corpo
</tbody></table></main></body></html>
"@
    Escrever-Arquivo (Join-Path $PastaSaida "painel.html") $html
}

# ------------------------------------------------------------------- selecao

$script:Impressoes = @{}       # arquivo -> hash do conteudo, para nao reescrever a toa
$Impressoes = $script:Impressoes
$script:CacheBoletins = @{}    # "uf-cargo" -> ultimo boletim bom
$script:VistosNesteCiclo = @{}
$script:Alertas = @{}          # "uf-cargo" -> @{ desde; pct }
$script:Impressao = @{}        # "uf-cargo" -> impressao do ultimo boletim visto
$script:RegressaoVista = @{}   # "uf-cargo" -> quantas vezes o numero menor insistiu
$script:Ciclo = 0

function Ler-Selecao {
    # A praca escolhida pelo operador, por cargo. Governador e senador tem
    # selecao independente: o operador pode estar mostrando governador de SP
    # e senador do PR ao mesmo tempo.
    param([int] $Cargo = 3)
    if (-not (Tem-Propriedade $cfg "selecao")) { return $null }

    $arq = $cfg.selecao.arquivo_selecao
    if ($Cargo -eq 5 -and (Tem-Propriedade $cfg.selecao "arquivo_selecao_senador")) {
        $alt = $cfg.selecao.arquivo_selecao_senador
        # se o arquivo do senador nao existe, segue o do governador
        if (Test-Path $alt) { $arq = $alt }
    }

    $uf = $cfg.selecao.padrao
    if (Test-Path $arq) {
        try {
            $lido = (Get-Content $arq -Raw -ErrorAction Stop).Trim().ToLower()
            if ($lido) { $uf = $lido }
        } catch { }
    }
    foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $uf) { return $p } }
    # UF que nao existe na lista: cair na primeira praca poe um estado
    # qualquer no ar sem ninguem pedir. Melhor voltar ao padrao configurado
    # e dizer em voz alta que o arquivo de selecao esta com lixo.
    if ($uf -ne $cfg.selecao.padrao) {
        Escrever-Log "selecao '$uf' nao existe na lista de pracas: usando o padrao '$($cfg.selecao.padrao)'" "AVISO"
        foreach ($p in $cfg.selecao.pracas) { if ($p.uf -eq $cfg.selecao.padrao) { return $p } }
    }
    return $cfg.selecao.pracas[0]
}

function Obter-Impressao-Boletim {
    # O que caracteriza "boletim novo": percentual de urnas e os votos dos
    # dois primeiros. Nao uso a hora de geracao do TSE porque ela muda a cada
    # republicacao, mesmo sem numero novo - o alerta perderia sentido.
    param($Boletim)
    if ($null -eq $Boletim) { return "" }
    $partes = @("$($Boletim.PctUrnas)")
    foreach ($i in 0, 1) {
        if ($Boletim.Candidatos.Count -gt $i) {
            $partes += "$($Boletim.Candidatos[$i].Numero):$($Boletim.Candidatos[$i].Votos)"
        }
    }
    return ($partes -join "|")
}

function Marcar-Alerta {
    # Acende o alerta daquela praca/cargo quando o numero mudou de verdade.
    param([string] $Uf, [int] $Cargo, $Boletim)
    $chave = "$Uf-$Cargo"
    $nova = Obter-Impressao-Boletim $Boletim
    if (-not $nova) { return }
    $anterior = $null
    if ($script:Impressao.ContainsKey($chave)) { $anterior = $script:Impressao[$chave] }
    $script:Impressao[$chave] = $nova
    if ($null -eq $anterior) { return }      # primeira leitura nao e "novidade"
    if ($anterior -eq $nova) { return }
    # Placar de mudancas: responde "o TSE esta mandando numero novo?" sem
    # depender de alguem ficar olhando a tarja e tentando notar diferenca.
    $script:MudancasTotal = $script:MudancasTotal + 1
    $script:UltimaMudanca = Get-Date
    $script:Alertas[$chave] = @{
        desde = (Get-Date -Format "HH:mm:ss")
        pct   = (Formatar-Percentual $Boletim.PctUrnas)
    }
}

function Limpar-Alerta {
    param([string] $Uf, [int] $Cargo)
    $chave = "$Uf-$Cargo"
    if ($script:Alertas.ContainsKey($chave)) { $script:Alertas.Remove($chave) }
}

function Expirar-Alertas {
    # Alerta velho polui a tela: depois de um tempo ele sai sozinho.
    $segundos = 900
    if ((Tem-Propriedade $cfg "alertas") -and (Tem-Propriedade $cfg.alertas "segundos_para_expirar")) {
        $segundos = [int] $cfg.alertas.segundos_para_expirar
    }
    if ($segundos -le 0) { return }
    $agora = Get-Date
    foreach ($chave in @($script:Alertas.Keys)) {
        try {
            $desde = [datetime]::ParseExact($script:Alertas[$chave].desde, "HH:mm:ss", $null)
            if (($agora - $desde).TotalSeconds -gt $segundos) { $script:Alertas.Remove($chave) }
        } catch { }
    }
}

function Escrever-Alertas {
    # Arquivo que o painel web le para acender os avisos nos botoes.
    if (-not (Tem-Propriedade $cfg "alertas")) { return }
    $estados = [ordered]@{}
    foreach ($p in $cfg.selecao.pracas) {
        $gov = $null; $sen = $null
        if ($script:Alertas.ContainsKey("$($p.uf)-3")) { $gov = $script:Alertas["$($p.uf)-3"] }
        if ($script:Alertas.ContainsKey("$($p.uf)-5")) { $sen = $script:Alertas["$($p.uf)-5"] }
        $estados[$p.uf] = [ordered]@{
            nome = $p.nome
            governador = $(if ($gov) { [ordered]@{ novo = $true; desde = $gov.desde; pct = $gov.pct } } else { $null })
            senador    = $(if ($sen) { [ordered]@{ novo = $true; desde = $sen.desde; pct = $sen.pct } } else { $null })
        }
    }
    $pres = $null
    if ($script:Alertas.ContainsKey("br-1")) {
        $a = $script:Alertas["br-1"]
        $pres = [ordered]@{ novo = $true; desde = $a.desde; pct = $a.pct }
    }
    $corpo = [ordered]@{
        atualizado_em = (Get-Date -Format "HH:mm:ss")
        ciclo = $script:Ciclo
        presidente = $pres
        estados = $estados
    }
    Escrever-Arquivo (Join-Path $PastaSaida $cfg.alertas.arquivo) ($corpo | ConvertTo-Json -Depth 6)
}

function Buscar-Praca {
    # Le uma praca/cargo do TSE (ou do simulador), guarda em cache e acende o
    # alerta se o numero mudou. Uma praca por ciclo, no maximo.
    param([string] $Uf, [int] $Cargo, [string] $Nome, [string] $Modo)
    $chave = "$Uf-$Cargo"
    if ($script:VistosNesteCiclo.ContainsKey($chave)) {
        if ($script:CacheBoletins.ContainsKey($chave)) { return $script:CacheBoletins[$chave] }
        return $null
    }
    $script:VistosNesteCiclo[$chave] = $true

    $b = $null
    if ($Ensaio) {
        $b = Gerar-Simulado $Uf $Cargo $Nome
    } else {
        $bruto = Obter-Boletim (Montar-Url $Uf $Cargo)
        if ($bruto -eq "SEM-MUDANCA") {
            if ($script:CacheBoletins.ContainsKey($chave)) { return $script:CacheBoletins[$chave] }
            return $null
        }
        if ($null -ne $bruto) { $b = Normalizar-Boletim $bruto $Nome }
    }
    if ($null -ne $b -and (-not $b.Oficial) -and $Modo -eq "AR") { return $null }

    # ANTI-REGRESSAO. O TSE serve de CDN com varios pontos de presenca, e um
    # deles pode devolver copia velha. No ar isso aparece como a apuracao
    # ANDANDO PARA TRAS - 80% virando 40% - que parece erro da emissora e e
    # editorialmente grave. Seguramos o numero que regride e mantemos o
    # ultimo bom.
    # Mas correcao de verdade existe: se o valor menor insistir em aparecer,
    # nao e copia velha, e o TSE corrigindo. Depois de 3 leituras iguais,
    # aceitamos - senao a tarja ficaria presa num numero que nao existe mais.
    if ($null -ne $b -and $script:CacheBoletins.ContainsKey($chave)) {
        $velho = $script:CacheBoletins[$chave]
        $votosNovos = 0
        $votosVelhos = 0
        foreach ($c in $b.Candidatos) { $votosNovos += $c.Votos }
        foreach ($c in $velho.Candidatos) { $votosVelhos += $c.Votos }
        $regrediu = ($b.PctUrnas -lt $velho.PctUrnas - 0.001) -or
                    ($votosNovos -lt $votosVelhos -and $velho.Candidatos.Count -gt 0)
        if ($regrediu) {
            $impressao = Obter-Impressao-Boletim $b
            if ($script:RegressaoVista.ContainsKey($chave) -and
                $script:RegressaoVista[$chave].impressao -eq $impressao) {
                $script:RegressaoVista[$chave].vezes = $script:RegressaoVista[$chave].vezes + 1
            } else {
                $script:RegressaoVista[$chave] = @{ impressao = $impressao; vezes = 1 }
            }
            $vezes = $script:RegressaoVista[$chave].vezes
            if ($vezes -lt 3) {
                Escrever-Log ("$chave regrediu de {0:N2}% para {1:N2}% das urnas: mantendo o ultimo bom ({2}a vez)" -f `
                    $velho.PctUrnas, $b.PctUrnas, $vezes) "AVISO"
                return $velho
            }
            Escrever-Log ("${chave}: numero menor confirmado {0} vezes, aceitando como correcao do TSE" -f $vezes) "AVISO"
        }
        $script:RegressaoVista.Remove($chave)
    }
    if ($null -ne $b) {
        Marcar-Alerta $Uf $Cargo $b
        $script:CacheBoletins[$chave] = $b
    }
    return $b
}

function Publicar-Selecionada {
    # Reescreve as tarjas do seletor a partir do cache. Nao consulta o TSE:
    # trocar de estado no ar tem que ser instantaneo.
    param($Cache)
    if (-not (Tem-Propriedade $cfg "selecao")) { return @() }
    $publicados = @()
    foreach ($saida in $cfg.selecao.saidas) {
        $praca = Ler-Selecao $saida.cargo
        if ($null -eq $praca) { continue }
        $chave = "$($praca.uf)-$($saida.cargo)"
        $b = $null
        if ($Cache.ContainsKey($chave)) { $b = $Cache[$chave] }
        if ($null -eq $b) {
            # Sem boletim para esta praca neste cargo. NAO pode deixar o
            # arquivo como estava: mostraria o estado ANTERIOR com o operador
            # achando que selecionou outro. Publica vazio, com o nome certo.
            $b = [pscustomobject]@{
                Fase = "O"; Oficial = $true; Praca = $praca.nome
                PctUrnas = 0.0; Geracao = ""; Candidatos = @()
            }
        } else {
            $b = $b.PSObject.Copy()
        }
        $b.Praca = $praca.nome
        $json = ($(Montar-Tarja $b $saida) | ConvertTo-Json -Depth 5)
        $hash = Obter-Hash $json
        if ($Impressoes[$saida.arquivo] -ne $hash) {
            Escrever-Arquivo (Join-Path $PastaSaida "$($saida.arquivo).json") $json
            $Impressoes[$saida.arquivo] = $hash
            $publicados += $saida.arquivo
        }
    }
    return $publicados
}

# --------------------------------------------------------------------- ciclo

function Executar-Ciclo {
    param([string] $Modo)
    $script:Ciclo++
    $script:VistosNesteCiclo = @{}
    $linhas = @()

    $ciclosVarredura = 3
    if (Tem-Propriedade $cfg "ciclos_varredura") { $ciclosVarredura = [math]::Max(1, [int] $cfg.ciclos_varredura) }
    # Varredura completa de vez em quando; o resto do tempo so o que esta no
    # ar. E o que permite cobrir 27 estados sem estourar o limite do TSE.
    $varredura = (($script:Ciclo - 1) % $ciclosVarredura) -eq 0

    # --- tarjas fixas (presidente) : todo ciclo
    foreach ($tarja in $cfg.tarjas) {
        $b = Buscar-Praca $tarja.abrangencia $tarja.cargo $tarja.praca $Modo
        $situacao = "sem dado"
        if ($null -ne $b) {
            $json = ($(Montar-Tarja $b $tarja) | ConvertTo-Json -Depth 5)
            $hash = Obter-Hash $json
            if ($Impressoes[$tarja.arquivo] -eq $hash) {
                $situacao = "sem mudanca"
            } else {
                Escrever-Arquivo (Join-Path $PastaSaida "$($tarja.arquivo).json") $json
                $Impressoes[$tarja.arquivo] = $hash
                $situacao = "publicado"
            }
            $p1 = ""; $q1 = ""; $p2 = ""; $q2 = ""
            if ($b.Candidatos.Count -ge 1) {
                $p1 = "$($b.Candidatos[0].Nome) ($($b.Candidatos[0].Partido))"
                $q1 = Formatar-Percentual $b.Candidatos[0].Percentual
            }
            if ($b.Candidatos.Count -ge 2) {
                $p2 = "$($b.Candidatos[1].Nome) ($($b.Candidatos[1].Partido))"
                $q2 = Formatar-Percentual $b.Candidatos[1].Percentual
            }
            $linhas += [pscustomobject]@{
                Tarja = $tarja.arquivo; Praca = $b.Praca
                Urnas = (Formatar-Percentual $b.PctUrnas)
                Primeiro = $p1; Pct1 = $q1; Segundo = $p2; Pct2 = $q2; Situacao = $situacao
            }
        } else {
            $linhas += [pscustomobject]@{
                Tarja = $tarja.arquivo; Praca = $tarja.praca; Urnas = ""
                Primeiro = ""; Pct1 = ""; Segundo = ""; Pct2 = ""; Situacao = $situacao
            }
        }
    }

    # --- pracas selecionadas : todo ciclo, para o que esta no ar ficar fresco
    if (Tem-Propriedade $cfg "selecao") {
        foreach ($saida in $cfg.selecao.saidas) {
            $praca = Ler-Selecao $saida.cargo
            if ($null -eq $praca) { continue }
            $null = Buscar-Praca $praca.uf $saida.cargo $praca.nome $Modo
        }
    }

    # --- varredura das demais pracas : a cada N ciclos
    if ($varredura -and (Tem-Propriedade $cfg "selecao")) {
        foreach ($p in $cfg.selecao.pracas) {
            foreach ($saida in $cfg.selecao.saidas) {
                $null = Buscar-Praca $p.uf $saida.cargo $p.nome $Modo
            }
        }
    }

    # --- escreve as tarjas do seletor
    if (Tem-Propriedade $cfg "selecao") {
        $null = Publicar-Selecionada $script:CacheBoletins
        foreach ($saida in $cfg.selecao.saidas) {
            $praca = Ler-Selecao $saida.cargo
            if ($null -eq $praca) { continue }
            # quem esta no ar nao precisa de alerta: o operador ja esta vendo
            Limpar-Alerta $praca.uf $saida.cargo
            $linhas += [pscustomobject]@{
                Tarja = $saida.arquivo; Praca = $praca.nome; Urnas = ""
                Primeiro = ""; Pct1 = ""; Segundo = ""; Pct2 = ""; Situacao = "no ar"
            }
        }
    }

    # --- listas de pracas
    if (Tem-Propriedade $cfg "listas") {
        foreach ($listaCfg in $cfg.listas) {
            $boletins = @{}
            foreach ($p in $listaCfg.pracas) {
                $chave = "$($p.uf)-$($listaCfg.cargo)"
                $bb = $null
                if ($script:CacheBoletins.ContainsKey($chave)) { $bb = $script:CacheBoletins[$chave] }
                if ($null -ne $bb) {
                    $bb = $bb.PSObject.Copy()
                    $bb.Praca = $p.nome
                    $boletins[$p.uf] = $bb
                }
            }
            $lista = Montar-Lista $listaCfg $boletins
            $json = ($lista | ConvertTo-Json -Depth 6)
            $hash = Obter-Hash $json
            if ($Impressoes[$listaCfg.arquivo] -ne $hash) {
                Escrever-Arquivo (Join-Path $PastaSaida "$($listaCfg.arquivo).json") $json
                $Impressoes[$listaCfg.arquivo] = $hash
            }
            $linhas += [pscustomobject]@{
                Tarja = $listaCfg.arquivo; Praca = "$($lista.com_dado) de $($lista.total) pracas"
                Urnas = ""; Primeiro = ""; Pct1 = ""; Segundo = ""; Pct2 = ""
                Situacao = $(if ($lista.com_dado -gt 0) { "publicado" } else { "sem dado" })
            }
        }
    }

    # o painel web pede baixa de alerta escrevendo no VISTO.txt
    if (Test-Path "VISTO.txt") {
        try {
            $pedidos = Get-Content "VISTO.txt" -ErrorAction Stop
            foreach ($linha in $pedidos) {
                $chave = $linha.Trim().ToLower()
                if ($chave -and $script:Alertas.ContainsKey($chave)) { $script:Alertas.Remove($chave) }
            }
            Remove-Item "VISTO.txt" -Force -ErrorAction SilentlyContinue
        } catch { }
    }

    Expirar-Alertas
    Escrever-Alertas
    Escrever-Painel $linhas ([int] $cfg.intervalo_segundos) $Modo
    return $linhas
}

# ---------------------------------------------------------------- validar

if ($Validar) {
    # Conferencia numero a numero: pega o boletim CRU do TSE e compara com o
    # que o sistema poe na tarja. Responde "o que esta na tela e o que o TSE
    # mandou?" por escrito, com o dado dos dois lados na mesma linha, em vez
    # de exigir que alguem confie.
    $linhasV = New-Object System.Collections.ArrayList
    function Diz {
        param([string] $Texto = "")
        [void] $linhasV.Add($Texto)
        Write-Host $Texto
    }
    $script:Falhas = 0
    function Confere {
        param([string] $Item, $Esperado, $Obtido)
        $igual = ("$Esperado" -eq "$Obtido")
        if (-not $igual) { $script:Falhas = $script:Falhas + 1 }
        $marca = "OK   "
        if (-not $igual) { $marca = "FALHA" }
        Diz ("   {0}  {1,-28} TSE: {2,-24} tarja: {3}" -f $marca, $Item, "$Esperado", "$Obtido")
    }

    if ($Teste) {
        if ((Tem-Propriedade $cfg.tse "pleito_simulado") -and $cfg.tse.pleito_simulado) {
            $cfg.tse.pleito = $cfg.tse.pleito_simulado
        }
        if ((Tem-Propriedade $cfg.tse "eleicao_simulado") -and $cfg.tse.eleicao_simulado) {
            $cfg.tse.eleicao = $cfg.tse.eleicao_simulado
        }
    }

    Diz "==========================================================="
    Diz " gctse $Versao - validacao contra o dado cru do TSE"
    Diz " $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')   modo: $(if ($Teste) { 'SIMULADO' } else { 'OFICIAL' })"
    Diz "==========================================================="

    $alvos = @()
    # A chave 'praca' precisa existir em todos: sob StrictMode, ler chave
    # ausente de hashtable e erro, nao valor vazio.
    $alvos += @{ abr = "br"; cargo = 1; rotulo = "PRESIDENTE - BRASIL"
                 arquivo = "tarja-presidente"; praca = "BRASIL" }
    if (Tem-Propriedade $cfg "selecao") {
        foreach ($saida in $cfg.selecao.saidas) {
            $praca = Ler-Selecao $saida.cargo
            if ($null -eq $praca) { continue }
            $alvos += @{ abr = $praca.uf; cargo = [int] $saida.cargo
                         rotulo = "$(Obter-NomeCargo ([int] $saida.cargo)) - $($praca.nome)"
                         arquivo = $saida.arquivo; praca = $praca.nome }
        }
    }

    foreach ($alvo in $alvos) {
        Diz ""
        Diz "-----------------------------------------------------------"
        Diz $alvo.rotulo
        $url = Montar-Url $alvo.abr $alvo.cargo
        Diz "   $url"
        $bruto = Obter-Boletim $url
        if ($bruto -eq "SEM-MUDANCA" -or $null -eq $bruto) {
            Diz "   NAO FOI POSSIVEL LER ESTE BOLETIM AGORA."
            continue
        }
        $nomePraca = $alvo.praca
        if (-not $nomePraca) { $nomePraca = "BRASIL" }
        $b = Normalizar-Boletim $bruto $nomePraca

        Diz ""
        Diz "   O QUE O TSE MANDOU, CRU:"
        Diz "      fase: $($b.Fase)   gerado: $($b.Geracao)   urnas: $($b.PctUrnas)%"
        $i = 0
        foreach ($c in $b.Candidatos) {
            $i = $i + 1
            if ($i -gt 4) { break }
            Diz ("      {0}o {1,-26} {2,-10} {3,12} votos   {4}%" -f $i, $c.Nome, $c.Partido, $c.Votos, $c.Percentual)
        }

        $caminho = Join-Path $PastaSaida "$($alvo.arquivo).json"
        if (-not (Test-Path $caminho)) {
            Diz ""
            Diz "   O arquivo $($alvo.arquivo).json ainda nao existe. Rode o TESTE/INICIAR antes."
            continue
        }
        $tarja = Get-Content $caminho -Raw -Encoding UTF8 | ConvertFrom-Json
        Diz ""
        Diz "   COMPARACAO COM O QUE ESTA NO ARQUIVO DA TARJA:"
        Confere "praca" $nomePraca $tarja.abrangencia
        Confere "% de urnas apuradas" (Formatar-Percentual $b.PctUrnas) $tarja.apuracao_pct
        for ($k = 1; $k -le 2; $k++) {
            if ($b.Candidatos.Count -ge $k) {
                $c = $b.Candidatos[$k - 1]
                Confere "${k}o nome" (Limitar-Texto $c.Nome $LimiteNome) $tarja."cand${k}_nome"
                Confere "${k}o partido" (Limitar-Texto $c.Partido $LimitePartido) $tarja."cand${k}_partido"
                Confere "${k}o percentual" (Formatar-Percentual $c.Percentual) $tarja."cand${k}_percentual"
                Confere "${k}o visivel" "1" $tarja."cand${k}_visivel"
            } else {
                Confere "${k}o visivel (sem candidato)" "0" $tarja."cand${k}_visivel"
            }
        }
        # A barra e a conta que mais assusta: aqui ela e refeita a mao.
        $trilho = 0
        foreach ($tj in $cfg.tarjas) {
            if ($tj.arquivo -eq $alvo.arquivo -and (Tem-Propriedade $tj "trilho_px")) {
                $trilho = [int] $tj.trilho_px
            }
        }
        if (-not $trilho -and (Tem-Propriedade $cfg "selecao")) {
            foreach ($sd in $cfg.selecao.saidas) {
                if ($sd.arquivo -eq $alvo.arquivo -and (Tem-Propriedade $sd "trilho_px")) {
                    $trilho = [int] $sd.trilho_px
                }
            }
        }
        if ($trilho -gt 0) {
            for ($k = 1; $k -le 2; $k++) {
                if ($b.Candidatos.Count -lt $k) { continue }
                $pc = $b.Candidatos[$k - 1].Percentual
                $esperada = [int] [math]::Round($trilho * $pc / 100.0)
                if ($pc -gt 0 -and $esperada -lt 6) { $esperada = 6 }
                Confere "${k}a barra ($pc% de ${trilho}px)" $esperada $tarja."cand${k}_barra_px"
            }
        }
    }

    Diz ""
    Diz "==========================================================="
    if ($script:Falhas -eq 0) {
        Diz " NENHUMA DIVERGENCIA. O que esta na tarja e o que o TSE mandou."
    } else {
        Diz " $($script:Falhas) DIVERGENCIA(S) ACIMA. Envie este arquivo para analise."
    }
    Diz " Observacao: se a coleta estiver rodando, um boletim novo pode ter"
    Diz " chegado entre a leitura desta conferencia e a gravacao da tarja."
    Diz " Nesse caso, rode de novo: divergencia de verdade se repete."
    Diz "==========================================================="

    $utf8v = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText((Join-Path (Get-Location) "VALIDACAO.txt"), ($linhasV -join "`r`n"), $utf8v)
    Write-Host ""
    Write-Host "  Gravado em VALIDACAO.txt, nesta mesma pasta." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- conferir

if ($Conferir) {
    # Diagnostico de um clique: responde "estamos recebendo dado do TSE?"
    # sem depender de ninguem saber ler log. Grava tudo em CONFERIR.txt para
    # o arquivo poder ser enviado inteiro a quem for analisar.
    $rel = New-Object System.Collections.ArrayList

    function Anotar {
        param([string] $Texto = "")
        [void] $rel.Add($Texto)
        Write-Host $Texto
    }

    function Sondar-Url {
        param([string] $Url, [string] $Rotulo, $Cabecalhos = $null)
        Anotar "--- $Rotulo"
        Anotar "    $Url"
        $t0 = Get-Date
        try {
            if ($Cabecalhos) {
                $r = Invoke-WebRequest -Uri $Url -Headers $Cabecalhos -TimeoutSec 25 -UseBasicParsing
            } else {
                $r = Invoke-WebRequest -Uri $Url -TimeoutSec 25 -UseBasicParsing
            }
            $ms = [int] ((Get-Date) - $t0).TotalMilliseconds
            $texto = Ler-Texto-Resposta $r
            Anotar "    RECEBIDO   HTTP $([int] $r.StatusCode)   $($texto.Length) caracteres   $ms ms"
            return $texto
        } catch {
            $ms = [int] ((Get-Date) - $t0).TotalMilliseconds
            $cod = "sem resposta do servidor"
            $corpo = ""
            $servidor = ""
            if ((Tem-Propriedade $_.Exception "Response") -and $_.Exception.Response) {
                try { $cod = "HTTP " + [int] $_.Exception.Response.StatusCode } catch { }
                # Quem respondeu e o que ele disse: um 403 de CDN costuma se
                # identificar no cabecalho Server e explicar no corpo. E a
                # diferenca entre "o TSE recusou" e "um intermediario barrou".
                try { $servidor = $_.Exception.Response.Headers["Server"] } catch { }
                try {
                    $fluxo = $_.Exception.Response.GetResponseStream()
                    $leitor = New-Object IO.StreamReader($fluxo, [Text.Encoding]::UTF8)
                    $corpo = $leitor.ReadToEnd()
                    $leitor.Close()
                } catch { }
            }
            if (-not $corpo) {
                try { $corpo = "$($_.ErrorDetails.Message)" } catch { }
            }
            Anotar "    NAO RECEBIDO   $cod   ($ms ms)"
            Anotar "    motivo: $($_.Exception.Message)"
            if ($servidor) { Anotar "    quem respondeu (Server): $servidor" }
            if ($corpo) {
                $limpo = ($corpo -replace '<[^>]+>', ' ') -replace '\s+', ' '
                $limpo = $limpo.Trim()
                if ($limpo.Length -gt 300) { $limpo = $limpo.Substring(0, 300) + "..." }
                if ($limpo) { Anotar "    o servidor explicou: $limpo" }
            }
            return $null
        }
    }

    function Recortar {
        param([string] $Texto, [int] $Maximo = 5000)
        if ($null -eq $Texto) { return "" }
        if ($Texto.Length -le $Maximo) { return $Texto }
        return $Texto.Substring(0, $Maximo) + "`r`n[... cortado, o arquivo tem $($Texto.Length) caracteres ...]"
    }

    Anotar "==========================================================="
    Anotar " gctse - conferencia de recebimento de dados do TSE"
    Anotar " $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    Anotar " maquina...: $env:COMPUTERNAME"
    Anotar " PowerShell: $($PSVersionTable.PSVersion)"
    Anotar " Windows...: $([Environment]::OSVersion.VersionString)"
    Anotar "==========================================================="
    Anotar ""
    Anotar "ETAPA 1 - a maquina alcanca o TSE?"
    Anotar ""

    # O endereco do simulado nao esta documentado de forma estavel, e o
    # ele-c.json do proprio TSE descreve os caminhos como
    # <base>/<ambiente>/<ciclo>/... - ou seja, "simulado" e um AMBIENTE, que
    # pode morar no mesmo host do oficial. Em vez de apostar num endereco,
    # testamos os candidatos e relatamos qual respondeu.
    $candidatos = New-Object System.Collections.ArrayList
    if ((Tem-Propriedade $cfg.tse "base_url_simulado") -and $cfg.tse.base_url_simulado) {
        [void] $candidatos.Add($cfg.tse.base_url_simulado)
    }
    foreach ($c in @("https://resultados-sim.tse.jus.br/simulado/simulado2026",
                     "https://resultados-sim.tse.jus.br/simulado",
                     "https://resultados.tse.jus.br/simulado",
                     "https://resultados-sim.tse.jus.br",
                     "https://resultados-sim.tse.jus.br/oficial",
                     "https://resultados-sim.tse.jus.br/simulado/ele2026",
                     "https://resultados.tse.jus.br/teste")) {
        if (-not $candidatos.Contains($c)) { [void] $candidatos.Add($c) }
    }

    $eleSim = $null
    $cfgSim = $null
    $n = 0
    foreach ($cand in $candidatos) {
        $n = $n + 1
        $resp = Sondar-Url "$($cand.TrimEnd('/'))/comum/config/ele-c.json" "SIMULADO - tentativa $n de $($candidatos.Count)"
        Anotar ""
        if ($resp) {
            $eleSim = $resp
            $cfgSim = $cand
            Anotar "    >>> ESTE E O ENDERECO DO SIMULADO: $cand"
            Anotar ""
            break
        }
    }

    # Se todo caminho deu 403 igual e rapido, a hipotese muda: nao e caminho
    # errado, e o host recusando este cliente. O teste que separa as duas
    # coisas e repetir com os mesmos cabecalhos que um navegador manda - se
    # passar, era o cliente; se der 403 de novo, o ambiente esta fechado e a
    # resposta esta com o TSE, nao aqui.
    if ($null -eq $eleSim) {
        Anotar "-----------------------------------------------------------"
        Anotar "Nenhum caminho passou. Repetindo com cabecalhos de navegador,"
        Anotar "para saber se o que incomoda e o caminho ou o cliente."
        Anotar "-----------------------------------------------------------"
        Anotar ""
        $cabNavegador = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
            "Accept" = "application/json,text/plain,*/*"
            "Accept-Language" = "pt-BR,pt;q=0.9"
        }
        $retentar = New-Object System.Collections.ArrayList
        if ((Tem-Propriedade $cfg.tse "base_url_simulado") -and $cfg.tse.base_url_simulado) {
            [void] $retentar.Add($cfg.tse.base_url_simulado)
        }
        foreach ($c in @("https://resultados-sim.tse.jus.br/simulado/simulado2026",
                         "https://resultados-sim.tse.jus.br/simulado")) {
            if (-not $retentar.Contains($c)) { [void] $retentar.Add($c) }
        }
        foreach ($cand in $retentar) {
            $resp = Sondar-Url "$($cand.TrimEnd('/'))/comum/config/ele-c.json" "SIMULADO com cabecalho de navegador" $cabNavegador
            Anotar ""
            if ($resp) {
                $eleSim = $resp
                $cfgSim = $cand
                Anotar "    >>> PASSOU COM CABECALHO DE NAVEGADOR."
                Anotar "    >>> Endereco do simulado: $cand"
                Anotar "    >>> Ponha no config.json, em tse.base_url_simulado."
                Anotar "    >>> E ponha tambem tse.user_agent com o valor de navegador."
                Anotar ""
                break
            }
        }
    }

    $appSim = $null
    if ($null -eq $eleSim) {
        # Nenhum caminho de arquivo respondeu. A pagina do simulado responder
        # separa dois problemas muito diferentes: host bloqueado na rede
        # (nada responde) x caminho dos arquivos diferente do que supus.
        $cabPagina = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
            "Accept" = "text/html,application/xhtml+xml,*/*"
            "Accept-Language" = "pt-BR,pt;q=0.9"
        }
        $appSim = Sondar-Url "https://resultados-sim.tse.jus.br/simulado/app/index.html" "PAGINA do simulado, como um navegador pediria" $cabPagina
        Anotar ""
    }

    $eleOfi = Sondar-Url "$($UrlOficial.TrimEnd('/'))/comum/config/ele-c.json" "OFICIAL (o da noite da apuracao)"
    Anotar ""

    if ($null -eq $eleSim -and $null -eq $eleOfi) {
        Anotar "RESULTADO: a maquina NAO esta recebendo dado nenhum do TSE."
        Anotar "Nenhum endereco respondeu. Isso e liberacao de rede, nao e o programa."
        Anotar "Peca a TI a liberacao de saida HTTPS (porta 443) para:"
        Anotar "    resultados.tse.jus.br"
        Anotar "    resultados-sim.tse.jus.br"
    } elseif ($null -eq $eleSim) {
        Anotar "RESULTADO: o OFICIAL responde, mas nenhum caminho de simulado respondeu."
        Anotar "Como o oficial passa, a REDE ESTA LIBERADA e o programa funciona."
        if ($appSim) {
            Anotar ""
            Anotar "A pagina do simulado respondeu como navegador, mas os JSON nao estao"
            Anotar "nos caminhos que tentei. Ou seja: o host existe e a rede alcanca,"
            Anotar "so o caminho dos arquivos e outro."
            Anotar ""
            Anotar "COMO DESCOBRIR O CAMINHO CERTO, em 2 minutos:"
            Anotar "  1. abra no Chrome:"
            Anotar "     https://resultados-sim.tse.jus.br/simulado/app/index.html"
            Anotar "  2. aperte F12 e clique na aba Network (ou Rede)"
            Anotar "  3. aperte F5 para recarregar a pagina"
            Anotar "  4. na lista, procure as linhas que terminam em .json"
            Anotar "  5. clique com o botao direito em uma e escolha Copy > Copy link address"
            Anotar "  6. me envie esse endereco - e o endereco de verdade do simulado"
        } else {
            Anotar "NEM A PAGINA DO SIMULADO RESPONDEU, nem como navegador."
            Anotar ""
            Anotar "Isso muda o diagnostico: o host recusa TUDO, inclusive a pagina"
            Anotar "que uma pessoa abriria no Chrome. Nao e caminho errado nem"
            Anotar "cabecalho: o ambiente de simulado esta fechado para esta rede."
            Anotar ""
            Anotar "O TESTE QUE FECHA A QUESTAO, em 10 segundos:"
            Anotar "  abra no Chrome desta mesma maquina:"
            Anotar "  https://resultados-sim.tse.jus.br/simulado/app/index.html"
            Anotar ""
            Anotar "  - se o Chrome tambem mostrar 403/Acesso negado, o ambiente"
            Anotar "    esta fechado e a resposta esta com o TSE. Abra chamado em"
            Anotar "    https://30308800.tse.jus.br/ com 'Resultados - Divulgacao'"
            Anotar "    na descricao, pedindo a URL do ambiente de simulado."
            Anotar "  - se o Chrome ABRIR a pagina normalmente, o bloqueio e so"
            Anotar "    para programas. Ai aperte F12, aba Network, F5, e me envie"
            Anotar "    o endereco de qualquer linha que termine em .json."
        }
        Anotar ""
        Anotar "Envie este arquivo para analise."
    } elseif ($null -eq $eleOfi) {
        Anotar "RESULTADO: o simulado responde (da para testar), mas o OFICIAL nao."
        Anotar "O teste roda, a noite da apuracao NAO. Peca resultados.tse.jus.br:443."
    } else {
        Anotar "RESULTADO: os dois ambientes respondem. A maquina esta recebendo dado do TSE."
    }

    Anotar ""
    Anotar "==========================================================="
    Anotar "ETAPA 2 - quais eleicoes o TSE esta publicando"
    Anotar "Daqui saem os codigos de pleito e de eleicao para o config.json."
    Anotar "==========================================================="

    $script:Achado = @{}

    function Resumir-EleC {
        # Le o ele-c.json e imprime a lista de pleitos em tabela, em vez de
        # despejar 20 mil caracteres que ninguem consegue ler numa tela de
        # operacao. Marca com >>> o que e de 2026.
        param([string] $Json, [string] $Rotulo)
        Anotar ""
        Anotar ">>> $Rotulo"
        try {
            $d = $Json | ConvertFrom-Json
        } catch {
            Anotar "    nao consegui abrir como JSON."
            return
        }
        if (Tem-Propriedade $d "c") { Anotar "    ciclo publicado neste arquivo: $($d.c)" }
        if (Tem-Propriedade $d "dg") { Anotar "    gerado em: $($d.dg) $(Obter-Campo $d @('hg') '')" }
        if (-not (Tem-Propriedade $d "pl")) {
            Anotar "    o arquivo nao traz a lista de pleitos (campo pl)."
            return
        }
        Anotar ""
        foreach ($pleito in $d.pl) {
            $cdPleito = Obter-Campo $pleito @("cd") "?"
            $dt = Obter-Campo $pleito @("dt") ""
            if (-not (Tem-Propriedade $pleito "e")) { continue }
            foreach ($eleicao in $pleito.e) {
                $cdEleicao = Obter-Campo $eleicao @("cd") "?"
                $nome = Decodificar-Entidades "$(Obter-Campo $eleicao @('nm') '')"
                $cargos = New-Object System.Collections.ArrayList
                if (Tem-Propriedade $eleicao "abr") {
                    foreach ($a in $eleicao.abr) {
                        if (-not (Tem-Propriedade $a "cp")) { continue }
                        foreach ($cargo in $a.cp) {
                            $rot = "$(Obter-Campo $cargo @('cd') '')=$(Decodificar-Entidades "$(Obter-Campo $cargo @('ds') '')")"
                            if (-not $cargos.Contains($rot)) { [void] $cargos.Add($rot) }
                        }
                    }
                }
                # Data de 2026 nao basta: a lista do TSE vem cheia de eleicao
                # suplementar de prefeito marcada com data de 2026. O que
                # identifica a eleicao geral sao os CARGOS - Presidente, ou
                # Governador e Senador juntos.
                $temPresidente = $false
                $temGovernador = $false
                $temSenador = $false
                foreach ($rot in $cargos) {
                    if ($rot -like "1=*") { $temPresidente = $true }
                    if ($rot -like "3=*") { $temGovernador = $true }
                    if ($rot -like "5=*") { $temSenador = $true }
                }
                $geral = $temPresidente -or $temGovernador -or $temSenador
                $marca = "    "
                if ($geral) {
                    $marca = ">>> "
                    if (-not $script:Achado.ContainsKey($Rotulo)) {
                        $script:Achado[$Rotulo] = @{
                            ciclo = "$(Obter-Campo $d @('c') '')"
                            pleito = "$cdPleito"
                            eleicao = "$cdEleicao"
                            cargos = @{}
                            nomes = New-Object System.Collections.ArrayList
                        }
                    }
                    $reg = $script:Achado[$Rotulo]
                    # Cada cargo aponta para a eleicao em que ele esta: o
                    # Presidente numa, Governador e Senador em outra.
                    foreach ($rot in $cargos) {
                        $num = ($rot -split "=")[0]
                        if (@("1","3","5") -contains $num) {
                            $reg.cargos[$num] = "$cdEleicao"
                        }
                    }
                    [void] $reg.nomes.Add("$cdEleicao = $nome")
                }
                Anotar ("    {0}pleito {1}  |  eleicao {2}  |  {3}" -f $marca, $cdPleito, $cdEleicao, $dt)
                Anotar ("        {0}" -f $nome)
                if ($cargos.Count -gt 0) {
                    Anotar ("        cargos: {0}" -f ($cargos -join "   "))
                }
                Anotar ""
            }
        }
        Anotar ""
        if ($script:Achado.ContainsKey($Rotulo)) {
            Anotar "    A linha marcada com >>> e a ELEICAO GERAL - a que interessa."
            Anotar "    PLEITO vai em 'pleito', ELEICAO vai em 'eleicao' no config.json."
        } else {
            Anotar "    NENHUMA ELEICAO GERAL nesta lista."
            Anotar "    So aparecem eleicoes municipais e suplementares. O TSE ainda"
            Anotar "    nao publicou a configuracao da eleicao geral neste ambiente."
            Anotar "    Nao adianta escolher um pleito daqui - nenhum tem Presidente,"
            Anotar "    Governador e Senador."
        }
    }

    if ($eleOfi) { Resumir-EleC $eleOfi "AMBIENTE OFICIAL" }
    if ($eleSim) { Resumir-EleC $eleSim "AMBIENTE DE SIMULADO ($cfgSim)" }

    $ofi = $null
    $sim = $null
    foreach ($k in $script:Achado.Keys) {
        if ($k -eq "AMBIENTE OFICIAL") { $ofi = $script:Achado[$k] } else { $sim = $script:Achado[$k] }
    }
    if ($ofi -or $sim) {
        Anotar "-----------------------------------------------------------"
        Anotar "COPIE ISTO PARA O config.json, dentro de `"tse`":"
        Anotar ""
        function Mapa-Json {
            param($Reg)
            if (-not $Reg) { return "{}" }
            $partes = New-Object System.Collections.ArrayList
            foreach ($c in @("1", "3", "5")) {
                if ($Reg.cargos.ContainsKey($c)) {
                    [void] $partes.Add("`"$c`": `"$($Reg.cargos[$c])`"")
                }
            }
            return "{ " + ($partes -join ", ") + " }"
        }

        $cicloAchado = "$($cfg.tse.ciclo)"
        if ($ofi -and $ofi.ciclo) { $cicloAchado = $ofi.ciclo }
        elseif ($sim -and $sim.ciclo) { $cicloAchado = $sim.ciclo }
        Anotar "      `"ciclo`": `"$cicloAchado`","
        if ($ofi) {
            Anotar "      `"pleito`": `"$($ofi.pleito)`","
            Anotar "      `"eleicao`": `"$($ofi.eleicao)`","
            Anotar "      `"eleicao_por_cargo`": $(Mapa-Json $ofi),"
        } else {
            Anotar "      `"pleito`": `"`",      <- o oficial ainda nao publicou 2026"
            Anotar "      `"eleicao`": `"`","
            Anotar "      `"eleicao_por_cargo`": {},"
        }
        if ($sim) {
            Anotar "      `"pleito_simulado`": `"$($sim.pleito)`","
            Anotar "      `"eleicao_simulado`": `"$($sim.eleicao)`","
            Anotar "      `"eleicao_por_cargo_simulado`": $(Mapa-Json $sim)"
        } else {
            Anotar "      `"pleito_simulado`": `"`",   <- o simulado nao respondeu"
            Anotar "      `"eleicao_simulado`": `"`","
            Anotar "      `"eleicao_por_cargo_simulado`": {}"
        }
        Anotar ""
        Anotar "1 = Presidente, 3 = Governador, 5 = Senador."
        Anotar "Os tres nao ficam na mesma eleicao: o TSE separa por esfera."
        foreach ($reg in @($ofi, $sim)) {
            if ($reg -and $reg.nomes.Count -gt 0) {
                foreach ($n in $reg.nomes) { Anotar "    $n" }
            }
        }
        Anotar "-----------------------------------------------------------"
    } else {
        Anotar ""
        Anotar "NAO ACHEI A ELEICAO GERAL em nenhum dos ambientes que responderam."
        Anotar "As listas acima so trazem eleicoes municipais e suplementares - "
        Anotar "nenhuma com os cargos de Presidente, Governador e Senador."
        Anotar ""
        Anotar "Isso nao e defeito da maquina nem do programa: e o TSE que ainda"
        Anotar "nao publicou a configuracao da eleicao geral neste endereco."
        Anotar "Deixe o config.json como esta e rode este teste de novo mais tarde."
    }

    # O arquivo inteiro fica gravado ao lado, sem corte, para analise.
    $utf8sb = New-Object System.Text.UTF8Encoding($true)
    if ($eleOfi) {
        [IO.File]::WriteAllText((Join-Path (Get-Location) "ele-c-OFICIAL.json"), $eleOfi, $utf8sb)
        Anotar ""
        Anotar "    O arquivo completo foi gravado em ele-c-OFICIAL.json."
    }
    if ($eleSim) {
        [IO.File]::WriteAllText((Join-Path (Get-Location) "ele-c-SIMULADO.json"), $eleSim, $utf8sb)
        Anotar "    O arquivo completo foi gravado em ele-c-SIMULADO.json."
    }
    if ($null -eq $cfgSim) { $cfgSim = $UrlOficial }

    Anotar ""
    Anotar "==========================================================="
    Anotar "ETAPA 3 - um boletim de verdade"
    Anotar "==========================================================="

    $pleitoTeste = $cfg.tse.pleito
    $eleicaoTeste = $cfg.tse.eleicao
    if ((Tem-Propriedade $cfg.tse "pleito_simulado") -and $cfg.tse.pleito_simulado) {
        $pleitoTeste = $cfg.tse.pleito_simulado
    }
    if ((Tem-Propriedade $cfg.tse "eleicao_simulado") -and $cfg.tse.eleicao_simulado) {
        $eleicaoTeste = $cfg.tse.eleicao_simulado
    }

    if ("$pleitoTeste" -eq "000" -or -not "$pleitoTeste" -or "$eleicaoTeste" -eq "000" -or -not "$eleicaoTeste") {
        Anotar ""
        Anotar "PULADA: os codigos ainda estao zerados no config.json."
        Anotar "Pegue os codigos na ETAPA 2 acima, preencha o config.json e rode de novo."
    } else {
        $cfg.tse.base_url = $cfgSim
        $cfg.tse.pleito = $pleitoTeste
        $cfg.tse.eleicao = $eleicaoTeste
        if (Tem-Propriedade $cfg.tse "eleicao_por_cargo_simulado") {
            $cfg.tse.eleicao_por_cargo = $cfg.tse.eleicao_por_cargo_simulado
        }
        $ufTeste = "sp"
        if ((Tem-Propriedade $cfg "selecao") -and $cfg.selecao.pracas) {
            $ufTeste = "$($cfg.selecao.pracas[0].uf)".ToLower()
        }
        # O caminho dos arquivos de resultado mudou de 2022 para 2026. Em vez
        # de supor um, testamos os moldes conhecidos com o cargo de
        # presidente e ficamos com o primeiro que entregar um boletim.
        $moldes = New-Object System.Collections.ArrayList
        if ((Tem-Propriedade $cfg.tse "padrao_url") -and $cfg.tse.padrao_url) {
            [void] $moldes.Add("$($cfg.tse.padrao_url)")
        }
        foreach ($m in @(
            "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-c{cargo4}-e{eleicao6}-u.json",
            "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-c{cargo4}-e{eleicao6}-r.json",
            "{base}/{ciclo}/{eleicao}/dados-simplificados/{dir}/{abr}-c{cargo4}-e{eleicao6}-r.json",
            "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-e{eleicao6}-ab.json",
            "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-e{eleicao6}-r.json",
            "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-c{cargo4}-e{eleicao6}-ab.json",
            "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-e{eleicao6}-e.json",
            "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-e{eleicao6}-u.json",
            "{base}/{ciclo}/{eleicao}/dados/{dir}/{abr}-c{cargo4}-e{eleicao6}-u.json",
            "{base}/{ciclo}/{pleito}/dados-simplificados/{dir}/{abr}-c{cargo4}-e{eleicao6}-r.json",
            "{base}/{ciclo}/{pleito}/dados/{dir}/{abr}-c{cargo4}-e{eleicao6}-r.json")) {
            if (-not $moldes.Contains($m)) { [void] $moldes.Add($m) }
        }

        Anotar ""
        Anotar "Procurando o caminho dos arquivos de resultado..."
        Anotar ""
        # Testa TODOS os moldes, nao para no primeiro que responde. Um
        # arquivo que existe nao e necessariamente o arquivo certo - o de
        # abrangencia responde 200 e nao traz candidato nenhum. E cada
        # rodada destas custa tempo de janela de teste, entao vale trazer
        # tudo de uma vez em vez de descobrir um por vez.
        $moldeBom = ""
        $i = 0
        foreach ($molde in $moldes) {
            $i = $i + 1
            $sondagem = Sondar-Url (Montar-Url "br" 1 $molde) "molde $i de $($moldes.Count)"
            if ($sondagem) {
                $temCand = $false
                try {
                    $j = $sondagem | ConvertFrom-Json
                    if ((Tem-Propriedade $j "cand") -and $j.cand -and $j.cand.Count -gt 0) { $temCand = $true }
                    # 2026 aninha os candidatos dentro de carg/agr/par - o
                    # teste raso dizia "sem candidatos" para o arquivo certo.
                    $b = Normalizar-Boletim $j "teste"
                    if ($b.Candidatos.Count -gt 0) { $temCand = $true }
                } catch { }
                if ($temCand) {
                    Anotar "    >>> TEM CANDIDATOS. Este e o molde certo."
                    if (-not $moldeBom) { $moldeBom = $molde }
                } else {
                    Anotar "    (responde, mas sem lista de candidatos - nao serve para a tarja)"
                }
                Anotar "    campos no topo: $(($sondagem | ConvertFrom-Json).PSObject.Properties.Name -join ', ')"
                Anotar "    conteudo:"
                Anotar (Recortar $sondagem 1200)
            }
            Anotar ""
        }
        if ($moldeBom) {
            Anotar "-----------------------------------------------------------"
            Anotar "Ponha no config.json, em tse.padrao_url:"
            Anotar "    $moldeBom"
            Anotar "-----------------------------------------------------------"
            Anotar ""
        }
        if (-not $moldeBom) {
            Anotar "NENHUM molde conhecido entregou boletim. O caminho mudou."
            Anotar "Me envie a URL de um arquivo .json de resultado que voce veja"
            Anotar "funcionando (pelo F12 do navegador, aba Network) e eu monto o molde."
            Anotar ""
        }

        $alvos = @(
            @{ abr = "br"; cargo = 1; rotulo = "PRESIDENTE - Brasil" },
            @{ abr = $ufTeste; cargo = 3; rotulo = "GOVERNADOR - $($ufTeste.ToUpper())" },
            @{ abr = $ufTeste; cargo = 5; rotulo = "SENADOR - $($ufTeste.ToUpper())" }
        )
        foreach ($alvo in $alvos) {
            if (-not $moldeBom) { break }
            Anotar ""
            $corpo = Sondar-Url (Montar-Url $alvo.abr $alvo.cargo $moldeBom) $alvo.rotulo
            if ($corpo) {
                try {
                    $b = $corpo | ConvertFrom-Json
                    $chaves = (($b.PSObject.Properties | ForEach-Object { $_.Name }) -join ", ")
                    Anotar "    campos no topo: $chaves"
                    if (Tem-Propriedade $b "f") { Anotar "    fase: $($b.f)   (S = simulado, O = oficial)" }
                    if (Tem-Propriedade $b "pst") { Anotar "    urnas apuradas: $($b.pst)%" }
                    if (Tem-Propriedade $b "cand") { Anotar "    candidatos no arquivo: $($b.cand.Count)" }
                } catch {
                    Anotar "    o conteudo veio, mas nao e um JSON que eu consiga abrir."
                }
                Anotar "    --- inicio do arquivo, para conferencia dos nomes de campo ---"
                Anotar (Recortar $corpo 2500)
            }
        }
    }

    Anotar ""
    Anotar "==========================================================="
    Anotar "Fim. Envie este arquivo inteiro para analise."
    Anotar "==========================================================="

    $utf8 = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText((Join-Path (Get-Location) "CONFERIR.txt"), ($rel -join "`r`n"), $utf8)
    Write-Host ""
    Write-Host "  Gravado em CONFERIR.txt, nesta mesma pasta." -ForegroundColor Green
    Write-Host "  Envie esse arquivo para analise." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- descobrir

if ($Descobrir) {
    $url = "$($cfg.tse.base_url.TrimEnd('/'))/comum/config/ele-c.json"
    Escrever-Log "consultando $url"
    try {
        $dados = Invoke-RestMethod -Uri $url -TimeoutSec 20 -UseBasicParsing
        Write-Host ""
        Write-Host "Pleitos publicados pelo TSE:" -ForegroundColor Green
        ($dados | ConvertTo-Json -Depth 6)
        Write-Host ""
        Write-Host "Copie o codigo do pleito de 2026 para 'pleito' e 'eleicao' no config.json."
    } catch {
        Escrever-Log "nao foi possivel consultar: $($_.Exception.Message)" "ERRO"
        Escrever-Log "se for erro de conexao, peca a TI a liberacao de resultados.tse.jus.br:443 E resultados-sim.tse.jus.br:443" "ERRO"
        exit 1
    }
    exit 0
}

# ------------------------------------------------------------------ execucao

if ($Preencher) { $Ensaio = $true; $UmaVez = $true; $DuracaoEnsaio = 0 }

$Modo = "AR"
if ($Ensaio) { $Modo = "ENSAIO" } elseif ($Teste) { $Modo = "TESTE" }

# Sem os codigos do pleito nao ha o que buscar: cada ciclo montaria 55 URLs
# invalidas, tomaria 55 respostas 404 e ainda assim gastaria o limite de
# requisicoes por minuto do TSE. Melhor parar na porta e dizer o porque.
if ($Modo -ne "ENSAIO") {
    $pleitoUso = "$($cfg.tse.pleito)"
    $eleicaoUso = "$($cfg.tse.eleicao)"
    if ($Teste) {
        if ((Tem-Propriedade $cfg.tse "pleito_simulado") -and $cfg.tse.pleito_simulado) {
            $pleitoUso = "$($cfg.tse.pleito_simulado)"
        }
        if ((Tem-Propriedade $cfg.tse "eleicao_simulado") -and $cfg.tse.eleicao_simulado) {
            $eleicaoUso = "$($cfg.tse.eleicao_simulado)"
        }
    }
    # O mapa por cargo tambem serve: se ele tem os codigos, ha o que buscar.
    $temMapa = $false
    $chaveMapa = "eleicao_por_cargo"
    if ($Teste -and (Tem-Propriedade $cfg.tse "eleicao_por_cargo_simulado")) {
        $chaveMapa = "eleicao_por_cargo_simulado"
    }
    if (Tem-Propriedade $cfg.tse $chaveMapa) {
        foreach ($prop in $cfg.tse.$chaveMapa.PSObject.Properties) {
            if ($prop.Value) { $temMapa = $true }
        }
    }
    $faltando = (-not $pleitoUso) -or ($pleitoUso -eq "000") -or
                ((-not $temMapa) -and ((-not $eleicaoUso) -or ($eleicaoUso -eq "000")))
    if ($faltando) {
        Write-Host ""
        if ($Teste) {
            Escrever-Log "Sem os codigos do SIMULADO no config.json." "ERRO"
            Write-Host "  Preencha 'pleito_simulado' e 'eleicao_simulado' no config.json."
        } else {
            Escrever-Log "Sem os codigos da eleicao no config.json." "ERRO"
            Write-Host "  Preencha 'pleito' e 'eleicao' no config.json."
        }
        Write-Host ""
        Write-Host "  Para descobrir os codigos: rode CONFERIR.bat."
        Write-Host ""
        Write-Host "  Se o CONFERIR disser que nao existe eleicao geral publicada,"
        Write-Host "  nao ha nada a fazer ainda: o TSE publica os codigos da eleicao"
        Write-Host "  geral perto da data. Ate la, use ENSAIO.bat para treinar a"
        Write-Host "  equipe e montar as cenas - ele nao depende do TSE."
        Write-Host ""
        exit 1
    }
}

$limiteReq = 80
if (Tem-Propriedade $cfg "limite_requisicoes_por_minuto") { $limiteReq = [int] $cfg.limite_requisicoes_por_minuto }
$intervalo = [int] $cfg.intervalo_segundos
$ciclosVar = 3
if (Tem-Propriedade $cfg "ciclos_varredura") { $ciclosVar = [math]::Max(1, [int] $cfg.ciclos_varredura) }

# Um ciclo comum le so o que esta no ar; a cada N ciclos varre todas as
# pracas. A media por minuto e o que interessa para o limite do TSE.
$noAr = 0
if (Tem-Propriedade $cfg "tarjas") { $noAr += $cfg.tarjas.Count }
if (Tem-Propriedade $cfg "selecao") { $noAr += $cfg.selecao.saidas.Count }
$naVarredura = Contar-Requisicoes-Por-Ciclo
$porMinuto = [math]::Round(
    (60.0 / ($ciclosVar * $intervalo)) * ((($ciclosVar - 1) * $noAr) + $naVarredura), 1)

Escrever-Log "gctse versao $Versao" "OK"
Escrever-Log "modo $Modo | saida em $PastaSaida | intervalo ${intervalo}s" "OK"
if ($Modo -ne "ENSAIO") { Escrever-Log "caminho: $(Montar-Url 'br' 1)" }
if (-not $Ensaio) {
    Escrever-Log "$noAr req por ciclo comum, $naVarredura na varredura (1 a cada $ciclosVar)"
    Escrever-Log "media de $porMinuto requisicoes por minuto (limite $limiteReq)"
    # Projecao acima do limite significa que o limitador vai estrangular a
    # coleta: as varreduras ficam raras e os alertas chegam atrasados. E
    # regulagem de config, nao defeito - mas precisa aparecer na partida.
    if ($porMinuto -gt $limiteReq) {
        Escrever-Log "o intervalo de ${intervalo}s pede mais requisicoes do que o limite permite." "AVISO"
        $sugerido = [int] [math]::Ceiling($intervalo * $porMinuto / [double] $limiteReq)
        Write-Host ""
        Write-Host "  A coleta vai ser freada pelo limitador e as varreduras ficarao raras."
        Write-Host "  Aumente 'intervalo_segundos' no config.json para ${sugerido} ou mais,"
        Write-Host "  ou aumente 'ciclos_varredura'."
        Write-Host ""
    }
    if ($porMinuto -gt $limiteReq) {
        $minimo = [math]::Ceiling(
            (60.0 / ($ciclosVar * $limiteReq)) * ((($ciclosVar - 1) * $noAr) + $naVarredura))
        Escrever-Log "ACIMA DO LIMITE. As requisicoes serao seguradas na fila." "AVISO"
        Escrever-Log "Para nao segurar: intervalo_segundos ${minimo}s+, ou ciclos_varredura maior." "AVISO"
    }
}
if ($Modo -ne "AR") {
    Escrever-Log "dados NAO OFICIAIS neste modo. Nao use no ar." "AVISO"
}

# Fotografa a selecao antes do primeiro ciclo: sem isto, a primeira olhada
# leria "mudou" e publicaria tarja vazia por cima do que estiver na pasta.
if (Tem-Propriedade $cfg "selecao") {
    $script:UltimaSelecao = (($cfg.selecao.saidas | ForEach-Object { (Ler-Selecao $_.cargo).uf }) -join ",")
}

do {
    $inicio = Get-Date
    try {
        $linhas = Executar-Ciclo $Modo
        $resumo = ($linhas | ForEach-Object { "$($_.Tarja)=$($_.Situacao)" }) -join "  "
        $naJanela = $script:Requisicoes.Count
        Escrever-Log "$resumo | req: $naJanela no ultimo minuto"

        # Primeiro ciclo sem nenhum boletim e quase sempre caminho errado, e
        # nao ausencia de dado. Sem este aviso o operador fica olhando tarja
        # vazia sem nada na tela explicando o que houve.
        if ($script:Ciclo -eq 1 -and $Modo -ne "ENSAIO") {
            if ($script:BoletinsOk -eq 0) {
                Escrever-Log "NENHUM boletim voltou do TSE neste primeiro ciclo." "ERRO"
                Write-Host ""
                Write-Host "  Isso quase nunca e falta de dado - e endereco errado."
                Write-Host "  Rode CONFERIR.bat: ele testa os caminhos e diz qual funciona."
                Write-Host ""
                Write-Host "  Buscando em:"
                Write-Host "    $(Montar-Url 'br' 1)"
                Write-Host ""
            }
        }

        # Batida do coracao. O painel usa a IDADE deste arquivo para saber se
        # a coleta continua viva: so e gravado quando o ciclo fecha inteiro.
        # Ciclo que estoura nao bate - e o painel acusa em poucos segundos,
        # antes que os numeros congelados do GC virem erro no ar.
        $batida = [ordered]@{
            atualizado_em = (Get-Date -Format "dd/MM/yyyy HH:mm:ss")
            ciclo = $script:Ciclo
            modo = $Modo
            intervalo_segundos = [int] $cfg.intervalo_segundos
            requisicoes_no_minuto = $naJanela
            tarjas = $resumo
            mudancas_total = $script:MudancasTotal
            ultima_mudanca = $(if ($script:UltimaMudanca) { $script:UltimaMudanca.ToString("HH:mm:ss") } else { "" })
            segundos_sem_mudanca = $(if ($script:UltimaMudanca) { [int] ((Get-Date) - $script:UltimaMudanca).TotalSeconds } else { -1 })
        }
        Escrever-Arquivo (Join-Path $PastaSaida "coleta.json") ($batida | ConvertTo-Json -Depth 4)
    } catch {
        Escrever-Log "erro no ciclo: $($_.Exception.Message)" "ERRO"
    }
    if ($UmaVez) { break }

    # Espera do proximo ciclo vigiando a selecao: se o operador trocar de
    # estado, a tarja acompanha em ~1s em vez de esperar o ciclo inteiro.
    $gasto = ((Get-Date) - $inicio).TotalSeconds
    $espera = [math]::Max(1, [int] $cfg.intervalo_segundos - $gasto)
    for ($s = 0; $s -lt $espera; $s++) {
        Start-Sleep -Seconds 1
        $null = Atender-Troca-De-Praca
    }
} while ($true)
