<#
    gctse - Apuracao do TSE para o gerador de caracteres
    ------------------------------------------------------------------
    Roda direto no Windows. Nao instala nada, nao precisa de Python e nao
    precisa de internet alem do proprio TSE.

    Escrito para Windows PowerShell 5.1 (o que ja vem no Windows), sem
    recursos de versoes mais novas.

        .\gctse.ps1 -Descobrir    mostra os codigos do pleito
        .\gctse.ps1 -Conferir     testa a conexao e grava CONFERIR.txt
        .\gctse.ps1 -Validar      confere numero por numero contra o TSE
        .\gctse.ps1 -Fotos        lista os nomes de arquivo de foto aceitos
        .\gctse.ps1 -Campos       mostra as colunas dos arquivos, numeradas
        .\gctse.ps1 -Modelos      regrava as tarjas VAZIAS, para montar a cena
        .\gctse.ps1 -Diagnostico  valida TUDO de uma vez e grava DIAGNOSTICO.txt
        .\gctse.ps1 -Teste        aceita o simulado do TSE (fase S)
        .\gctse.ps1               no ar: so boletim oficial
#>

[CmdletBinding()]
param(
    [switch] $Descobrir,
    [switch] $Conferir,
    [switch] $Validar,
    [switch] $Fotos,
    [switch] $Campos,
    [switch] $Modelos,
    [switch] $Diagnostico,
    [switch] $Teste,
    [switch] $UmaVez,
    [string] $Config = "config.json"
)

# Versao impressa na partida e no painel. Sem carimbo, "qual versao esta
# rodando ai?" so se responde abrindo arquivo e comparando a olho - e no
# meio de um teste com janela de horario ninguem faz isso.
$Versao = "5.7 - 24/09/2026"

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# TLS 1.2: o Windows PowerShell 5.1 ainda negocia TLS 1.0 por padrao em
# maquina antiga, e o TSE recusa. Sem esta linha a coleta falha sem explicar.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# LIMITE DE CONEXOES. O .NET Framework, que e o que o Windows PowerShell 5.1
# usa, abre no maximo DUAS conexoes simultaneas por servidor. Uma resposta
# que nao e fechada prende uma delas; com duas presas, toda requisicao
# seguinte ao TSE fica esperando conexao ate estourar o tempo - e a coleta
# para sem dizer nada. O PowerShell 7 nao tem esse limite, e por isso isto
# passava nos testes e travava na maquina do GC. Subir o teto e a segunda
# linha de defesa; a primeira e fechar toda resposta (Fechar-Resposta).
try { [Net.ServicePointManager]::DefaultConnectionLimit = 64 } catch { }

