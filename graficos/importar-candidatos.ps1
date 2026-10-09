<#
    gctse GRAFICOS - IMPORTAR CANDIDATOS: genero dos candidatos a Deputado
    Federal, do arquivo oficial do TSE (Portal de Dados Abertos).

    O boletim de resultados do TSE nao traz o genero do candidato. O arquivo
    "Candidatos" dos Dados Abertos traz (DS_GENERO), com o mesmo numero
    sequencial (SQ_CANDIDATO = sqcand do boletim). Este programa le esse
    arquivo e grava web\candidatos-genero.js para a tela "Bancada feminina".

    Uso: baixe em dadosabertos.tse.jus.br (Candidatos 2026 e, para comparar,
    Candidatos 2022) os arquivos consulta_cand_2026.zip e consulta_cand_2022.zip,
    ponha na pasta "importar" (ou deixe em Downloads) e de dois cliques em
    IMPORTAR-CANDIDATOS.bat. Le o .zip direto (ou o .csv ja extraido).
#>
[CmdletBinding(PositionalBinding = $false)]
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Caminhos = @())
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz
try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch { }
try { Add-Type -AssemblyName System.IO.Compression } catch { }

$script:Diag = New-Object System.Collections.Generic.List[string]
function Anotar([string] $Texto, [string] $Cor = "Gray") { Write-Host $Texto -ForegroundColor $Cor; $script:Diag.Add($Texto) }
function Sair([string] $Msg, [int] $Codigo) {
    if ($Codigo -ne 0) { Anotar $Msg "Red" } else { Anotar $Msg "Green" }
    try { [IO.File]::WriteAllLines((Join-Path $Raiz "IMPORTAR-CANDIDATOS.txt"), $script:Diag, (New-Object System.Text.UTF8Encoding($true))) } catch { }
    exit $Codigo
}
$Latin1 = [Text.Encoding]::GetEncoding(28591)   # os CSV do TSE vem em Latin-1

