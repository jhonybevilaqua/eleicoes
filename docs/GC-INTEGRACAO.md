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

O LiveBoard amarra cada objeto da cena a uma célula (B7, C12…). Isso é
confiável desde que a **geometria do arquivo nunca mude**. O exporter `classx`
garante isso.

### A decisão que vem antes da configuração

Célula não se move sozinha. O que muda é o que ela significa:

| `ordem` | A linha 1 é… | Na virada de liderança | Use quando |
|---|---|---|---|
| `colocacao` | sempre o 1º colocado | o **nome** dentro da célula troca | placar de apuração, ranking |
| `fixa` | sempre o candidato nº X | nada muda de lugar | cena com foto/cor fixa por posição |

Se a cena tem a foto do candidato desenhada na posição, `ordem: fixa` é o
único modo correto — senão a foto do A aparece com os votos do B na primeira
virada. Se a cena é um ranking neutro, `colocacao` é o certo.

Dá para ter os dois ao mesmo tempo: dois exporters `classx`, cada um com sua
pasta e sua cena.

### O risco real: geometria variável

O que de fato desloca célula não é o ranking — é o arquivo mudar de tamanho.
Quatro linhas às 17h e seis às 20h (apareceu candidato, o bloco de resumo
cresceu) e tudo abaixo desliza, sem erro visível. O exporter blinda contra
isso:

- **sempre** `slots` linhas de candidato — sobrou, corta; faltou, preenche
  vazio;
- ordem das colunas fixa em configuração, nunca a ordem que o TSE mandou;
- cabeçalho sempre na mesma linha;
- escrita atômica, então o LiveBoard nunca lê o arquivo pela metade.

Cada linha vazia sai com `visivel = 0` — amarre a visibilidade do objeto a
esse campo e a cena esconde sozinha as posições que não existem.

### Layouts

**`chave_valor`** (padrão, e o mais indicado para vínculo por célula) — coluna
A é o nome do campo, coluna B é o valor. Cada campo tem sua linha fixa; você
amarra sempre em `B<n>`:

```
campo;valor
cargo;GOVERNADOR
abrangencia;PARANA
...
cand1_nome_partido;RATINHO JUNIOR (PSD)     <- B19
cand1_percentual;50,00%                     <- B20
```

Repare que é exatamente o padrão que você descreveu: nome com partido numa
célula, percentual na de baixo. O campo `nome_partido` já vem montado, então
um único objeto da cena resolve a linha inteira. O formato é configurável em
`formato_nome_partido`.

**`grade`** — tabela clássica: linha 1 é cabeçalho, linhas 2 em diante são os
slots. Bom quando a cena tem uma lista e você amarra por coluna. O resumo sai
num segundo arquivo, `<alvo>-resumo.csv`, também de geometria fixa.

```
visivel;numero;nome;partido;nome_partido;percentual;votos;eleito
1;11;RATINHO JUNIOR;PSD;RATINHO JUNIOR (PSD);50,00%;2.000.000;0
1;22;CANDIDATO BETA;PL;CANDIDATO BETA (PL);35,00%;1.400.000;0
0;;;;;;;
```

**`largo`** — tudo numa linha só (linha 1 cabeçalho, linha 2 valores). Para
cena de take único: `A2`, `B2`, `C2`…

### Configuração

```yaml
exporters:
  liveboard:
    tipo: classx
    layout: chave_valor
    ordem: colocacao
    slots: 6
    delimitador: ";"
    encoding: utf-8-sig
    destino: "//liveboard/dados"
    nome_arquivo: "{alvo}"
    formato_nome_partido: "{nome} ({partido})"
```

Para o modo de candidato fixo:

```yaml
    ordem: fixa
    candidatos_fixos: ["22", "13", "12"]   # linha 1 = nº 22, linha 2 = nº 13...
```

Em `ordem: fixa`, `slots` passa a ser o tamanho da lista. Número que não
aparecer no boletim sai como linha vazia, com `visivel = 0`.

### O mapa de células

Não amarre a cena por tentativa e erro. O comando abaixo diz exatamente qual
célula guarda qual campo — e roda sem precisar de dado do TSE, então pode ser
gerado semanas antes do pleito e entregue junto com o roteiro da cena:

```bash
gctse celulas
gctse celulas --pasta dados/saida/mapa    # também grava em CSV
```

```
=== governador-pr  /  exporter 'liveboard'  /  layout chave_valor  /  ordem colocacao
    arquivo: dados/saida/liveboard/governador-pr.csv
    CELULA   CAMPO                      ARQUIVO / OBSERVACAO
    B2       cargo                      governador-pr.csv  (resumo)
    B5       apuracao_pct               governador-pr.csv  (resumo)
    B17      cand1_nome                 governador-pr.csv  (1o colocado no momento)
    B19      cand1_nome_partido         governador-pr.csv  (1o colocado no momento)
    B20      cand1_percentual           governador-pr.csv  (1o colocado no momento)
```

A coluna de observação é o que evita o erro caro: ela diz se aquela célula é
“1º colocado no momento” ou “sempre o candidato nº 22”.

**As células só mudam se você alterar `layout`, `ordem`, `slots` ou as listas
`campos_resumo` / `campos_candidato`.** Se mexer em qualquer um desses depois
de a cena estar amarrada, gere o mapa de novo e refaça os vínculos. Fora isso,
a posição é estável do primeiro ao último boletim do dia.

### Encoding

`utf-8-sig` (UTF-8 com BOM) é o padrão sugerido: o acento sai correto e o
arquivo abre certo no Excel se alguém precisar conferir na mão. Se o LiveBoard
mostrar caractere estranho, tente `cp1252`. Em último caso,
`texto.remover_acentos: true` tira o problema pela raiz, ao custo de o nome ir
ao ar sem acento.

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