# Barra de progresso do Invoke-WebRequest: no Windows PowerShell 5.1 ela
# e desenhada a cada pedaco recebido e deixa o download varias vezes mais
# lento. Numa coleta que faz 55 requisicoes por ciclo, isso e tempo de ar.
$ProgressPreference = "SilentlyContinue"

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
        Add-Content -Path (Join-Path "logs" ("gctse-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))) -Value $linha
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
    # O LiveBoard le este arquivo a cada 2 ou 3 segundos. No Windows, um
    # leitor que abra sem compartilhar escrita faz o Move-Item falhar - e
    # sem esta protecao a excecao subia e derrubava a COLETA INTEIRA por
    # causa de uma colisao de milissegundos. Tenta de novo algumas vezes;
    # se ainda assim nao der, perde-se esta gravacao e nao a noite: o
    # proximo ciclo reescreve, porque a impressao so e guardada em caso
    # de sucesso.
    $tentativas = 0
    while ($true) {
        $tentativas++
        try {
            Move-Item -Path $temporario -Destination $Caminho -Force -ErrorAction Stop
            return $true
        } catch {
            if ($tentativas -ge 4) {
                Escrever-Log "nao consegui gravar $Caminho : $($_.Exception.Message)" "AVISO"
                try { Remove-Item -Path $temporario -Force -ErrorAction SilentlyContinue } catch { }
                # Falso, e nao excecao: perder ESTA gravacao nao pode levar
                # junto o resto do ciclo (as outras tarjas, as listas, os
                # alertas). Quem chama nao guarda a impressao, entao o
                # proximo ciclo tenta de novo sozinho.
                return $false
            }
            Start-Sleep -Milliseconds (60 * $tentativas)
        }
    }
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
$CorPadrao = $cfg.texto.cor_padrao
$RotuloEleito = "ELEITO"
if (Tem-Propriedade $cfg.texto "rotulo_eleito") { $RotuloEleito = "$($cfg.texto.rotulo_eleito)" }
$PastaFotos = ""
if (Tem-Propriedade $cfg.texto "pasta_fotos") { $PastaFotos = "$($cfg.texto.pasta_fotos)" }
if ($PastaFotos -and -not [IO.Path]::IsPathRooted($PastaFotos)) {
    $PastaFotos = Join-Path (Get-Location) $PastaFotos
}
$FotoReserva = ""
if (Tem-Propriedade $cfg.texto "foto_reserva") { $FotoReserva = "$($cfg.texto.foto_reserva)" }
$FotosDoTse = $false
if (Tem-Propriedade $cfg.texto "fotos_do_tse") { $FotosDoTse = [bool] $cfg.texto.fotos_do_tse }
$FotoNomeFixo = $false
if (Tem-Propriedade $cfg.texto "foto_nome_fixo") { $FotoNomeFixo = [bool] $cfg.texto.foto_nome_fixo }

# ------------------------------------------------ ordem travada das colunas
#
# O Castalia vincula por POSICAO da coluna, nao pelo nome. Um campo que entre
# no meio empurra todos os seguintes e a tarja vai ao ar com o nome do estado
# no lugar do nome do candidato. Ja aconteceu duas vezes.
#
# Por isso a ordem nao e mais um efeito do codigo que monta a tarja: e esta
# lista. Montar-Tarja termina reordenando a saida por ela. Quem editar a
# funcao pode inserir campo onde quiser - a saida continua saindo nesta
# ordem. Campo que nao esteja na lista vai para o FIM e grita no log.
#
# As 19 primeiras sao iguais nos tres modelos, de proposito: uma cena
# montada para governador funciona no senador e no presidente.
#
# REGRA: campo novo entra SEMPRE no fim da lista do modelo. Nunca no meio.
# Mexer aqui = remontar a cena no Castalia.

$OrdemBase = @(
    "cargo", "abrangencia", "apuracao_pct", "selo", "hora_atualizacao",
    "cand1_visivel", "cand1_nome", "cand1_partido", "cand1_percentual",
    "cand1_barra_px", "cand1_cor", "cand1_eleito",
    "cand2_visivel", "cand2_nome", "cand2_partido", "cand2_percentual",
    "cand2_barra_px", "cand2_cor", "cand2_eleito"
)
$OrdemMajoritaria = $OrdemBase + @("cand1_eleito_rotulo", "cand2_eleito_rotulo",
                                   "cand1_situacao", "cand2_situacao",
                                   "apuracao_encerrada")
$OrdemPresidente  = $OrdemBase + @(
    "cand1_foto", "cand1_foto_existe", "cand1_foto_fixa", "cand1_eleito_rotulo",
    "cand2_foto", "cand2_foto_existe", "cand2_foto_fixa", "cand2_eleito_rotulo",
    "cand1_situacao", "cand2_situacao", "apuracao_encerrada"
)

function Ordem-Do-Modelo {
    param([string] $Modelo)
    if ($Modelo -eq "presidente") { return $OrdemPresidente }
    return $OrdemMajoritaria
}

$script:OrdemJaAvisada = @{}

function Ordenar-Tarja {
    # Devolve a tarja na ordem travada. Campo previsto que faltar entra vazio
    # (posicao vazia nao desloca nada; posicao ausente desloca TUDO). Campo
    # nao previsto vai para o fim, onde nao empurra ninguem, e o log avisa.
    param($Tarja, [string] $Modelo, [string] $Arquivo)
    $ordem = Ordem-Do-Modelo $Modelo
    $final = [ordered]@{}
    foreach ($chave in $ordem) {
        if ($Tarja.Contains($chave)) { $final[$chave] = $Tarja[$chave] }
        else { $final[$chave] = "" }
    }
    $sobra = @()
    foreach ($chave in $Tarja.Keys) {
        if ($final.Contains($chave)) { continue }
        $final[$chave] = $Tarja[$chave]
        $sobra += $chave
    }
    if ($sobra.Count -gt 0 -and -not $script:OrdemJaAvisada.ContainsKey($Arquivo)) {
        $script:OrdemJaAvisada[$Arquivo] = $true
        Escrever-Log ("$Arquivo tem campo fora da ordem travada: " + ($sobra -join ", ") +
                      ". Foi para o fim do arquivo para nao deslocar as colunas da cena. " +
                      "Inclua na lista de ordem antes de usar no ar.") "ERRO"
    }
    return $final
}

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
$script:UltimaCongelado = $false
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
    # Descongelar tambem e uma troca. Sem isto, sair do congelamento so
    # entrava no ar no ciclo seguinte - ate 20 segundos com o numero velho
    # na tela depois de alguem ter mandado liberar. Ao vivo, 20 segundos e
    # muito tempo.
    $congelado = Tarjas-Congeladas
    $descongelou = ($script:UltimaCongelado -eq $true) -and (-not $congelado)
    $script:UltimaCongelado = $congelado
    if ($agora -eq $script:UltimaSelecao -and -not $descongelou) { return $false }
    $script:UltimaSelecao = $agora
    # Estado escolhido que ainda nao esta no cache (troca no meio da
    # primeira varredura, por exemplo): busca AGORA, uma leitura so, antes de
    # gravar. Sem isto ia ao ar a tarja VAZIA, "0,00%", ate a varredura
    # chegar nesse estado - visto na 5.7, dois segundos de tarja em branco
    # no ar. Perto do limite de requisicoes nao busca: a troca nao pode
    # ficar esperando a fila; publica vazio e a varredura completa depois.
    if (-not (Tarjas-Congeladas)) {
        $limiteT = 80
        if (Tem-Propriedade $cfg "limite_requisicoes_por_minuto") { $limiteT = [int] $cfg.limite_requisicoes_por_minuto }
        foreach ($saida in $cfg.selecao.saidas) {
            $praca = Ler-Selecao $saida.cargo
            if ($null -eq $praca) { continue }
            if ($script:CacheBoletins.ContainsKey("$($praca.uf)-$($saida.cargo)")) { continue }
            if ($script:Requisicoes.Count -ge ($limiteT - 5)) { continue }
            $null = Buscar-Praca $praca.uf $saida.cargo $praca.nome $script:Modo
        }
    }
    $null = Publicar-Selecionada $script:CacheBoletins
    foreach ($saida in $cfg.selecao.saidas) {
        $praca = Ler-Selecao $saida.cargo
        if ($null -ne $praca) { Limpar-Alerta $praca.uf $saida.cargo }
    }
    Escrever-Alertas
    if ($descongelou) { Escrever-Log "descongelado: $agora entra no ar agora" "OK" }
    else { Escrever-Log "selecao trocada: $agora" "OK" }
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

$script:Ausentes = @{}   # url -> @{ vezes; pularAte } : recuo depois de 404

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

function Obter-Boletim {
    # RECUO DEPOIS DE 404. O TSE avisa que requisicao para endereco que nao
    # existe pode gerar bloqueio do IP. E no comeco da noite isso acontece
    # sozinho, sem ninguem errar nada: o estado ainda nao publicou boletim,
    # o arquivo ainda nao existe, e a varredura pede de novo a cada volta -
    # 54 respostas 404 por varredura, hora apos hora.
    #
    # Entao quem responde 404 entra em recuo: e pedido de novo depois de 1,
    # 2, 4, 8 ciclos, ate o teto. Qualquer resposta que nao seja 404 zera a
    # conta. A praca que esta NO AR tem teto curto, porque nela a demora
    # aparece na tela; as outras tem teto longo, porque nelas nao aparece.
    param([string] $Url, [switch] $Prioritario)

    if ($script:Ausentes.ContainsKey($Url)) {
        $reg = $script:Ausentes[$Url]
        if ($script:Ciclo -lt $reg.pularAte) { return $null }
    }

    Aguardar-Vez
    # Configuravel porque CDN de governo as vezes recusa cliente que nao se
    # parece com navegador, e trocar isso no ar nao pode depender de recompilar.
    $ua = "gctse/1.0"
    if ((Tem-Propriedade $cfg.tse "user_agent") -and $cfg.tse.user_agent) { $ua = "$($cfg.tse.user_agent)" }
    $cabecalhos = @{ "User-Agent" = $ua; "Accept" = "application/json,text/plain,*/*" }
    if ($Cache.ContainsKey($Url) -and "$($Cache[$Url])") { $cabecalhos["If-None-Match"] = "$($Cache[$Url])" }
    $relogio = [Diagnostics.Stopwatch]::StartNew()
    try {
        $resposta = Invoke-WebRequest -Uri $Url -Headers $cabecalhos -TimeoutSec 15 -UseBasicParsing
        $relogio.Stop()
    } catch {
        $relogio.Stop()
        $codigo = 0
        try { $codigo = [int] $_.Exception.Response.StatusCode } catch { }
        Fechar-Resposta $_
        if ($relogio.Elapsed.TotalSeconds -ge 5) {
            Escrever-Log ("TSE LENTO: {0:N1}s sem resposta em {1}" -f $relogio.Elapsed.TotalSeconds, $Url) "AVISO"
        }
        if ($codigo -eq 304) {
            if ($script:Ausentes.ContainsKey($Url)) { $script:Ausentes.Remove($Url) }
            return "SEM-MUDANCA"
        }
        if ($codigo -eq 404) {
            # Ainda nao publicado. Anota e espera mais da proxima vez.
            $vezes = 1
            if ($script:Ausentes.ContainsKey($Url)) { $vezes = $script:Ausentes[$Url].vezes + 1 }
            $teto = 10
            if ($Prioritario) { $teto = 2 }
            $espera = [math]::Min([math]::Pow(2, $vezes - 1), $teto)
            $script:Ausentes[$Url] = @{ vezes = $vezes; pularAte = $script:Ciclo + [int] $espera }
            return $null
        }
        Escrever-Log "falha em $Url : $($_.Exception.Message)" "AVISO"
        return $null
    }
    # Resposta que demora e o primeiro sinal de CDN sob carga - ou de
    # conexao presa. Silenciosa, vira "a tarja nao atualiza" sem pista.
    if ($relogio.Elapsed.TotalSeconds -ge 5) {
        Escrever-Log ("TSE LENTO: {0:N1}s para responder {1}" -f $relogio.Elapsed.TotalSeconds, $Url) "AVISO"
    }
    # Respondeu: sai do recuo.
    if ($script:Ausentes.ContainsKey($Url)) { $script:Ausentes.Remove($Url) }
    # ETag como TEXTO, sempre. O Windows PowerShell 5.1 devolve o cabecalho
    # como texto; o PowerShell 7 devolve como LISTA - e uma lista posta de
    # volta no If-None-Match invalida o pedido antes de ele sair, de modo que
    # do segundo ciclo em diante nenhuma requisicao chegava mais ao TSE e a
    # tarja parava no primeiro numero. Isso so apareceu quando o servidor de
    # teste passou a mandar ETag como o CDN do TSE manda.
    try {
        $etag = $resposta.Headers["ETag"]
        if ($etag -is [array]) { $etag = $etag | Select-Object -First 1 }
        if ($etag) { $Cache[$Url] = "$etag" } elseif ($Cache.ContainsKey($Url)) { $Cache.Remove($Url) }
    } catch { }
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
    # dvt = destinacao dos votos. Nos dados reais do simulado aparecem
    # "Valido", "Anulado" e "Anulado sub judice" - e um candidato ANULADO
    # pode estar entre os dois primeiros, com voto e percentual normais.
    # O TSE publica assim e nos repassamos assim; mas quem esta no ar
    # precisa poder saber, entao a situacao vai junto.
    $situacao = Decodificar-Entidades "$(Obter-Campo $C @('dvt') '')"
    return [pscustomobject]@{
        Numero     = "$(Obter-Campo $C @('n') '')"
        # O TSE publica a foto de cada candidato em fotos/<uf>/<sqcand>.jpeg.
        # Sem guardar este numero, a foto so poderia vir de arquivo que
        # alguem baixou e nomeou na mao.
        Sequencial = "$(Obter-Campo $C @('sqcand') '')"
        Nome       = "$(Obter-Campo $C @('nmu','nm','nmurna') '')"
        Partido    = "$partido"
        Votos      = $votos
        Percentual = $perc
        Eleito     = $eleito
        Situacao   = "$situacao"
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
        # "and" = andamento. "f" significa totalizacao FINAL daquela
        # abrangencia; "p" e parcial. O FAQ do TSE detalha a regra por
        # cargo. E diferente de 100% das urnas: o percentual pode chegar a
        # 100 antes de a totalizacao fechar, e e so com and=f que o
        # resultado daquela praca esta encerrado de verdade.
        Encerrada   = $(if ("$(Obter-Campo $Bruto @('and') '')".ToLower() -eq "f") { "1" } else { "0" })
        Oficial     = ($fase -eq "O")
        Praca       = $nome
        PctUrnas    = $pct
        Geracao     = "$(Obter-Campo $Bruto @('dg') '') $(Obter-Campo $Bruto @('hg') '')"
        Candidatos  = $candidatos
    }
}

# --------------------------------------------------------------- montar tarja

$ExtensoesFoto = @(".png", ".jpg", ".jpeg", ".webp", ".bmp")

function Nome-Para-Arquivo {
    # "JOAO DA SILVA CONCEICAO" -> "joao-da-silva-conceicao"
    # Tira acento, poe minuscula e troca o que nao e letra ou numero por
    # hifen, para o nome do arquivo nao depender de como o teclado escreve.
    param([string] $Texto)
    if (-not $Texto) { return "" }
    $semAcento = ($Texto.Normalize([Text.NormalizationForm]::FormD).ToCharArray() |
        Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne
                       [Globalization.UnicodeCategory]::NonSpacingMark }) -join ""
    $limpo = $semAcento.ToLower() -replace '[^a-z0-9]+', '-'
    return $limpo.Trim('-')
}

function Nomes-De-Foto-Aceitos {
    # Todos os nomes de arquivo que servem para um candidato, na ordem em que
    # sao procurados. O NUMERO vem primeiro porque e o que nao muda: nome de
    # urna o TSE pode reescrever entre o simulado e o oficial, e acento e
    # abreviacao variam. O nome existe porque quem organiza a pasta pensa em
    # pessoa, nao em numero.
    param([string] $Numero, [string] $Nome)
    $nomes = New-Object System.Collections.ArrayList
    if ($Numero) {
        foreach ($e in $ExtensoesFoto) { [void] $nomes.Add("$Numero$e") }
    }
    $slug = Nome-Para-Arquivo $Nome
    if ($slug) {
        foreach ($e in $ExtensoesFoto) { [void] $nomes.Add("$slug$e") }
        # primeiro nome sozinho: "LULA" de "LULA", "MARINA" de "MARINA SILVA"
        $primeiro = ($slug -split '-')[0]
        if ($primeiro -and $primeiro -ne $slug -and $primeiro.Length -ge 3) {
            foreach ($e in $ExtensoesFoto) { [void] $nomes.Add("$primeiro$e") }
        }
    }
    return $nomes
}

$script:FotosTseTentadas = @{}

function Baixar-Foto-Do-TSE {
    # O TSE publica a foto em [ambiente]/[ciclo]/[eleicao]/fotos/[uf]/<sqcand>.jpeg
    # (documento "Instrucoes para download dos arquivos", versao 1.0).
    #
    # UMA tentativa por candidato, por execucao. Se der 404, nunca mais se
    # pede: o proprio TSE avisa que multiplos 404 podem bloquear o IP, e
    # foto que falta nao justifica esse risco - a silhueta resolve.
    param([string] $Sequencial, [string] $Abrangencia, [int] $Cargo)
    if (-not $Sequencial) { return "" }
    if ($script:FotosTseTentadas.ContainsKey($Sequencial)) {
        return $script:FotosTseTentadas[$Sequencial]
    }

    $pasta = $PastaFotos
    if (-not $pasta) { $pasta = "FOTOS" }
    $destino = Join-Path $pasta "tse-$Sequencial.jpeg"
    if (Test-Path $destino) {
        $script:FotosTseTentadas[$Sequencial] = $destino
        return $destino
    }

    $molde = "{base}/{ciclo}/{eleicao}/fotos/{dir}/{sqcand}.jpeg"
    if ((Tem-Propriedade $cfg.tse "padrao_url_foto") -and $cfg.tse.padrao_url_foto) {
        $molde = "$($cfg.tse.padrao_url_foto)"
    }
    $dir = $Abrangencia
    if ($dir.Length -gt 2) { $dir = $dir.Substring(0, 2) }
    $url = $molde.Replace("{base}", $cfg.tse.base_url.TrimEnd('/'))
    $url = $url.Replace("{ciclo}", "$($cfg.tse.ciclo)")
    $url = $url.Replace("{eleicao}", "$(Obter-Eleicao $Cargo)")
    $url = $url.Replace("{dir}", $dir).Replace("{sqcand}", $Sequencial)

    $script:FotosTseTentadas[$Sequencial] = ""
    try {
        if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
        Aguardar-Vez
        $ua = "gctse/1.0"
        if ((Tem-Propriedade $cfg.tse "user_agent") -and $cfg.tse.user_agent) { $ua = "$($cfg.tse.user_agent)" }
        $temporario = "$destino.tmp"
        Invoke-WebRequest -Uri $url -Headers @{ "User-Agent" = $ua } -TimeoutSec 20 `
                          -UseBasicParsing -OutFile $temporario -ErrorAction Stop
        Move-Item -Path $temporario -Destination $destino -Force
        $script:FotosTseTentadas[$Sequencial] = $destino
        Escrever-Log "foto do TSE baixada: $destino" "OK"
        return $destino
    } catch {
        Fechar-Resposta $_
        try { Remove-Item -Path "$destino.tmp" -Force -ErrorAction SilentlyContinue } catch { }
        Escrever-Log "sem foto no TSE para o candidato $Sequencial (nao tento de novo nesta execucao)"
        return ""
    }
}

function Encontrar-Foto {
    # Procura a foto do candidato e devolve o caminho do que achou, ou o
    # caminho da reserva. A lista de nomes aceitos deixa a pasta ser
    # organizada por numero ou por nome, sem o operador ter que escolher.
    param([string] $Numero, [string] $Nome, [string] $Sequencial = "",
          [string] $Abrangencia = "br", [int] $Cargo = 1)
    $pasta = $PastaFotos
    if (-not $pasta) { $pasta = "FOTOS" }

    # 1. mapa explicito no config: numero ou nome -> arquivo, para apelido
    #    que nao sai do nome de urna ("13": "lula.jpg")
    if (Tem-Propriedade $cfg.texto "fotos") {
        foreach ($chave in @($Numero, (Nome-Para-Arquivo $Nome))) {
            if ($chave -and (Tem-Propriedade $cfg.texto.fotos $chave)) {
                $alvo = "$($cfg.texto.fotos.$chave)"
                if ($alvo) {
                    $caminho = Join-Path $pasta (Split-Path -Leaf $alvo)
                    try { if (Test-Path $caminho) { return @{ caminho = $caminho; existe = "1" } } } catch { }
                }
            }
        }
    }
    # 2. numero, depois nome, depois primeiro nome
    foreach ($nomeArq in (Nomes-De-Foto-Aceitos $Numero $Nome)) {
        $caminho = Join-Path $pasta $nomeArq
        try { if (Test-Path $caminho) { return @{ caminho = $caminho; existe = "1" } } } catch { }
    }
    # 3. a foto que o proprio TSE publica, se estiver ligado no config.
    #    Fica por ultimo de proposito: foto escolhida pela emissora manda
    #    mais do que a oficial, e so se recorre a rede quando nao ha nada
    #    em disco.
    if ($FotosDoTse -and $Sequencial) {
        $baixada = Baixar-Foto-Do-TSE $Sequencial $Abrangencia $Cargo
        if ($baixada) { return @{ caminho = $baixada; existe = "1" } }
    }
    # 4. silhueta, para nunca deixar quadro quebrado no ar
    if ($FotoReserva) {
        $reserva = Join-Path $pasta (Split-Path -Leaf $FotoReserva)
        try { if (Test-Path $reserva) { return @{ caminho = $reserva; existe = "0" } } } catch { }
    }
    return @{ caminho = ""; existe = "0" }
}

$script:FotosFixas = @{}   # destino -> origem ja copiada

function Caminho-Fixo-Foto {
    # Caminho ABSOLUTO, igual ao do campo cand1_foto. O gerador de
    # caracteres resolve caminho relativo a partir da pasta DELE, nao da
    # pasta do gctse - um caminho relativo aqui vira imagem que nao carrega
    # na maquina do GC.
    param([int] $Indice)
    $pasta = $PastaSaida
    if (-not [IO.Path]::IsPathRooted($pasta)) { $pasta = Join-Path (Get-Location) $pasta }
    return (Join-Path $pasta ("foto-cand{0}.png" -f $Indice))
}

function Copiar-Foto-Para-Nome-Fixo {
    # Nem todo gerador de caracteres aceita vincular o CAMINHO de uma imagem
    # a um campo do banco. Quando nao aceita, a saida e o contrario: o
    # caminho fica FIXO na cena e quem troca e o arquivo. O coletor copia a
    # foto do candidato que esta em 1o para TARJAS\foto-cand1.png, e a cena
    # aponta para esse nome que nunca muda.
    # Copia so quando a origem muda, para nao reescrever imagem a cada ciclo
    # enquanto o GC pode estar lendo.
    param([string] $Origem, [string] $Destino)
    if (-not $Origem) { return }
    try {
        if ($script:FotosFixas.ContainsKey($Destino) -and $script:FotosFixas[$Destino] -eq $Origem) { return }
        if (-not (Test-Path $Origem)) { return }
        # No primeiro ciclo a pasta de saida ainda nao existe: a montagem da
        # tarja acontece antes da primeira gravacao que a criaria.
        $pastaDestino = Split-Path -Parent $Destino
        if ($pastaDestino -and -not (Test-Path $pastaDestino)) {
            New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null
        }
        $temporario = "$Destino.tmp"
        Copy-Item -Path $Origem -Destination $temporario -Force
        Move-Item -Path $temporario -Destination $Destino -Force
        $script:FotosFixas[$Destino] = $Origem
    } catch {
        Escrever-Log "nao consegui copiar a foto $Origem : $($_.Exception.Message)" "AVISO"
    }
}

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

    $encerrada = "0"
    if (Tem-Propriedade $Boletim "Encerrada") { $encerrada = "$($Boletim.Encerrada)" }

    $trilho = 0
    if (Tem-Propriedade $Tarja "trilho_px") { $trilho = [int] $Tarja.trilho_px }

    # Campo novo NUNCA entra no meio. O gerador de caracteres pode vincular
    # por POSICAO da coluna, e nao pelo nome: um campo inserido no meio
    # empurra todos os seguintes e a tarja vai ao ar com nome no lugar de
    # percentual. Aconteceu. Por isso o que e novo se acumula aqui e so e
    # anexado no fim, depois dos campos que ja existiam.
    $extras = [ordered]@{}

    for ($i = 1; $i -le 2; $i++) {
        $c = $null
        if ($Boletim.Candidatos.Count -ge $i) { $c = $Boletim.Candidatos[$i - 1] }
        $p = "cand$i" + "_"
        if ($null -eq $c) {
            $saida[$p + "visivel"] = "0"
            $saida[$p + "nome"] = ""
            $saida[$p + "partido"] = ""
            if ($Tarja.modelo -eq "presidente") {
                $extras[$p + "foto"] = ""
                $extras[$p + "foto_existe"] = "0"
                $extras[$p + "foto_fixa"] = ""
                if ($FotoNomeFixo) {
                    $fixo = Caminho-Fixo-Foto $i
                    $reservaVazia = ""
                    if ($FotoReserva) {
                        $reservaVazia = $FotoReserva
                        if ($PastaFotos) { $reservaVazia = Join-Path $PastaFotos (Split-Path -Leaf $FotoReserva) }
                    }
                    Copiar-Foto-Para-Nome-Fixo $reservaVazia $fixo
                    $extras[$p + "foto_fixa"] = $fixo
                }
            }
            $saida[$p + "percentual"] = ""
            $saida[$p + "barra_px"] = 0
            $saida[$p + "cor"] = ""
            $saida[$p + "eleito"] = "0"
            $extras[$p + "eleito_rotulo"] = ""
            $extras[$p + "situacao"] = ""
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
                    $extras[$p + "foto"] = ""
                    $extras[$p + "foto_existe"] = "0"
                    $extras[$p + "foto_fixa"] = ""
                    if ($FotoNomeFixo) { $extras[$p + "foto_fixa"] = Caminho-Fixo-Foto $i }
                }
                $saida[$p + "percentual"] = ""
                $saida[$p + "barra_px"] = 0
                $saida[$p + "cor"] = ""
                $saida[$p + "eleito"] = "0"
                $extras[$p + "eleito_rotulo"] = ""
                $extras[$p + "situacao"] = ""
                continue
            }
            $saida[$p + "visivel"] = "1"
            $saida[$p + "nome"] = $nomeCand
            $saida[$p + "partido"] = Limitar-Texto $c.Partido $LimitePartido
            if ($Tarja.modelo -eq "presidente") {
                # O TSE nao manda imagem: a foto e arquivo local, procurado
                # pelo numero do candidato e, em seguida, pelo nome.
                $seq = ""
                if (Tem-Propriedade $c "Sequencial") { $seq = "$($c.Sequencial)" }
                $achada = Encontrar-Foto $c.Numero $c.Nome $seq $Tarja.abrangencia ([int] $Tarja.cargo)
                $extras[$p + "foto"] = $achada.caminho
                $extras[$p + "foto_existe"] = $achada.existe
                $extras[$p + "foto_fixa"] = ""
                if ($FotoNomeFixo) {
                    $fixo = Caminho-Fixo-Foto $i
                    Copiar-Foto-Para-Nome-Fixo $achada.caminho $fixo
                    $extras[$p + "foto_fixa"] = $fixo
                }
            }
            $saida[$p + "percentual"] = Formatar-Percentual $c.Percentual
            $saida[$p + "barra_px"] = $largura
            $saida[$p + "cor"] = Obter-Cor $c.Partido
            $saida[$p + "eleito"] = $c.Eleito
            # Campo de TEXTO para o selo: a cena vincula um objeto de texto
            # aqui e ele aparece sozinho quando o TSE declara o eleito. Quem
            # preferir um grafico pronto usa o campo "eleito" (1 ou 0) na
            # visibilidade. Os dois existem porque os geradores diferem.
            # NAO chamar esta variavel de $rotuloEleito: no PowerShell ela
            # seria a MESMA que $RotuloEleito, que guarda o texto do config -
            # e a atribuicao de "" apagaria o texto antes de usa-lo.
            # Nome proprio: $selo la em cima e o "PARCIAL - NAO OFICIAL".
            # Reaproveitar a mesma variavel para duas coisas diferentes na
            # mesma funcao e como este arquivo ja quebrou antes.
            $seloEleito = ""
            if ($c.Eleito -eq "1") { $seloEleito = $RotuloEleito }
            $extras[$p + "eleito_rotulo"] = $seloEleito
            $situacao = ""
            if (Tem-Propriedade $c "Situacao") { $situacao = "$($c.Situacao)" }
            $extras[$p + "situacao"] = $situacao
        }
    }
    $extras["apuracao_encerrada"] = $encerrada
    foreach ($chave in $extras.Keys) { $saida[$chave] = $extras[$chave] }
    $arquivo = "tarja"
    if (Tem-Propriedade $Tarja "arquivo") { $arquivo = "$($Tarja.arquivo)" }
    return (Ordenar-Tarja $saida "$($Tarja.modelo)" $arquivo)
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
    param($Linhas, [int] $SegundosCiclo, [string] $Modo)
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
<meta http-equiv="refresh" content="$SegundosCiclo"><title>Painel de apuracao</title><style>
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
&middot; recarrega a cada <b>${intervalo}s</b></div></div>
$faixa
<main><table><thead><tr><th>Tarja</th><th>Praca</th><th class="num">Urnas</th>
<th>1o colocado</th><th class="num">%</th><th>2o colocado</th><th class="num">%</th>
<th>Situacao</th></tr></thead><tbody>
$corpo
</tbody></table></main></body></html>
"@
    $null = Escrever-Arquivo (Join-Path $PastaSaida "painel.html") $html
}

# ------------------------------------------------------------------- selecao

$script:Impressoes = @{}       # arquivo -> hash do conteudo, para nao reescrever a toa
$Impressoes = $script:Impressoes
$script:CacheBoletins = @{}    # "uf-cargo" -> ultimo boletim bom
$script:VistosNesteCiclo = @{}
$script:Alertas = @{}          # "uf-cargo" -> @{ desde; pct }
$script:Impressao = @{}        # "uf-cargo" -> impressao do ultimo boletim visto
$script:RegressaoVista = @{}   # "uf-cargo" -> quantas vezes o numero menor insistiu
$script:SelecaoRuimAvisada = ""  # ultimo valor invalido de SELECAO ja reclamado
# Quem esta gravando: maquina + processo. Serve para perceber duas coletas
# apontadas para a mesma pasta, que e o jeito errado de fazer redundancia.
# So o NOME DA MAQUINA, sem o numero do processo: o INICIAR.bat reinicia
# sozinho quando cai, e o processo novo tem PID novo. Comparando PID, cada
# reinicio gritaria "outra coleta" sem ter nenhuma - e aviso que mente
# algumas vezes deixa de ser lido na vez que importa.
$script:Dono = "$([Environment]::MachineName)"
if (-not $script:Dono) { $script:Dono = "maquina-sem-nome" }
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
        # Uma vez por valor ruim, e nao uma vez por chamada: esta funcao e
        # consultada dezenas de vezes por ciclo (uma por praca, por cargo),
        # e o mesmo aviso repetido 41 vezes empurra o resumo do ciclo para
        # fora da tela. Aviso que soterra a tela deixa de ser aviso.
        if ($script:SelecaoRuimAvisada -ne $uf) {
            $script:SelecaoRuimAvisada = $uf
            Escrever-Log "selecao '$uf' nao existe na lista de pracas: usando o padrao '$($cfg.selecao.padrao)'" "AVISO"
        }
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
        # O instante de verdade, e nao so a hora. Guardar "HH:mm:ss" e
        # reconstruir depois com ParseExact monta a data de HOJE: um alerta
        # aceso as 23:58 vira, a 00:05, um alerta do FUTURO, a diferenca da
        # negativa e ele nunca expira. A apuracao passa da meia-noite.
        quando = (Get-Date)
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
            $alerta = $script:Alertas[$chave]
            $quando = $null
            if ($alerta.ContainsKey("quando")) { $quando = $alerta.quando }
            if ($null -eq $quando) { continue }
            if (($agora - $quando).TotalSeconds -gt $segundos) { $script:Alertas.Remove($chave) }
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
    $null = Escrever-Arquivo (Join-Path $PastaSaida $cfg.alertas.arquivo) ($corpo | ConvertTo-Json -Depth 6)
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
    $bruto = Obter-Boletim (Montar-Url $Uf $Cargo) -Prioritario:(Esta-No-Ar $Uf $Cargo)
    # Falha de rede de UM pedido nao apaga o que ja se sabe: fica o ultimo
    # boletim bom, como no 304. Antes o resumo dizia "sem dado" para uma
    # praca que tinha dado de sobra, so porque um pedido falhou.
    if ($null -eq $bruto -and $script:CacheBoletins.ContainsKey($chave)) {
        return $script:CacheBoletins[$chave]
    }
    if ($bruto -eq "SEM-MUDANCA") {
        if ($script:CacheBoletins.ContainsKey($chave)) { return $script:CacheBoletins[$chave] }
        return $null
    }
    if ($null -ne $bruto) { $b = Normalizar-Boletim $bruto $Nome }
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
            # NAO chamar de $impressao: no PowerShell seria a MESMA variavel
            # que $Impressao, a tabela de escopo script. Hoje esta funcao nao
            # le essa tabela, entao nao quebra - mas a proxima edicao que
            # ler vai receber uma string no lugar de um hashtable, em
            # silencio. Ja aconteceu duas vezes neste arquivo.
            $marcaBoletim = Obter-Impressao-Boletim $b
            if ($script:RegressaoVista.ContainsKey($chave) -and
                $script:RegressaoVista[$chave].impressao -eq $marcaBoletim) {
                $script:RegressaoVista[$chave].vezes = $script:RegressaoVista[$chave].vezes + 1
            } else {
                $script:RegressaoVista[$chave] = @{ impressao = $marcaBoletim; vezes = 1 }
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
        Avisar-Candidato-Nao-Valido $chave $b $Uf $Cargo
        Marcar-Alerta $Uf $Cargo $b
        $script:CacheBoletins[$chave] = $b
    }
    return $b
}

$script:SituacaoAvisada = @{}

function Esta-No-Ar {
    # A praca que o GC esta exibindo agora: as tarjas fixas (presidente) mais
    # o que o operador selecionou para governador e senador.
    param([string] $Uf, [int] $Cargo)
    if (Tem-Propriedade $cfg "tarjas") {
        foreach ($t in $cfg.tarjas) {
            if ("$($t.abrangencia)" -eq $Uf -and [int] $t.cargo -eq $Cargo) { return $true }
        }
    }
    if (Tem-Propriedade $cfg "selecao") {
        foreach ($saida in $cfg.selecao.saidas) {
            if ([int] $saida.cargo -ne $Cargo) { continue }
            $praca = Ler-Selecao $saida.cargo
            if ($null -ne $praca -and $praca.uf -eq $Uf) { return $true }
        }
    }
    return $false
}

function Avisar-Candidato-Nao-Valido {
    # Nos dados reais do TSE um candidato com os votos ANULADOS aparece no
    # boletim com voto e percentual normais, e pode estar entre os dois
    # primeiros. Quem le no ar precisa saber disso ANTES de ler o nome em
    # voz alta. Avisa uma vez por praca e so volta a avisar se mudar.
    param([string] $Chave, $Boletim, [string] $Uf, [int] $Cargo)
    # So avisa sobre o que esta NO AR. Na varredura das 27 pracas o aviso
    # saia 27 vezes de uma vez e empurrava para fora da tela o resumo do
    # ciclo - que e a linha que o operador precisa ver. Aviso que vira
    # ruido deixa de ser aviso.
    if (-not (Esta-No-Ar $Uf $Cargo)) { return }
    $situacoes = @()
    $limite = [math]::Min(2, $Boletim.Candidatos.Count)
    for ($i = 0; $i -lt $limite; $i++) {
        $c = $Boletim.Candidatos[$i]
        $sit = ""
        if (Tem-Propriedade $c "Situacao") { $sit = "$($c.Situacao)" }
        if ($sit -and $sit -notmatch '^V[aá]lido') {
            $situacoes += "$($i + 1)o $($c.Nome): $sit"
        }
    }
    $resumo = ($situacoes -join " | ")
    $visto = ""
    if ($script:SituacaoAvisada.ContainsKey($Chave)) { $visto = $script:SituacaoAvisada[$Chave] }
    if ($resumo -eq $visto) { return }
    $script:SituacaoAvisada[$Chave] = $resumo
    if ($resumo) {
        Escrever-Log "${Chave}: o TSE marcou voto nao valido entre os dois primeiros - $resumo" "AVISO"
    }
}

function Tarjas-Congeladas {
    # Congelar e a unica protecao contra o pior momento no ar: o numero
    # mudando enquanto o apresentador le em voz alta. A coleta continua -
    # alertas, placar e listas seguem vivos - so as tres tarjas que o GC le
    # param de ser reescritas, ate alguem descongelar.
    return (Test-Path "CONGELADO.txt")
}

$script:UltimoMostrado = @{}

function Mostrar-No-Ar {
    # Escreve na janela o que acabou de ir para o arquivo da tarja. So quando
    # MUDA, entao nao vira ruido: numa apuracao parada, fica quieto.
    #
    # Existe porque "estou recebendo os dados?" nao pode depender de abrir
    # arquivo, rodar ferramenta ou olhar o LiveBoard. O numero que o GC vai
    # mostrar tem que estar escrito na tela de quem opera a coleta - e se o
    # LiveBoard mostrar outra coisa, a diferenca aparece na hora.
    param($Tarja)
    try {
        # So os numeros contam: a hora da tarja muda todo minuto e faria a
        # mesma linha sair de novo sem nada ter mudado.
        $assinatura = "$($Tarja["cargo"])|$($Tarja["abrangencia"])|$($Tarja["apuracao_pct"])|" +
                      "$($Tarja["cand1_nome"])|$($Tarja["cand1_percentual"])|$($Tarja["cand2_nome"])|$($Tarja["cand2_percentual"])"
        $chaveM = "$($Tarja["cargo"])"
        if ($script:UltimoMostrado.ContainsKey($chaveM) -and $script:UltimoMostrado[$chaveM] -eq $assinatura) { return }
        $script:UltimoMostrado[$chaveM] = $assinatura
        $partes = @()
        foreach ($i in 1, 2) {
            if ("$($Tarja["cand${i}_visivel"])" -eq "1") {
                $partes += ("{0}o {1} {2}" -f $i, $Tarja["cand${i}_nome"], $Tarja["cand${i}_percentual"])
            }
        }
        # Tarja sem candidato NAO e "OK": sai em amarelo, para ninguem ler
        # "NO ARQUIVO" e achar que o dado chegou.
        $cands = "SEM DADO DO TSE (tarja vazia)"
        $nivelM = "AVISO"
        if ($partes.Count -gt 0) { $cands = $partes -join "  |  "; $nivelM = "OK" }
        Escrever-Log ("NO ARQUIVO  {0} {1}  urnas {2}  |  {3}" -f $Tarja["cargo"], $Tarja["abrangencia"],
                      $Tarja["apuracao_pct"], $cands) $nivelM
    } catch { }
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
                PctUrnas = 0.0; Geracao = ""; Candidatos = @(); Encerrada = "0"
            }
        } else {
            $b = $b.PSObject.Copy()
        }
        $b.Praca = $praca.nome
        if (Tarjas-Congeladas) {
            # Congelada: nao publica agora. Zerar a impressao faz o arquivo
            # ser reescrito no primeiro ciclo depois do descongelamento -
            # sem isso, uma troca de praca feita durante o congelamento
            # ficaria perdida e o operador veria o estado antigo no ar.
            $script:Impressoes[$saida.arquivo] = ""
            continue
        }
        $montada = Montar-Tarja $b $saida
        $json = ($montada | ConvertTo-Json -Depth 5)
        $hash = Obter-Hash $json
        if ($Impressoes[$saida.arquivo] -ne $hash) {
            if (Escrever-Arquivo (Join-Path $PastaSaida "$($saida.arquivo).json") $json) {
                $Impressoes[$saida.arquivo] = $hash
                $publicados += $saida.arquivo
                Mostrar-No-Ar $montada
            }
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
            $montada = Montar-Tarja $b $tarja
            $json = ($montada | ConvertTo-Json -Depth 5)
            $hash = Obter-Hash $json
            if (Tarjas-Congeladas) {
                # Congelada: nao grava, mas o resto do ciclo segue igual - a
                # linha continua saindo no log e a impressao NAO e guardada,
                # para que ao descongelar o arquivo seja reescrito na hora.
                $situacao = "congelada"
            } elseif ($Impressoes[$tarja.arquivo] -eq $hash) {
                $situacao = "sem mudanca"
            } elseif (Escrever-Arquivo (Join-Path $PastaSaida "$($tarja.arquivo).json") $json) {
                $Impressoes[$tarja.arquivo] = $hash
                $situacao = "publicado"
                Mostrar-No-Ar $montada
            } else {
                $situacao = "gravacao falhou"
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
        # Grava a tarja NO AR agora, antes de varrer as outras 26 pracas.
        # Antes ela so era gravada no fim do ciclo: o dado da praca no ar
        # chegava no primeiro segundo e ficava esperando o Acre, Alagoas,
        # Amapa... ate Tocantins serem lidos - uns 11 segundos num dia bom,
        # MINUTOS se o CDN do TSE estiver lento em algum estado. O que esta
        # no ar nao pode depender do que nao esta. A gravacao do fim do
        # ciclo continua existindo e so reescreve se algo mudou.
        $null = Publicar-Selecionada $script:CacheBoletins
    }

    # --- varredura das demais pracas : a cada N ciclos
    if ($varredura -and (Tem-Propriedade $cfg "selecao")) {
        # O PRIMEIRO ciclo fala enquanto varre. A linha de resumo so sai
        # quando o ciclo fecha, e uma varredura de 55 leituras leva uns dez
        # segundos - dez segundos de tela muda logo depois de dar partida,
        # que e exatamente quando o operador esta olhando para ver se
        # funcionou. Tela muda no arranque parece defeito. Do segundo ciclo
        # em diante ele cala: aí o resumo ja esta aparecendo de 20 em 20s.
        $falante = ($script:Ciclo -eq 1)
        $totalPracas = $cfg.selecao.pracas.Count
        if ($falante) {
            Escrever-Log "varrendo as $totalPracas pracas. O resumo sai quando o ciclo fechar."
        }
        $feitas = 0
        foreach ($p in $cfg.selecao.pracas) {
            foreach ($saida in $cfg.selecao.saidas) {
                $null = Buscar-Praca $p.uf $saida.cargo $p.nome $Modo
            }
            $feitas++
            if ($falante -and ($feitas % 9) -eq 0 -and $feitas -lt $totalPracas) {
                Escrever-Log "  ... $feitas de $totalPracas pracas lidas"
            }
        }
        if ($falante) { Escrever-Log "varredura completa: $totalPracas pracas" "OK" }
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
                if (Escrever-Arquivo (Join-Path $PastaSaida "$($listaCfg.arquivo).json") $json) {
                    $Impressoes[$listaCfg.arquivo] = $hash
                }
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

# ------------------------------------------------- descoberta dos codigos

function Descobrir-Codigos {
    # No dia da eleicao os codigos de pleito e de eleicao sao os do TSE, e
    # ate a vespera ninguem sabe quais sao. A alternativa era alguem abrir o
    # config.json no domingo a noite e digitar numero na mao, com o telejornal
    # comecando. Isto le o ele-c.json do proprio TSE e resolve sozinho.
    #
    # Data de 2026 NAO identifica a eleicao geral: a lista do TSE vem cheia
    # de eleicao suplementar de prefeito com data de 2026. O que identifica
    # sao os CARGOS - Presidente (1), Governador (3), Senador (5). Presidente
    # fica numa eleicao e Governador/Senador em outra, por isso o mapa por
    # cargo e nao um codigo so.
    param([string] $Base)
    $url = "$($Base.TrimEnd('/'))/comum/config/ele-c.json"
    $bruto = $null
    try {
        $cabecalhos = @{}
        if ((Tem-Propriedade $cfg.tse "user_agent") -and $cfg.tse.user_agent) {
            $cabecalhos["User-Agent"] = $cfg.tse.user_agent
        }
        $resp = Invoke-WebRequest -Uri $url -Headers $cabecalhos -TimeoutSec 20 -UseBasicParsing
        $bruto = (Ler-Texto-Resposta $resp) | ConvertFrom-Json
    } catch {
        Fechar-Resposta $_
        Escrever-Log "nao consegui ler $url : $($_.Exception.Message)" "AVISO"
        return $null
    }
    if (-not (Tem-Propriedade $bruto "pl")) {
        Escrever-Log "o ele-c.json do TSE nao trouxe a lista de pleitos (campo pl)." "AVISO"
        return $null
    }

    $encontrado = $null
    foreach ($pleito in $bruto.pl) {
        if (-not (Tem-Propriedade $pleito "e")) { continue }
        foreach ($eleicao in $pleito.e) {
            $cargos = @()
            if (Tem-Propriedade $eleicao "abr") {
                foreach ($a in $eleicao.abr) {
                    if (-not (Tem-Propriedade $a "cp")) { continue }
                    foreach ($cargo in $a.cp) { $cargos += "$(Obter-Campo $cargo @('cd') '')" }
                }
            }
            $geral = ($cargos -contains "1") -or ($cargos -contains "3") -or ($cargos -contains "5")
            if (-not $geral) { continue }
            if ($null -eq $encontrado) {
                # O CICLO vem da DATA do pleito, e nao do campo "c" do
                # arquivo. Motivo concreto: em 22/09/2026 o ele-c.json do
                # ambiente oficial ainda trazia c="ele2024" enquanto ja
                # listava pleitos de 2026 - "c" e o ciclo corrente do
                # ambiente, nao o da eleicao que se procura. Confiar nele
                # montaria .../ele2024/... na noite da apuracao e daria 404
                # nas 55 pracas. A data nao mente: 06/10/2024 -> ele2024,
                # 04/10/2026 -> ele2026, que e o que o TSE de fato publica.
                $cicloDerivado = "$(Obter-Campo $bruto @('c') '')"
                $dataPleito = "$(Obter-Campo $pleito @('dt') '')"
                if ($dataPleito -match '(\d{4})\s*$') { $cicloDerivado = "ele$($Matches[1])" }
                $encontrado = @{
                    # Era "$ciclo", que nao existe aqui: sem diferenciar
                    # maiuscula, o PowerShell achava o CONTADOR de ciclos
                    # ($script:Ciclo = 1) e o caminho virava .../1/21270/...
                    # - 404 a noite inteira justo quando o TSE troca o codigo
                    # do simulado entre janelas. Achado e corrigido na 5.7.
                    ciclo   = $cicloDerivado
                    pleito  = "$(Obter-Campo $pleito @('cd') '')"
                    eleicao = "$(Obter-Campo $eleicao @('cd') '')"
                    cargos  = @{}
                    nomes   = @()
                }
            }
            foreach ($num in @("1", "3", "5")) {
                if ($cargos -contains $num) { $encontrado.cargos[$num] = "$(Obter-Campo $eleicao @('cd') '')" }
            }
            $encontrado.nomes += "$(Obter-Campo $eleicao @('cd') '') = " +
                             (Decodificar-Entidades "$(Obter-Campo $eleicao @('nm') '')")
        }
    }
    return $encontrado
}

function Garantir-Codigos {
    # Resolve os codigos do pleito para QUALQUER modo, nao so para a coleta.
    # Antes isto vivia solto no bloco de execucao, e o -Validar rodava antes
    # dele: montava URL com "000", nao lia boletim nenhum e mesmo assim
    # terminava dizendo "NENHUMA DIVERGENCIA". Validador que aprova sem ter
    # conferido e pior do que nao ter validador.
    $pleitoUso = "$($cfg.tse.pleito)"
    $eleicaoUso = "$($cfg.tse.eleicao)"
    $temMapa = $false
    if (Tem-Propriedade $cfg.tse "eleicao_por_cargo") {
        foreach ($prop in $cfg.tse.eleicao_por_cargo.PSObject.Properties) {
            if ($prop.Value) { $temMapa = $true }
        }
    }
    $semCodigo = (-not $pleitoUso) -or ($pleitoUso -eq "000") -or
                 ((-not $temMapa) -and ((-not $eleicaoUso) -or ($eleicaoUso -eq "000")))
    if (-not $semCodigo) { return $true }

    Escrever-Log "codigos ausentes no config.json - perguntando ao TSE" "AVISO"
    $encontrado = Descobrir-Codigos $cfg.tse.base_url
    if ($null -eq $encontrado) { return $false }

    if ($encontrado.ciclo) { $cfg.tse.ciclo = $encontrado.ciclo }
    $cfg.tse.pleito = $encontrado.pleito
    $cfg.tse.eleicao = $encontrado.eleicao
    $mapa = @{}
    foreach ($num in $encontrado.cargos.Keys) { $mapa[$num] = $encontrado.cargos[$num] }
    $cfg.tse.eleicao_por_cargo = [pscustomobject] $mapa
    Escrever-Log "o TSE respondeu: ciclo $($cfg.tse.ciclo), pleito $($encontrado.pleito)" "OK"
    foreach ($nome in $encontrado.nomes) { Escrever-Log "  eleicao $nome" }
    foreach ($num in @("1", "3", "5")) {
        if ($encontrado.cargos.ContainsKey($num)) {
            Escrever-Log "  cargo $num -> eleicao $($encontrado.cargos[$num])"
        }
    }
    # NAO grava no config.json de proposito. Codigo descoberto e gravado
    # vira codigo errado gravado no dia em que o TSE corrige o dele - e
    # ninguem ia descobrir isso no ar. Uma requisicao por partida e barato
    # demais para correr esse risco.
    Escrever-Log "descoberto agora, nao gravado no config.json - confira no CONFERIR.bat se duvidar"
    return $true
}

function Adotar-Codigos {
    # Passa a usar, so em memoria, os codigos que o TSE publica agora.
    param($Encontrado, [string] $Antes)
    if ($Encontrado.ciclo) { $cfg.tse.ciclo = $Encontrado.ciclo }
    $cfg.tse.pleito = $Encontrado.pleito
    $cfg.tse.eleicao = $Encontrado.eleicao
    $mapa = @{}
    foreach ($num in $Encontrado.cargos.Keys) { $mapa[$num] = $Encontrado.cargos[$num] }
    $cfg.tse.eleicao_por_cargo = [pscustomobject] $mapa
    Escrever-Log "o codigo do config estava velho: $Antes virou $($Encontrado.pleito)/$($Encontrado.eleicao)" "OK"
    Escrever-Log "seguindo com o codigo que o TSE publica agora. Caminho: $(Montar-Url 'br' 1)" "OK"
}

function Conferir-Codigo-No-TSE {
    # O TSE troca o codigo do simulado entre uma janela de teste e outra. Com
    # o codigo velho no config, as 55 pracas dao 404 e a tarja fica vazia sem
    # nada na tela dizendo por que. Antes isto so era percebido no FIM do
    # primeiro ciclo, e so pela coleta: o -Validar e o -Diagnostico seguiam
    # com o codigo velho e acusavam FALHA mesmo com a coleta recebendo.
    #
    # Agora TODO modo pergunta na porta: uma requisicao ao boletim do
    # presidente/Brasil. Respondeu, segue. 404 (ou 403, que e como alguns
    # CDNs respondem a arquivo inexistente), le o ele-c.json do TSE e, se o
    # codigo mudou, adota o novo. Falha de rede nao troca nada.
    $url = Montar-Url "br" 1
    $codigo = 0
    try {
        $ua = "gctse/1.0"
        if ((Tem-Propriedade $cfg.tse "user_agent") -and $cfg.tse.user_agent) { $ua = "$($cfg.tse.user_agent)" }
        $r = Invoke-WebRequest -Uri $url -Headers @{ "User-Agent" = $ua } -TimeoutSec 12 -UseBasicParsing
        return
    } catch {
        try { $codigo = [int] $_.Exception.Response.StatusCode } catch { }
        Fechar-Resposta $_
    }
    if ($codigo -ne 404 -and $codigo -ne 403) { return }
    $antes = "$($cfg.tse.pleito)/$($cfg.tse.eleicao)"
    Escrever-Log "o TSE respondeu $codigo para o codigo $antes do config - conferindo o codigo publicado" "AVISO"
    $encontrado = Descobrir-Codigos $cfg.tse.base_url
    if ($null -eq $encontrado) { return }
    if ("$($encontrado.pleito)/$($encontrado.eleicao)" -ne $antes) {
        Adotar-Codigos $encontrado $antes
    } else {
        Escrever-Log "o codigo $antes e o que o TSE publica; o boletim so ainda nao saiu" "AVISO"
    }
}

function Parar-Sem-Codigos {
    Write-Host ""
    if ($Teste) {
        Escrever-Log "Sem os codigos do SIMULADO, e o TSE nao respondeu." "ERRO"
        Write-Host "  Preencha 'pleito_simulado' e 'eleicao_simulado' no config.json."
    } else {
        Escrever-Log "Sem os codigos da eleicao, e o TSE nao respondeu." "ERRO"
        Write-Host "  Preencha 'pleito' e 'eleicao' no config.json."
    }
    Write-Host ""
    Write-Host "  Rode CONFERIR.bat: ele diz se o problema e a rede desta"
    Write-Host "  maquina ou se o TSE ainda nao publicou a eleicao geral."
    Write-Host ""
    exit 1
}

# ------------------------------------------------------------------ fotos

if ($Fotos) {
    if (-not (Garantir-Codigos)) { Parar-Sem-Codigos }
    # Le a lista de candidatos a presidente direto do TSE e escreve, para
    # cada um, os nomes de arquivo que o sistema aceita. Assim ninguem precisa
    # adivinhar como escrever o nome, nem eu preciso chutar quem sao os
    # candidatos: quem responde isso e o proprio TSE, na hora.
    $rel = New-Object System.Collections.ArrayList
    function Nota {
        param([string] $Texto = "")
        [void] $rel.Add($Texto)
        Write-Host $Texto
    }

    if ($Teste) {
        if ((Tem-Propriedade $cfg.tse "pleito_simulado") -and $cfg.tse.pleito_simulado) {
            $cfg.tse.pleito = $cfg.tse.pleito_simulado
        }
        if ((Tem-Propriedade $cfg.tse "eleicao_simulado") -and $cfg.tse.eleicao_simulado) {
            $cfg.tse.eleicao = $cfg.tse.eleicao_simulado
        }
    }

    $pasta = $PastaFotos
    if (-not $pasta) { $pasta = Join-Path (Get-Location) "FOTOS" }

    Nota "==========================================================="
    Nota " FOTOS DOS CANDIDATOS A PRESIDENTE"
    Nota " gctse $Versao   $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    Nota " modo: $(if ($Teste) { 'SIMULADO' } else { 'OFICIAL' })"
    Nota "==========================================================="
    Nota ""
    Nota " Ponha os arquivos nesta pasta:"
    Nota "   $pasta"
    Nota ""

    $url = Montar-Url "br" 1
    Nota " Lendo a lista de candidatos em:"
    Nota "   $url"
    $bruto = Obter-Boletim $url
    if ($bruto -eq "SEM-MUDANCA" -or $null -eq $bruto) {
        Nota ""
        Nota " NAO FOI POSSIVEL LER A LISTA AGORA."
        Nota " Rode o CONFERIR.bat para descobrir o que esta faltando."
        $utf8f = New-Object System.Text.UTF8Encoding($true)
        [IO.File]::WriteAllText((Join-Path $pasta "LISTA-DE-FOTOS.txt"), ($rel -join "`r`n"), $utf8f)
        exit 1
    }
    $b = Normalizar-Boletim $bruto "BRASIL"
    Nota ""
    Nota " $($b.Candidatos.Count) candidato(s) na lista do TSE."
    Nota ""

    $faltando = 0
    foreach ($c in $b.Candidatos) {
        Nota "-----------------------------------------------------------"
        Nota " $($c.Nome)   ($($c.Partido))   numero $($c.Numero)"
        $achada = Encontrar-Foto $c.Numero $c.Nome
        if ($achada.existe -eq "1") {
            Nota "   JA TEM FOTO: $(Split-Path -Leaf $achada.caminho)"
        } else {
            $faltando = $faltando + 1
            Nota "   FALTA A FOTO. Salve o arquivo com QUALQUER um destes nomes:"
            $vistos = @{}
            foreach ($nomeArq in (Nomes-De-Foto-Aceitos $c.Numero $c.Nome)) {
                $semExt = [IO.Path]::GetFileNameWithoutExtension($nomeArq)
                if ($vistos.ContainsKey($semExt)) { continue }
                $vistos[$semExt] = $true
                Nota "      $semExt.png   (ou .jpg, .jpeg, .webp, .bmp)"
            }
        }
        Nota ""
    }

    Nota "==========================================================="
    if ($faltando -eq 0) {
        Nota " TODOS OS CANDIDATOS TEM FOTO."
    } else {
        Nota " $faltando candidato(s) sem foto. Sem o arquivo, a tarja mostra"
        Nota " a silhueta do sem-foto.png - nao fica quadro quebrado no ar."
    }
    Nota ""
    Nota " Todas as fotos no MESMO tamanho e enquadramento, senao a tarja"
    Nota " desalinha quando a ordem dos candidatos muda. O sem-foto.png"
    Nota " esta em 420x560 (proporcao 3x4) e serve de referencia."
    Nota ""
    Nota " O numero e o nome vem do TSE: se o TSE reescrever o nome de urna,"
    Nota " o arquivo pelo NUMERO continua valendo. Por isso, na duvida,"
    Nota " nomeie pelo numero."
    Nota "==========================================================="

    if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    $utf8f = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText((Join-Path $pasta "LISTA-DE-FOTOS.txt"), ($rel -join "`r`n"), $utf8f)
    Write-Host ""
    Write-Host "  Gravado em FOTOS\LISTA-DE-FOTOS.txt" -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- campos

if ($Campos) {
    # Existe por um motivo concreto: duas vezes a tarja foi ao ar com dado no
    # lugar errado, e nas duas o arquivo estava certo - o que estava errado
    # era o vinculo na cena, ou o arquivo que a cena estava lendo. Discutir
    # isso por mensagem custa meia hora. Esta tela responde em dez segundos:
    # a coluna 7 do arquivo e o nome do candidato, ponto. Se no ar a coluna 7
    # mostra o estado, o problema esta na cena, nao aqui.
    $linhas = @()
    $linhas += "Colunas dos arquivos em $PastaSaida"
    $linhas += "gctse versao $Versao   -   $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    $linhas += ""
    $linhas += "Compare com a lista que o DataSource Editor do Castalia mostra."
    $linhas += "Tem que bater NUMERO POR NUMERO. A cena vincula por posicao."
    $linhas += ""

    if (-not (Test-Path $PastaSaida)) {
        Escrever-Log "a pasta $PastaSaida ainda nao existe. Rode INICIAR ou TESTE uma vez." "ERRO"
        exit 1
    }

    $arquivos = Get-ChildItem -Path $PastaSaida -Filter "*.json" | Sort-Object Name
    foreach ($arq in $arquivos) {
        $linhas += "==============================================================="
        $linhas += $arq.Name
        $linhas += "   gravado em: $($arq.LastWriteTime.ToString('dd/MM/yyyy HH:mm:ss'))"
        $linhas += "   caminho:    $($arq.FullName)"
        $linhas += ""
        $dado = $null
        try {
            $dado = (Get-Content -Path $arq.FullName -Raw -Encoding UTF8) | ConvertFrom-Json
        } catch {
            $linhas += "   NAO E JSON VALIDO: $($_.Exception.Message)"
            $linhas += ""
            continue
        }

        $chaves = @($dado.PSObject.Properties | ForEach-Object { $_.Name })
        $ehTarja = ($arq.Name -like "tarja-*") -and -not ($chaves -contains "pracas")
        $ehLista = ($chaves -contains "pracas")
        if (-not $ehTarja -and -not $ehLista) {
            # alertas.json e coleta.json sao do painel e do log. Nao tem
            # ordem travada porque nenhuma cena le esses dois.
            $linhas += "   (arquivo auxiliar do painel - nenhuma cena le este)"
            $linhas += ""
        }
        if ($ehLista) {
            # A confusao classica. Este arquivo tem 4 colunas no topo e os 27
            # estados escondidos dentro de "pracas". Se a cena de tarja for
            # apontada para ele, a coluna 1 vira o nome da lista e nada mais
            # bate. Ja aconteceu neste projeto.
            $linhas += "   *** ESTE NAO E ARQUIVO DE TARJA. ***"
            $linhas += "   E uma LISTA (placar de varios estados de uma vez)."
            $linhas += "   Serve para uma cena de tabela, nunca para a tarja de"
            $linhas += "   um estado so. Para a tarja use tarja-governador.json,"
            $linhas += "   tarja-senador.json ou tarja-presidente.json."
            $linhas += ""
        }

        $i = 0
        foreach ($prop in $dado.PSObject.Properties) {
            $i++
            $valor = $prop.Value
            if ($valor -is [array]) { $valor = "[ lista com $($valor.Count) itens ]" }
            elseif ($null -eq $valor) { $valor = "(vazio)" }
            elseif ("$valor" -eq "") { $valor = "(vazio)" }
            $linhas += ("   {0,2}  {1,-22} = {2}" -f $i, $prop.Name, $valor)
        }
        $linhas += ""

        if ($ehTarja) {
            $modelo = "majoritaria"
            if ($arq.Name -like "*presidente*") { $modelo = "presidente" }
            $esperado = Ordem-Do-Modelo $modelo
            $divergencias = @()
            for ($k = 0; $k -lt $esperado.Count; $k++) {
                $tem = ""
                if ($k -lt $chaves.Count) { $tem = $chaves[$k] }
                if ($tem -ne $esperado[$k]) {
                    $divergencias += ("   posicao {0}: o arquivo tem '{1}' e a ordem travada pede '{2}'" -f ($k + 1), $tem, $esperado[$k])
                }
            }
            if ($chaves.Count -ne $esperado.Count) {
                $divergencias += ("   o arquivo tem {0} colunas e o modelo {1} pede {2}" -f $chaves.Count, $modelo, $esperado.Count)
            }
            if ($divergencias.Count -eq 0) {
                $linhas += "   ORDEM CONFERE: $($esperado.Count) colunas, na ordem travada do modelo $modelo."
            } else {
                $linhas += "   ORDEM NAO CONFERE com o modelo $($modelo):"
                $linhas += $divergencias
            }
            $linhas += ""
        }
    }

    $linhas += "==============================================================="
    $linhas += ""
    $linhas += "Se a ordem CONFERE aqui e no ar a tarja aparece embaralhada, o"
    $linhas += "arquivo esta certo e o problema esta na cena do Castalia:"
    $linhas += ""
    $linhas += "  1. no DataSource Editor, confirme o CAMINHO do arquivo -"
    $linhas += "     tem que terminar em tarja-governador.json (e nao em"
    $linhas += "     lista-governador.json, nem numa copia antiga sua)."
    $linhas += "  2. confirme a HORA de gravacao impressa acima. Se ela nao"
    $linhas += "     anda, a cena esta lendo uma copia parada, nao o original."
    $linhas += "  3. remova e refaca o vinculo dos objetos de texto. Vincular"
    $linhas += "     na ordem: 7 = nome do 1o, 9 = percentual do 1o,"
    $linhas += "     14 = nome do 2o, 16 = percentual do 2o."
    $linhas += ""
    $linhas += "A referencia completa das colunas esta em CAMPOS.txt."

    $texto = ($linhas -join [Environment]::NewLine)
    Write-Host ""
    Write-Host $texto
    Write-Host ""
    $null = Escrever-Arquivo "CAMPOS-AGORA.txt" $texto
    Escrever-Log "gravei CAMPOS-AGORA.txt - pode mandar esse arquivo junto se a duvida continuar" "OK"
    exit 0
}

# ---------------------------------------------------------------- modelos

if ($Modelos) {
    # Regrava as tres tarjas VAZIAS, com todas as colunas na ordem travada.
    #
    # Existe porque as tarjas de exemplo da entrega ja ficaram para tras
    # duas vezes: o sistema passou a emitir campo novo e o exemplo continuou
    # com a contagem antiga. Quem montasse a cena por ele nao veria os
    # campos novos na arvore do DataSource.
    #
    # Gerando a partir da MESMA lista que a coleta usa, nao ha como divergir.
    foreach ($modelo in @(
        @{ arquivo = "tarja-presidente"; modelo = "presidente";  cargo = "PRESIDENTE" },
        @{ arquivo = "tarja-governador"; modelo = "majoritaria"; cargo = "GOVERNADOR" },
        @{ arquivo = "tarja-senador";    modelo = "majoritaria"; cargo = "SENADOR" })) {

        $vazia = [ordered]@{}
        foreach ($campo in (Ordem-Do-Modelo $modelo.modelo)) {
            if ($campo -eq "cargo") { $vazia[$campo] = $modelo.cargo }
            elseif ($campo -like "*_barra_px") { $vazia[$campo] = 0 }
            elseif ($campo -like "*_visivel" -or $campo -like "*_eleito" -or
                    $campo -like "*_foto_existe" -or $campo -eq "apuracao_encerrada") { $vazia[$campo] = "0" }
            else { $vazia[$campo] = "" }
        }
        $caminho = Join-Path $PastaSaida "$($modelo.arquivo).json"
        $null = Escrever-Arquivo $caminho ($vazia | ConvertTo-Json -Depth 5)
        Escrever-Log "$($modelo.arquivo).json regravado vazio, com $($vazia.Count) colunas" "OK"
    }
    Write-Host ""
    Write-Host "  Pronto. Aponte o DataSource do Castalia para estes arquivos e monte"
    Write-Host "  a cena: todas as colunas aparecem na arvore, mesmo sem dado nenhum."
    Write-Host "  Assim que o TESTE ou o INICIAR rodar, os MESMOS arquivos sao"
    Write-Host "  reescritos com o dado real - sem refazer vinculo."
    Write-Host ""
    exit 0
}

# ------------------------------------------------------------- diagnostico

if ($Diagnostico) {
    # UMA ferramenta, UM arquivo. Antes eram quatro (CONFERIR, VALIDAR,
    # CONFERIR-COLUNAS e o log), cada uma com o seu .txt, e a pergunta
    # "esta funcionando?" dependia de alguem juntar as quatro na cabeca -
    # com a janela do simulado fechando. Aqui ela vira um veredito escrito.
    #
    # Reaproveita os modos que ja existem rodando o proprio gctse como
    # processo filho: o que valida aqui e EXATAMENTE o mesmo codigo que
    # valida no VALIDAR, e nao uma segunda copia que poderia divergir.
    $linhasD = New-Object System.Collections.ArrayList
    function D { param([string] $Texto = "") [void] $linhasD.Add($Texto); Write-Host $Texto }

    $exe = (Get-Process -Id $PID).Path
    $raiz = (Get-Location).Path
    $pastaT = $PastaSaida
    if (-not [IO.Path]::IsPathRooted($pastaT)) { $pastaT = Join-Path $raiz $pastaT }
    $modoD = "OFICIAL"
    if ($Teste) { $modoD = "SIMULADO" }
    $argsModo = @()
    if ($Teste) { $argsModo = @("-Teste") }

    $veredito = [ordered]@{}

    D "==========================================================="
    D " DIAGNOSTICO gctse - validacao completa contra o TSE"
    D " $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')   modo: $modoD"
    D " maquina ..: $([Environment]::MachineName)"
    D " versao ...: $Versao"
    D " pasta ....: $raiz"
    D "==========================================================="

    # ---- 1. rede
    D ""
    D "1. A MAQUINA ALCANCA O TSE?"
    D ""
    $alvosRede = @(
        @{ rotulo = "SIMULADO"; base = "$($cfg.tse.base_url_simulado)" },
        @{ rotulo = "OFICIAL "; base = "$UrlOficial" }
    )
    $redeOk = @{}
    foreach ($alvo in $alvosRede) {
        $url = "$($alvo.base.TrimEnd('/'))/comum/config/ele-c.json"
        $relogio = [Diagnostics.Stopwatch]::StartNew()
        try {
            $r = Invoke-WebRequest -Uri $url -TimeoutSec 12 -UseBasicParsing
            $relogio.Stop()
            D ("   {0}  RESPONDE   HTTP {1} em {2} ms" -f $alvo.rotulo, [int] $r.StatusCode, $relogio.ElapsedMilliseconds)
            $redeOk[$alvo.rotulo.Trim()] = $true
        } catch {
            $relogio.Stop()
            Fechar-Resposta $_
            $motivo = $_.Exception.Message
            if ($motivo.Length -gt 90) { $motivo = $motivo.Substring(0, 90) }
            D ("   {0}  NAO RESPONDE  ({1} ms) - {2}" -f $alvo.rotulo, $relogio.ElapsedMilliseconds, $motivo)
            $redeOk[$alvo.rotulo.Trim()] = $false
        }
    }

    # ---- 2. a coleta esta viva?
    D ""
    D "2. A COLETA (TESTE.bat / INICIAR.bat) ESTA RODANDO?"
    D ""
    $intervaloD = 20
    if (Tem-Propriedade $cfg "intervalo_segundos") { $intervaloD = [int] $cfg.intervalo_segundos }
    $limiteVivo = 3 * $intervaloD + 15
    $batida = Join-Path $pastaT "coleta.json"
    $viva = $false
    $modoErrado = $false
    if (Test-Path $batida) {
        $idade = [int] ((Get-Date) - (Get-Item $batida).LastWriteTime).TotalSeconds
        $modoBat = ""; $cicloBat = ""
        try {
            $b = Get-Content $batida -Raw -Encoding UTF8 | ConvertFrom-Json
            if (Tem-Propriedade $b "modo") { $modoBat = "$($b.modo)" }
            if (Tem-Propriedade $b "ciclo") { $cicloBat = "$($b.ciclo)" }
        } catch { }
        $modoEsperado = "AR"
        if ($Teste) { $modoEsperado = "TESTE" }
        if ($idade -le $limiteVivo -and $modoBat -and $modoBat -ne $modoEsperado) {
            # A confusao mais provavel de todas: INICIAR.bat aberto quando
            # se queria o TESTE.bat, ou o contrario. O oficial ainda nao tem
            # boletim de 2026, entao as tarjas ficam VAZIAS e o sintoma e
            # exatamente "nao estou recebendo dados" - com tudo funcionando.
            $modoErrado = $true
            $nomeBat = "INICIAR.bat (OFICIAL)"
            if ($modoBat -eq "TESTE") { $nomeBat = "TESTE.bat (SIMULADO)" }
            $nomeCerto = "TESTE.bat"
            if (-not $Teste) { $nomeCerto = "INICIAR.bat" }
            D "   SIM, mas no MODO ERRADO: quem esta rodando e o $nomeBat."
            D "   Este diagnostico e do $modoD. Feche aquela janela e abra o $nomeCerto."
            D "   As duas gravam na MESMA pasta TARJAS - nao deixe as duas abertas."
        } elseif ($idade -le $limiteVivo) {
            $viva = $true
            D "   SIM. Ultimo ciclo fechou ha $idade s (modo $modoBat, ciclo $cicloBat)."
        } else {
            D "   NAO. O ultimo ciclo fechou ha $idade s - a coleta esta parada."
        }
    } else {
        D "   NAO. Nenhum ciclo foi completado ainda nesta pasta."
    }
    if (-not $viva) {
        D ""
        D "   Rodando UM ciclo agora, aqui mesmo, para ter o que conferir..."
        $saidaCiclo = & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -UmaVez @argsModo | Out-String
        $ult = @($saidaCiclo -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 6)
        foreach ($l in $ult) { D "     $l" }
    }

    # ---- 3. os arquivos que o Castalia le
    D ""
    D "3. OS ARQUIVOS QUE O CASTALIA / LIVEBOARD DEVE LER"
    D ""
    D "   Pasta: $pastaT"
    D "   O DataSource tem que apontar para ESTES arquivos, e nao para copias."
    D ""
    # "Gravado agora" nao quer dizer "tem dado": sem boletim, o sistema
    # grava a tarja VAZIA de proposito (nome da praca certo, candidatos
    # escondidos). Para quem opera, as duas coisas sao opostas - uma e o
    # sistema funcionando, a outra e a tela sem numero. Contam separado.
    $frescas = 0; $esperadas = 0; $comDado = 0
    foreach ($nome in @("tarja-presidente", "tarja-governador", "tarja-senador")) {
        $esperadas++
        $arq = Join-Path $pastaT "$nome.json"
        if (-not (Test-Path $arq)) { D ("   {0,-22} NAO EXISTE" -f "$nome.json"); continue }
        $idadeA = [int] ((Get-Date) - (Get-Item $arq).LastWriteTime).TotalSeconds
        $cols = 0; $temDado = $false
        try {
            $obj = Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json
            $cols = @($obj.PSObject.Properties).Count
            if ((Tem-Propriedade $obj "cand1_visivel") -and "$($obj.cand1_visivel)" -eq "1") { $temDado = $true }
        } catch { }
        if ($temDado) { $comDado++ }
        $estado = "com dado"
        if (-not $temDado) { $estado = "VAZIA - sem candidato" }
        if ($idadeA -gt $limiteVivo) { $estado = "$estado, PARADO" } else { $frescas++ }
        D ("   {0,-22} gravado ha {1,4} s   {2,2} colunas   {3}" -f "$nome.json", $idadeA, $cols, $estado)
    }
    D ""
    D "   (Um arquivo 'sem mudanca' pode ficar sem ser regravado se o TSE nao"
    D "    mudou nada. PARADO so preocupa se a coleta estiver rodando.)"

    # ---- 4. confere com o TSE
    D ""
    D "4. O QUE ESTA NOS ARQUIVOS CONFERE COM O TSE?"
    D ""
    $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Validar @argsModo | Out-String
    $okV = 0; $falhaV = 0; $nadaV = $false; $conferidasV = ""
    if (Test-Path "VALIDACAO.txt") {
        $txtV = Get-Content "VALIDACAO.txt" -Encoding UTF8
        # -cmatch, e nao -match: o -match do PowerShell ignora maiusculas, e
        # frase de rodape como "se a ordem CONFERE aqui" contaria como
        # resultado. Contagem de veredito tem que ser exata.
        $okV = @($txtV | Where-Object { $_ -cmatch '^   OK ' }).Count
        $falhaV = @($txtV | Where-Object { $_ -cmatch '^   FALHA' }).Count
        $nadaV = [bool] (@($txtV | Where-Object { $_ -cmatch 'NADA FOI CONFERIDO' }).Count)
        $linhaV = @($txtV | Where-Object { $_ -cmatch 'NENHUMA DIVERGENCIA|DIVERGENCIA\(S\)|NADA FOI' }) | Select-Object -First 1
        if ($linhaV) { $conferidasV = "$linhaV".Trim() }
        D "   $($okV + $falhaV) conferencias campo a campo: $okV batem, $falhaV divergem."
        if ($conferidasV) { D "   $conferidasV" }
        foreach ($l in @($txtV | Where-Object { $_ -cmatch '^   FALHA' } | Select-Object -First 8)) { D "   $l" }
    } else {
        D "   O validador nao gerou VALIDACAO.txt."
    }

    # ---- 5. colunas
    D ""
    D "5. AS COLUNAS ESTAO NA ORDEM QUE A CENA ESPERA?"
    D ""
    $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Campos | Out-String
    $ordemOk = 0; $ordemRuim = 0
    if (Test-Path "CAMPOS-AGORA.txt") {
        $txtC = Get-Content "CAMPOS-AGORA.txt" -Encoding UTF8
        $ordemOk = @($txtC | Where-Object { $_ -cmatch '^\s+ORDEM CONFERE:' }).Count
        $ordemRuim = @($txtC | Where-Object { $_ -cmatch '^\s+ORDEM NAO CONFERE' }).Count
        D "   $ordemOk tarja(s) na ordem travada, $ordemRuim fora de ordem."
    }

    # ---- 6. o que a tela tem que mostrar
    D ""
    D "6. O QUE A SUA TARJA TEM QUE MOSTRAR NA TELA AGORA"
    D "   Compare, numero por numero, com o LiveBoard. Se a tela mostra"
    D "   outra coisa, o arquivo esta certo e o problema e o vinculo da cena"
    D "   ou o caminho do DataSource."
    foreach ($nome in @("tarja-presidente", "tarja-governador", "tarja-senador")) {
        $arq = Join-Path $pastaT "$nome.json"
        if (-not (Test-Path $arq)) { continue }
        try { $t = Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        D ""
        D ("   {0} - {1}   urnas apuradas {2}   (campo 3)" -f $t.cargo, $t.abrangencia, $t.apuracao_pct)
        if ("$($t.selo)") { D "   selo: $($t.selo)" }
        foreach ($i in 1, 2) {
            $vis = "$($t."cand${i}_visivel")"
            if ($vis -ne "1") { D "     ${i}o  (vazio - sem candidato para mostrar)"; continue }
            $extra = ""
            if ((Tem-Propriedade $t "cand${i}_eleito_rotulo") -and "$($t."cand${i}_eleito_rotulo")") { $extra += "  [$($t."cand${i}_eleito_rotulo")]" }
            if ((Tem-Propriedade $t "cand${i}_situacao") -and "$($t."cand${i}_situacao")" -and "$($t."cand${i}_situacao")" -notmatch '^V.lido') {
                $extra += "  ($($t."cand${i}_situacao"))"
            }
            D ("     {0}o  {1,-22} {2,-12} {3,8}   barra {4}px{5}" -f $i, $t."cand${i}_nome", $t."cand${i}_partido",
                $t."cand${i}_percentual", $t."cand${i}_barra_px", $extra)
        }
    }
    D ""
    D "   ATENCAO: 'urnas apuradas' (campo 3) e o percentual do 1o colocado"
    D "   (campo 9) sao numeros DIFERENTES. Se na tela aparecem iguais,"
    D "   o objeto de urnas esta vinculado no campo errado."

    # ---- 7. log
    D ""
    D "7. ULTIMAS LINHAS DO LOG DE HOJE"
    D ""
    $arqLog = Join-Path "logs" ("gctse-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))
    $codigoVelho = ""
    if (Test-Path $arqLog) {
        $v = @(Get-Content $arqLog -Encoding UTF8 | Where-Object { $_ -cmatch 'codigo do config estava velho: (.+)$' }) | Select-Object -Last 1
        if ($v -and ("$v" -cmatch 'estava velho: (.+)$')) { $codigoVelho = $Matches[1] }
        foreach ($l in @(Get-Content $arqLog -Tail 30 -Encoding UTF8)) { D "   $l" }
        $errosHoje = @(Get-Content $arqLog -Encoding UTF8 | Where-Object { $_ -cmatch ' ERRO ' }).Count
        D ""
        D "   linhas de ERRO no log de hoje: $errosHoje"
    } else {
        D "   (sem log de hoje)"
    }

    # ---- veredito
    $redeModo = $redeOk["SIMULADO"]
    if (-not $Teste) { $redeModo = $redeOk["OFICIAL"] }
    # RECEBER e CONFERIR sao perguntas diferentes, e misturar as duas da a
    # pista errada: tarja vazia com o TSE respondendo nao e "nao recebe",
    # e "recebe e nao grava" - o conserto e em outro lugar.
    $recebe = $redeModo -and (-not $nadaV) -and (($okV + $falhaV) -gt 0)
    $confere = ($okV -gt 0) -and ($falhaV -eq 0) -and (-not $nadaV)
    $colunas = ($ordemOk -eq 3) -and ($ordemRuim -eq 0)
    $gravando = ($frescas -eq $esperadas) -and ($comDado -eq $esperadas)

    D ""
    D "==========================================================="
    D " VEREDITO"
    D "==========================================================="
    function Marca { param([bool] $Ok) if ($Ok) { return "[ OK ]" } return "[FALHA]" }
    D (" {0}  recebendo dados do TSE ({1})" -f (Marca $recebe), $modoD)
    D (" {0}  tarjas COM DADO, gravadas nos ultimos {1} s ({2} de {3} com candidato)" -f (Marca $gravando), $limiteVivo, $comDado, $esperadas)
    D (" {0}  tarjas conferem com o TSE, campo a campo ({1} de {2})" -f (Marca $confere), $okV, ($okV + $falhaV))
    if ($modoErrado) { D " [FALHA]  a coleta que esta rodando e do OUTRO modo - ver item 2" }
    if ($codigoVelho) {
        # O sistema ja se corrige sozinho, entao nao e FALHA. Mas quem le
        # precisa saber, para acertar o config.json com calma.
        D " [ !! ]  codigo do config.json VELHO ($codigoVelho)."
        D "         A coleta ja usa o codigo novo sozinha. Rode CONFERIR.bat"
        D "         para ver os numeros e acerte o config.json depois do teste."
    }
    D (" {0}  colunas na ordem que a cena espera" -f (Marca $colunas))
    if ($Teste) {
        if ($redeOk["OFICIAL"]) { D " [ OK ]  ambiente OFICIAL responde (o do dia 04/10)" }
        else { D " [ !! ]  ambiente OFICIAL NAO respondeu - ver item 1. Nao impede o teste," ; D "         mas TEM que responder antes do dia 04/10." }
    }
    D ""
    if ($recebe -and $confere -and $colunas -and $gravando -and -not $modoErrado) {
        D " TUDO CERTO DO LADO DO SISTEMA. Se a tela do LiveBoard nao mostra"
        D " o que esta no item 6, o problema esta na cena ou no DataSource."
    } else {
        D " HA PROBLEMA. Envie este arquivo inteiro (DIAGNOSTICO.txt)."
    }
    D "==========================================================="

    $utf8d = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText((Join-Path $raiz "DIAGNOSTICO.txt"), ($linhasD -join "`r`n"), $utf8d)
    Write-Host ""
    Write-Host "  Gravado em DIAGNOSTICO.txt, nesta pasta. Envie esse arquivo." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- validar

if ($Validar) {
    # Sem isto o validador montava URL com "000", nao lia boletim nenhum e
    # ainda assim aprovava no fim. Ver o comentario em Garantir-Codigos.
    if (-not (Garantir-Codigos)) { Parar-Sem-Codigos }
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
    Conferir-Codigo-No-TSE

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

    $script:Conferidos = 0
    $script:NaoLidos = @()
    foreach ($alvo in $alvos) {
        Diz ""
        Diz "-----------------------------------------------------------"
        Diz $alvo.rotulo
        $url = Montar-Url $alvo.abr $alvo.cargo
        Diz "   $url"
        $bruto = Obter-Boletim $url
        if ($bruto -eq "SEM-MUDANCA" -or $null -eq $bruto) {
            Diz "   NAO FOI POSSIVEL LER ESTE BOLETIM AGORA."
            $script:NaoLidos += $alvo.rotulo
            continue
        }
        $script:Conferidos = $script:Conferidos + 1
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
    if ($script:Conferidos -eq 0) {
        # Sem isto o validador dizia "NENHUMA DIVERGENCIA" tendo conferido
        # ZERO boletins - e quem lesse ia para o ar confiando numa conta que
        # nunca foi feita. Nao conferir e um resultado, e tem que aparecer
        # como resultado.
        Diz " NADA FOI CONFERIDO. Nenhum boletim voltou do TSE agora, entao"
        Diz " esta conferencia NAO diz se a tarja esta certa ou errada."
        Diz ""
        Diz " Rode CONFERIR.bat: ele diz se o problema e a rede desta maquina,"
        Diz " o codigo do pleito ou o TSE ainda nao ter publicado o boletim."
    } elseif ($script:Falhas -eq 0) {
        Diz " NENHUMA DIVERGENCIA em $($script:Conferidos) de $($alvos.Count) tarjas conferidas."
        Diz " O que esta nelas e o que o TSE mandou."
    } else {
        Diz " $($script:Falhas) DIVERGENCIA(S) ACIMA. Envie este arquivo para analise."
    }
    if ($script:NaoLidos.Count -gt 0 -and $script:Conferidos -gt 0) {
        Diz ""
        Diz " NAO conferidas, porque o boletim nao voltou do TSE agora:"
        foreach ($r in $script:NaoLidos) { Diz "   - $r" }
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
            Fechar-Resposta $_
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

$Modo = "AR"
if ($Teste) { $Modo = "TESTE" }

# Sem os codigos do pleito nao ha o que buscar: cada ciclo montaria 55 URLs
# invalidas, tomaria 55 respostas 404 e ainda assim gastaria o limite de
# requisicoes por minuto do TSE. Melhor parar na porta e dizer o porque.
if (-not (Garantir-Codigos)) { Parar-Sem-Codigos }
Conferir-Codigo-No-TSE

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
Escrever-Log "caminho: $(Montar-Url 'br' 1)"
if ($true) {
    Escrever-Log "$noAr req por ciclo comum, $naVarredura na varredura (1 a cada $ciclosVar)"
    # O limite do TSE e de 100 requisicoes por IP por SEGUNDO, e estourar da
    # 10 minutos de bloqueio (que reinicia se voce insistir durante ele).
    # O numero abaixo e a NOSSA valvula, deliberadamente muito mais baixa -
    # deixar isso implicito ja fez parecer que 80/min era regra do TSE.
    $porSegundo = [math]::Round($porMinuto / 60.0, 1)
    Escrever-Log "media de $porMinuto req/min (${porSegundo}/s). Limite do TSE: 100/s. Valvula nossa: $limiteReq/min"
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
        if ($script:Ciclo -eq 1 -and $script:BoletinsOk -eq 0) {
            Escrever-Log "NENHUM boletim voltou do TSE neste primeiro ciclo." "ERRO"

            # Codigo do config que envelheceu e a causa mais provavel aqui, e
            # e a unica que da para consertar sozinho: o TSE troca o codigo do
            # simulado entre as janelas de teste, e quem partiu com o codigo
            # velho toma 404 em todas as 55 pracas sem nada na tela dizendo
            # por que. Pergunta ao TSE UMA vez; se o codigo mudou, segue a
            # noite com o certo em vez de esperar alguem perceber.
            $antes = "$($cfg.tse.pleito)/$($cfg.tse.eleicao)"
            $encontrado = Descobrir-Codigos $cfg.tse.base_url
            if ($null -ne $encontrado -and "$($encontrado.pleito)/$($encontrado.eleicao)" -ne $antes) {
                Adotar-Codigos $encontrado $antes
            } else {
                Write-Host ""
                Write-Host "  O codigo do pleito confere com o que o TSE publica,"
                Write-Host "  entao o problema esta em outro lugar - rede, mais provavel."
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
        # Duas maquinas gravando na MESMA pasta de rede e o acidente mais
        # provavel de quem monta redundancia: as duas reescrevem a mesma
        # tarja, com selecoes possivelmente diferentes, e o que vai ao ar
        # passa a ser quem gravou por ultimo. Nao da para impedir daqui -
        # mas da para gritar, que e melhor do que descobrir no ar.
        $arqBatida = Join-Path $PastaSaida "coleta.json"
        if (Test-Path $arqBatida) {
            try {
                $anterior = Get-Content $arqBatida -Raw -Encoding UTF8 | ConvertFrom-Json
                $donoAnterior = ""
                if (Tem-Propriedade $anterior "dono") { $donoAnterior = "$($anterior.dono)" }
                if ($donoAnterior -and $donoAnterior -ne $script:Dono) {
                    Escrever-Log ("OUTRA COLETA esta gravando nesta mesma pasta: '$donoAnterior'. " +
                                  "As duas vao brigar pela mesma tarja e o ar fica com quem gravar " +
                                  "por ultimo. Feche uma, ou aponte cada maquina para a sua pasta.") "ERRO"
                }
            } catch { }
        }

        $batida = [ordered]@{
            atualizado_em = (Get-Date -Format "dd/MM/yyyy HH:mm:ss")
            dono = $script:Dono
            ciclo = $script:Ciclo
            modo = $Modo
            intervalo_segundos = [int] $cfg.intervalo_segundos
            requisicoes_no_minuto = $naJanela
            tarjas = $resumo
            mudancas_total = $script:MudancasTotal
            ultima_mudanca = $(if ($script:UltimaMudanca) { $script:UltimaMudanca.ToString("HH:mm:ss") } else { "" })
            segundos_sem_mudanca = $(if ($script:UltimaMudanca) { [int] ((Get-Date) - $script:UltimaMudanca).TotalSeconds } else { -1 })
        }
        $null = Escrever-Arquivo (Join-Path $PastaSaida "coleta.json") ($batida | ConvertTo-Json -Depth 4)
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
