# Integração com o GC

Todos os exporters expõem o mesmo conjunto de campos. Muda só o empacotamento.

## Campos disponíveis

**Resumo** (cabeçalho do placar) — no CSV em linhas aparecem com prefixo `ap_`:

`cargo`, `cargo_codigo`, `abrangencia`, `abrangencia_codigo`, `abrangencia_tipo`,
`turno`, `eleicao`, `fase`, `fase_nome`, `oficial`, `totalizada`, `selo`,
`apuracao_pct`, `apuracao_pct_num`, `secoes_totalizadas`, `secoes_total`,
`eleitorado_apto`, `comparecimento`, `abstencao`, `votos_validos`,
`votos_nominais`, `votos_brancos`, `votos_nulos`, `total_apurado`,
`diferenca_lider`, `gerado_em`, `hora_geracao`, `atualizado_em`,
`hora_atualizacao`, `qtd_candidatos`

**Candidato** (uma linha por candidato):

`posicao`, `numero`, `nome`, `nome_completo`, `partido`, `coligacao`, `vice`,
`votos`, `votos_num`, `percentual`, `percentual_num`, `eleito`, `situacao`,
`sequencial`

Campos `*_num` vêm sem formatação (`60.00`), para cálculo e largura de barra.
Os demais vêm prontos para o ar (`2.400.000`, `60,00%`).

No layout largo (`cand1_nome`, `cand2_percentual`, …) os dois conjuntos vêm num
único registro — é o formato para take único.

## ClassX LiveBoard

O exporter `classx` gera **CSV, JSON ou XML** — os três com os mesmos nomes de
campo e as mesmas garantias. Trocar o `Type` no DataSource não obriga a mexer
em nada do lado do servidor: é só apontar para o outro arquivo.

### Qual `Type` escolher

| Type | Vínculo | Recomendação |
|---|---|---|
| **JSON** | pelo nome do campo (`resumo.cargo`, `candidatos[0].nome`) | **comece por aqui** — não existe deslocamento de célula, e os campos numéricos vêm como número de verdade |
| **XML** | por XPath (`/dados/candidatos/candidato[1]/nome`) | igualmente seguro; use se o LiveBoard amarrar melhor em XML na sua versão |
| **CSV** | por célula/coluna | funciona, desde que a geometria nunca mude — é o que este exporter garante |

Se o vínculo por nome funcionar bem na sua versão do LiveBoard, JSON resolve de
uma vez o problema que você levantou: não há coordenada para deslocar.

### A decisão que vem antes da configuração

Vale para os três formatos. Célula (ou índice) não se move sozinha — o que
muda é o que ela significa:

| `ordem` | A posição 1 é… | Na virada de liderança | Use quando |
|---|---|---|---|
| `colocacao` | sempre o 1º colocado | o **nome** dentro dela troca | placar de apuração, ranking |
| `fixa` | sempre o candidato nº X | nada muda de lugar | cena com foto/cor fixa por posição |

Se a cena tem a foto do candidato desenhada na posição, `ordem: fixa` é o único
modo correto — senão a foto do A aparece com os votos do B na primeira virada.
Dá para ter os dois ao mesmo tempo: dois exporters `classx`, cada um com sua
pasta e sua cena.

### O risco real: geometria variável

No CSV, o que de fato desloca célula não é o ranking — é o arquivo mudar de
tamanho. Quatro linhas às 17h e seis às 20h (apareceu candidato, o bloco de
resumo cresceu) e tudo abaixo escorrega, sem erro visível. O exporter blinda
contra isso, e a mesma garantia vale em JSON e XML:

- **sempre** `slots` registros de candidato — sobrou, corta; faltou, preenche
  vazio;
- ordem dos campos fixa em configuração, nunca a ordem que o TSE mandou;
- cabeçalho sempre na mesma linha;
- escrita atômica, então o LiveBoard nunca lê o arquivo pela metade.

Registro vazio sai com `visivel = 0` — amarre a visibilidade do objeto a esse
campo e a cena esconde sozinha as posições que não existem.

### Sort e "As number"

O `Sort` do DataSource não consegue ordenar `2.400.000` nem `50,00%` como
número — são texto formatado em pt-BR. Por isso cada campo numérico vem em duas
versões:

| Para exibir no ar | Para ordenar / calcular |
|---|---|
| `votos` → `2.400.000` | `votos_num` → `2400000` |
| `percentual` → `50,00%` | `percentual_num` → `50.0` |
| `apuracao_pct` → `50,00%` | `apuracao_pct_num` → `50.0` |

Se for usar o `Sort`, aponte **Column** para `votos_num` e marque **As number**.
Em JSON esses campos já saem como número (não string), então o `As number`
sequer é necessário. Os `*_num` também servem para largura de barra de
percentual.

Os dados já saem ordenados por votos, então o `Sort` do LiveBoard é opcional —
exceto se você usar `ordem: fixa` e quiser um ranking em outra cena a partir do
mesmo arquivo.

### JSON — o formato