# ------------------------------------------------------------- achar arquivos
$onde = @()
if ($Caminhos -and @($Caminhos | Where-Object { $_ }).Count -gt 0) { $onde = @($Caminhos | Where-Object { $_ } | ForEach-Object { "$_".Trim('"') }) }
else {
    $onde = @((Join-Path $Raiz "importar"), $Raiz)
    if ($env:USERPROFILE) { $onde += @((Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop")) }
    try { $onde += [Environment]::GetFolderPath("Desktop") } catch { }
}
$arquivos = @()
foreach ($o in ($onde | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $o -PathType Leaf) { $arquivos += @(Get-Item -LiteralPath $o); continue }
    if (Test-Path -LiteralPath $o -PathType Container) {
        $arquivos += @(Get-ChildItem -LiteralPath $o -File -Recurse -Depth 1 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)^consulta_cand_(20\d\d).*\.(zip|csv|txt)$' })
    }
}
$arquivos = @($arquivos | Sort-Object FullName -Unique)

# Sem o arquivo de um ano: baixa sozinho do TSE (Dados Abertos, endereco
# oficial dos arquivos "Candidatos") para a pasta importar. Falhou: segue o
# caminho manual (baixar no site e por na pasta importar).
if (-not ($Caminhos -and @($Caminhos | Where-Object { $_ }).Count -gt 0)) {
    $pastaImp = Join-Path $Raiz "importar"
    foreach ($anoB in @("2026", "2022")) {
        if (@($arquivos | Where-Object { $_.Name -match "(?i)^consulta_cand_$anoB" }).Count -gt 0) { continue }
        $urlB = "https://cdn.tse.jus.br/estatistica/sead/odsele/consulta_cand/consulta_cand_$anoB.zip"
        $destB = Join-Path $pastaImp "consulta_cand_$anoB.zip"
        $tmpB = "$destB.baixando"
        Anotar "baixando do TSE: $urlB (pode levar alguns minutos)..." "Cyan"
        try {
            if (-not (Test-Path $pastaImp)) { New-Item -ItemType Directory -Path $pastaImp | Out-Null }
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            $pp = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
            try { Invoke-WebRequest -Uri $urlB -OutFile $tmpB -UseBasicParsing -TimeoutSec 900 } finally { $ProgressPreference = $pp }
            $zt = [IO.Compression.ZipFile]::OpenRead($tmpB); $zt.Dispose()   # confere se e um zip inteiro
            Move-Item -LiteralPath $tmpB -Destination $destB -Force
            $arquivos += @(Get-Item -LiteralPath $destB)
            Anotar ("   baixado: consulta_cand_{0}.zip ({1} MB)" -f $anoB, [math]::Round((Get-Item $destB).Length / 1MB, 1)) "Green"
        } catch {
            Remove-Item -LiteralPath $tmpB -Force -ErrorAction SilentlyContinue
            Anotar "   nao consegui baixar ($($_.Exception.Message)). Baixe na mao em dadosabertos.tse.jus.br > Candidatos $anoB e ponha na pasta importar." "Yellow"
        }
    }
}
if ($arquivos.Count -eq 0) {
    Anotar "Procurei em:" "Yellow"; foreach ($o in $onde) { Anotar "   $o" }
    Sair "nenhum consulta_cand_2026.zip (nem 2022). Baixe em dadosabertos.tse.jus.br > Candidatos 2026 (e 2022) e ponha na pasta importar." 1
}

# ---------------------------------------------------------------- ler o CSV
# Uma "fonte" = um leitor de texto (arquivo .csv ou entrada do .zip). Do zip,
# usa o arquivo do BRASIL se existir; senao, todos os estados.
function Fontes($Arq) {
    $lista = @()
    if ($Arq.Extension -match '(?i)\.zip$') {
        $zip = [IO.Compression.ZipFile]::OpenRead($Arq.FullName)
        $csvs = @($zip.Entries | Where-Object { $_.Name -match '(?i)\.(csv|txt)$' })
        $br = @($csvs | Where-Object { $_.Name -match '(?i)BRASIL' })
        if ($br.Count -gt 0) { $csvs = $br }
        foreach ($e in $csvs) { $lista += [pscustomobject]@{ nome = "$($Arq.Name) > $($e.FullName)"; entrada = $e; caminho = "" } }
    } else {
        $lista += [pscustomobject]@{ nome = $Arq.Name; entrada = $null; caminho = $Arq.FullName }
    }
    return $lista
}
function Abrir($F) {
    if ($F.entrada) { return New-Object IO.StreamReader($F.entrada.Open(), $Latin1) }
    return New-Object IO.StreamReader($F.caminho, $Latin1)
}
# Leitor de linha CSV do TSE (separador ;): campos com e sem aspas na mesma
# linha ("2026";6;"DEPUTADO FEDERAL") - os arquivos reais misturam. Em C#
# (rapido); sem compilador, divide no ; e tira as aspas.
try {
    if (-not ("GctseCsv" -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @"
public static class GctseCsv {
    // Campos de uma linha CSV do TSE (separador ;). Aceita campo com e sem
    // aspas na mesma linha ("2026";6;"DEPUTADO FEDERAL") e "" dentro de aspas.
    public static string[] Campos(string l) {
        var r = new System.Collections.Generic.List<string>(64);
        var sb = new System.Text.StringBuilder();
        int i = 0, n = l.Length;
        while (true) {
            sb.Length = 0;
            if (i < n && l[i] == '"') {
                i++;
                while (i < n) {
                    char c = l[i];
                    if (c == '"') { if (i + 1 < n && l[i + 1] == '"') { sb.Append('"'); i += 2; continue; } i++; break; }
                    sb.Append(c); i++;
                }
                while (i < n && l[i] != ';') { sb.Append(l[i]); i++; }   // lixo depois da aspa
            } else {
                while (i < n && l[i] != ';') { sb.Append(l[i]); i++; }
            }
            r.Add(sb.ToString());
            if (i >= n) break;
            i++;   // pula o ;
        }
        return r.ToArray();
    }
}
"@
    }
} catch { }
function Campos([string] $L) {
    if ("GctseCsv" -as [type]) { return [GctseCsv]::Campos($L) }
    return @($L.Split(';') | ForEach-Object { $_.Trim().Trim('"') })
}

$anos = @{}   # ano -> dados
# Perfil (tela "Perfil da nova Camara"): idade na posse, grau de instrucao,
# cor/raca e se disputava a reeleicao - colunas do proprio arquivo do TSE.
$script:RotGrau = New-Object System.Collections.Generic.List[string]
$script:RotCor = New-Object System.Collections.Generic.List[string]
function Indice($lista, [string] $v) { if (-not $v) { return -1 }; $i = $lista.IndexOf($v); if ($i -lt 0) { $lista.Add($v); $i = $lista.Count - 1 }; return $i }
function Idade([string] $nrIdade, [string] $nasc, [string] $ano) {
    $n = 0; if ([int]::TryParse($nrIdade, [ref] $n) -and $n -ge 18 -and $n -le 110) { return $n }
    $d = [datetime]::MinValue
    if ($ano -and [datetime]::TryParseExact($nasc, "dd/MM/yyyy", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref] $d)) {
        $posse = New-Object DateTime(([int] $ano + 1), 2, 1)
        $a = $posse.Year - $d.Year; if ($posse -lt $d.AddYears($a)) { $a-- }
        if ($a -ge 18 -and $a -le 110) { return $a }
    }
    return -1
}
foreach ($a in $arquivos) {
    foreach ($f in (Fontes $a)) {
        $rd = Abrir $f
        try {
            $cab = Campos ($rd.ReadLine())
            $ix = @{}; for ($i = 0; $i -lt $cab.Count; $i++) { $ix[$cab[$i].Trim().ToUpper()] = $i }
            foreach ($c in @("SQ_CANDIDATO", "SG_PARTIDO")) { if (-not $ix.ContainsKey($c)) { throw "coluna $c nao encontrada" } }
            if (-not ($ix.ContainsKey("DS_GENERO") -or $ix.ContainsKey("CD_GENERO"))) { throw "coluna DS_GENERO nao encontrada" }
            function V($p, [string] $n) { if ($ix.ContainsKey($n) -and $ix[$n] -lt $p.Count) { return $p[$ix[$n]].Trim() } return "" }
            $n = 0; $usadas = 0; $sens = 0; $cargosVistos = @{}
            while ($null -ne ($linha = $rd.ReadLine())) {
                $n++
                $p = Campos $linha
                $cargoCd = V $p "CD_CARGO"; $cargoDs = (V $p "DS_CARGO").ToUpper()
                if ($cargosVistos.Count -lt 12) { $cargosVistos["$cargoCd=$cargoDs"] = 1 }
                $ehSen = ($cargoCd -eq "5" -or $cargoDs -eq "SENADOR")
                if (-not ($ehSen -or $cargoCd -eq "6" -or $cargoDs -eq "DEPUTADO FEDERAL")) { continue }
                $turno = V $p "NR_TURNO"; if ($turno -and $turno -ne "1") { continue }
                $ano = V $p "ANO_ELEICAO"
                if (-not $ano) { $m = [regex]::Match($a.Name, '(20\d\d)'); $ano = $m.Value }
                if (-not $anos.ContainsKey($ano)) { $anos[$ano] = @{ cand = @{}; senF = @{}; senN = 0 } }
                $sq = V $p "SQ_CANDIDATO"
                $gen = (V $p "DS_GENERO").ToUpper(); $cdg = V $p "CD_GENERO"
                $fem = ($gen -match '^FEM') -or ($cdg -eq "4")
                # Senado: so o sqcand das mulheres (tela "10 senadoras mais votadas")
                if ($ehSen) { $anos[$ano].senN++; if ($fem) { $anos[$ano].senF[$sq] = 1 }; $sens++; continue }
                $sit = (V $p "DS_SITUACAO_CANDIDATURA").ToUpper()
                $tot = (V $p "DS_SIT_TOT_TURNO").ToUpper()
                $eleito = ($tot -match 'ELEIT') -and -not ($tot -match 'N.O ELEIT')
                $grau = (V $p "DS_GRAU_INSTRUCAO").ToUpper(); $corR = (V $p "DS_COR_RACA").ToUpper()
                if ($grau -match '^#' ) { $grau = "" }; if ($corR -match '^#') { $corR = "" }
                $reel = (V $p "ST_REELEICAO").ToUpper()
                $pf = @((Idade (V $p "NR_IDADE_DATA_POSSE") (V $p "DT_NASCIMENTO") $ano), (Indice $script:RotGrau $grau), (Indice $script:RotCor $corR), $(if ($reel -eq "S") { 1 } elseif ($reel -eq "N") { 0 } else { -1 }))
                $anos[$ano].cand[$sq] = [pscustomobject]@{ f = $fem; apto = ($sit -eq "" -or $sit -eq "APTO"); eleito = $eleito; sg = (V $p "SG_PARTIDO"); uf = (V $p "SG_UF"); pf = $pf }
                $usadas++
            }
            Anotar ("lido {0}: {1} linhas, {2} de Deputado Federal, {3} de Senador" -f $f.nome, $n, $usadas, $sens)
            if ($n -gt 0 -and $usadas -eq 0 -and $sens -eq 0) {
                # nada reconhecido: mostra o que o arquivo tem (para corrigir)
                Anotar ("   ATENCAO: nenhum cargo reconhecido. Colunas: {0} | cargos vistos (codigo=nome): {1}" -f $cab.Count, (($cargosVistos.Keys | Select-Object -First 12) -join " ; ")) "Yellow"
            }
        } catch { Anotar ("{0}: {1}" -f $f.nome, $_.Exception.Message) "Yellow" }
        finally { $rd.Dispose() }
    }
}
if ($anos.Count -eq 0) { Sair "nenhuma linha de Deputado Federal nos arquivos lidos." 1 }

# ------------------------------------------------------------------ resumir
$saida = [ordered]@{
    gerado_em = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    fonte = "TSE - Portal de Dados Abertos, Candidatos (consulta_cand)"
    rotulos_grau = @($script:RotGrau)
    rotulos_cor = @($script:RotCor)
    anos = [ordered]@{}
}
$anoMaisNovo = ($anos.Keys | Sort-Object | Select-Object -Last 1)
foreach ($ano in ($anos.Keys | Sort-Object)) {
    $cs = @($anos[$ano].cand.Values)
    $aptos = @($cs | Where-Object { $_.apto })
    $el = @($cs | Where-Object { $_.eleito })
    $elF = @($el | Where-Object { $_.f })
    $porPartido = [ordered]@{}
    foreach ($g in ($elF | Group-Object sg | Sort-Object Count -Descending)) { $porPartido[$g.Name] = $g.Count }
    # sqcand das MULHERES candidatas (a tela cruza com os eleitos do boletim ao vivo)
    $fems = @($anos[$ano].cand.GetEnumerator() | Where-Object { $_.Value.f } | ForEach-Object { $_.Key })
    $saida.anos[$ano] = [ordered]@{
        candidaturas = $cs.Count; candidaturas_mulheres = @($cs | Where-Object { $_.f }).Count
        aptas = $aptos.Count; aptas_mulheres = @($aptos | Where-Object { $_.f }).Count
        eleitos = $el.Count; eleitas = $elF.Count
        eleitas_por_partido = [pscustomobject] $porPartido
        mulheres = $fems
        mulheres_senado = @($anos[$ano].senF.Keys)
    }
    Anotar ("{0}: {1} candidaturas ao Senado, {2} de mulheres" -f $ano, $anos[$ano].senN, $anos[$ano].senF.Count) "Cyan"
    # perfil por sqcand [idade, grau, cor, reeleicao]: do ano mais novo, de
    # todos os aptos (a tela cruza com os eleitos do boletim ao vivo); dos
    # anos anteriores, so dos eleitos (para comparar).
    $perfil = [ordered]@{}
    foreach ($kv in $anos[$ano].cand.GetEnumerator()) {
        if (($ano -eq $anoMaisNovo -and $kv.Value.apto) -or $kv.Value.eleito) { $perfil[$kv.Key] = $kv.Value.pf }
    }
    $saida.anos[$ano].perfil = [pscustomobject] $perfil
    Anotar ("{0}: perfil (idade, instrucao, cor/raca, reeleicao) de {1} candidatos" -f $ano, $perfil.Count)
    Anotar ("{0}: {1} candidaturas a Deputado Federal ({2} aptas), {3} de mulheres ({4} aptas); eleitos no arquivo: {5}, mulheres: {6}" -f $ano, $cs.Count, $aptos.Count, $saida.anos[$ano].candidaturas_mulheres, $saida.anos[$ano].aptas_mulheres, $el.Count, $elF.Count) "Cyan"
}
$destino = Join-Path $Raiz "web\candidatos-genero.js"
$json = $saida | ConvertTo-Json -Depth 6 -Compress
[IO.File]::WriteAllText($destino, "window.GCTSE_GENERO = $json;", (New-Object System.Text.UTF8Encoding($false)))
Sair ("gravado web\candidatos-genero.js. No gerenciador, clique de novo nas telas 'Camara: bancada feminina', 'Perfil da nova Camara' e as telas do Jornalismo para carregar.") 0