```json
{
  "resumo": {
    "cargo": "GOVERNADOR",
    "apuracao_pct": "50,00%",
    "apuracao_pct_num": 50.0,
    "selo": ""
  },
  "candidatos": [
    { "posicao": 1, "visivel": "1", "numero": "11", "nome": "CANDIDATO ALFA",
      "partido": "PSD", "nome_partido": "CANDIDATO ALFA (PSD)",
      "percentual": "50,00%", "votos": "2.000.000",
      "percentual_num": 50.0, "votos_num": 2000000 },
    { "posicao": 3, "visivel": "0", "nome": "", "votos_num": null }
  ],
  "plano": { "cargo": "GOVERNADOR", "cand1_nome": "CANDIDATO ALFA", "...": "" }
}
```

O bloco `plano` é o mesmo conteúdo achatado (`cand1_nome`, `cand2_percentual`…),
para quem prefere amarrar por uma chave única em vez de índice de array — é o
equivalente direto ao seu jeito atual de buscar campo a campo. Desligue com
`incluir_plano: false` se não usar.

### XML — o formato

```xml
<dados>
  <resumo>
    <cargo>GOVERNADOR</cargo>
    <apuracao_pct>50,00%</apuracao_pct>
  </resumo>
  <candidatos>
    <candidato posicao="1">
      <nome>CANDIDATO ALFA</nome>
      <nome_partido>CANDIDATO ALFA (PSD)</nome_partido>
      <percentual>50,00%</percentual>
      <votos_num>2000000</votos_num>
    </candidato>
  </candidatos>
</dados>
```

`<candidato>` repetido sob `<candidatos>` é a estrutura que leitores de XML
esperam para iterar registros.

### CSV — os três layouts

Configure o DataSource com **Separator** `;`, **Text delimiter** `"`, nomes de
coluna na primeira linha e **trim fields** ligado — bate com o que é gerado.

**`chave_valor`** (padrão para CSV) — coluna A é o nome do campo, coluna B é o
valor. Cada campo tem sua linha fixa; você amarra sempre em `B<n>`:

```
campo;valor
cargo;GOVERNADOR
...
cand1_nome_partido;CANDIDATO ALFA (PSD)     <- B20
cand1_percentual;50,00%                     <- B21
```

É exatamente o padrão que você descreveu: nome com partido numa célula,
percentual na de baixo. O campo `nome_partido` já vem montado, então um único
objeto da cena resolve a linha (formato configurável em `formato_nome_partido`).

**`grade`** — tabela clássica: linha 1 é cabeçalho, linhas 2 em diante são os
slots. É o layout que combina com **Sort** e com nomes de coluna na primeira
linha. O resumo sai num segundo arquivo, `<alvo>-resumo.csv`, também de
geometria fixa.

```
visivel;numero;nome;partido;nome_partido;percentual;votos;percentual_num;votos_num;eleito
1;11;CANDIDATO ALFA;PSD;CANDIDATO ALFA (PSD);50,00%;2.000.000;50.00;2000000;0
0;;;;;;;;;
```

**`largo`** — tudo numa linha só (linha 1 cabeçalho, linha 2 valores). Para cena
de take único: `A2`, `B2`, `C2`…

### Configuração

```yaml
exporters:
  liveboard:
    tipo: classx
    formato: json           # json | xml | csv
    ordem: colocacao
    slots: 6
    encoding: utf-8
    destino: "//liveboard/dados"
    nome_arquivo: "{alvo}"
    formato_nome_partido: "{nome} ({partido})"
    incluir_plano: true

    # só valem quando formato: csv
    layout: chave_valor
    delimitador: ";"
```

Para o modo de candidato fixo:

```yaml
    ordem: fixa
    candidatos_fixos: ["22", "13", "12"]   # posição 1 = nº 22, posição 2 = nº 13…
```

Em `ordem: fixa`, `slots` passa a ser o tamanho da lista. Número que não
aparecer no boletim sai como registro vazio, com `visivel = 0`.

### O mapa de vínculos

Não amarre a cena por tentativa e erro. O comando abaixo diz exatamente onde
cada campo está — célula no CSV, caminho de chave no JSON, XPath no XML. Roda
sem precisar de dado do TSE, então pode ser gerado semanas antes do pleito e
entregue junto com o roteiro da cena:

```bash
gctse celulas
gctse celulas --pasta dados/saida/mapa    # também grava em CSV
```

```
=== governador-pr  /  exporter 'liveboard'  /  formato json  /  ordem colocacao
    arquivo: dados/saida/liveboard/governador-pr.json
    CAMINHO                        CAMPO                      OBSERVACAO
    resumo.cargo                   cargo                      resumo
    resumo.apuracao_pct            apuracao_pct               resumo
    candidatos[0].nome             cand1_nome                 1o colocado no momento
    candidatos[0].nome_partido     cand1_nome_partido         1o colocado no momento
    plano.cand1_nome               cand1_nome                 1o colocado no momento (plano)
```

A coluna de observação é o que evita o erro caro: ela diz se aquela posição é
“1º colocado no momento” ou “sempre o candidato nº 22”.

**As referências só mudam se você alterar `formato`, `layout`, `ordem`, `slots`
ou as listas `campos_resumo` / `campos_candidato`.** Se mexer em qualquer um
desses depois de a cena estar amarrada, gere o mapa de novo e refaça os
vínculos. Fora isso, a posição é estável do primeiro ao último boletim do dia.

### Encoding

Em JSON e XML, `utf-8`. Em CSV, `utf-8-sig` (UTF-8 com BOM) é o padrão
sugerido: o acento sai correto e o arquivo abre certo no Excel se alguém
precisar conferir na mão. Se o LiveBoard mostrar caractere estranho, tente
`cp1252`. Em último caso, `texto.remover_acentos: true` tira o problema pela
raiz, ao custo de o nome ir ao ar sem acento.

## Ross XPression (DataLinq)

```yaml
exporters:
  xpression:
    tipo: csv
    layout: linhas
    delimitador: ","
    destino: "//servidor-gc/datalinq/eleicoes"
    nome_arquivo: "{alvo}"
    limite_candidatos: 8
```

No XPression, crie a fonte DataLinq apontando para o arquivo, com *refresh*
por intervalo (5 s serve) e a primeira linha como cabeçalho. Ligue os campos da
cena aos nomes das colunas.

Para um take único com todos os candidatos, use `layout: largo` e ligue a
`cand1_nome`, `cand1_percentual`, `cand2_nome` e assim por diante.

## Chyron (Lyric / PRIME)

O perfil `tabular` gera o XML genérico de registros/campos que os importadores
da Chyron leem:

```yaml
exporters:
  chyron:
    tipo: xml
    perfil: tabular
    destino: "//servidor-gc/chyron/data"
    encoding: utf-8      # troque para cp1252 se acento sair quebrado
```

```xml
<records>
  <record>
    <field name="ap_cargo">GOVERNADOR</field>
    <field name="nome">CANDIDATA ALFA</field>
    <field name="percentual">60,00%</field>
  </record>
</records>
```

Se a estação usar CSV em vez de XML, o exporter `csv` atende igual.

## Vizrt

**Viz Trio — tab fields.** A ordem em `campos` precisa bater com a ordem dos
tab fields da página:

```yaml
exporters:
  viz:
    tipo: viz_tab
    destino: "//viz-trio/import"
    campos: [posicao, nome, partido, percentual, votos]
```

**Viz Pilot / data feed.** Use o perfil `atributos`, que põe o resumo como
atributos da raiz e cada candidato como um elemento com atributos:

```yaml
exporters:
  pilot:
    tipo: xml
    perfil: atributos
    raiz: data
    registro: row
```

## CasparCG

Gera `templateData` XML e um JSON equivalente:

```yaml
exporters:
  caspar:
    tipo: casparcg
    destino: "C:/CasparCG/data"
    limite_candidatos: 5
    mapa_campos:
      f0: cargo
      f1: abrangencia
      f2: apuracao_pct
      f3: cand1_nome
      f4: cand1_percentual
      f5: cand2_nome
      f6: cand2_percentual
```

```xml
<templateData>
  <componentData id="f0"><data id="text" value="GOVERNADOR"/></componentData>
</templateData>
```

Sem `mapa_campos`, todos os campos saem com o nome próprio — o que costuma ser
mais prático para template HTML, que pode ler o JSON direto via `fetch`.

## GC com API própria, broker ou Power Automate

```yaml
exporters:
  push_gc:
    tipo: http
    url: ${GC_WEBHOOK_URL}
    metodo: POST
    formato: gc            # gc | largo | completo
    cabecalhos:
      Authorization: Bearer ${GC_TOKEN}
```

`${VAR}` é lido do ambiente, então token não vai para o repositório. Falha de
entrega é registrada e não interrompe o ciclo: o próximo boletim tenta de novo.

Esse mesmo exporter serve para acionar um fluxo do Power Automate — publicar o
placar num SharePoint, alimentar um Power BI de acompanhamento interno ou
avisar um canal do Teams a cada virada de liderança.

## Ajustes finos de layout

```yaml
texto:
  caixa: alta
  remover_acentos: false   # true se o GC não renderiza acento de fonte externa
  limites:
    nome: 22               # corta sem quebrar palavra
    coligacao: 40
  formatar_numeros: true
  separador_milhar: "."
  casas_percentual: 2
```

Encoding é por exporter: dá para escrever `cp1252` no hot folder do GC legado e
`utf-8` na pasta do web ao mesmo tempo.

## Quando algo não aparece no ar

| Sintoma | Causa provável |
|---|---|
| Arquivo não aparece | fase não oficial bloqueada — veja `saude.json` e o log |
| Arquivo não atualiza | conteúdo idêntico (dedupe). Force com `saida.reescrever_sempre: true` só para teste |
| Acento quebrado | `encoding` do exporter — tente `cp1252` |
| Nome estourando o layout | `texto.limites.nome` |
| Placar “pisca” trocando posições | empate real; a ordenação já desempata pelo número do candidato |
| GC lê arquivo pela metade | não deveria acontecer (escrita atômica). Confirme que a saída não está num compartilhamento que copia em duas etapas |
