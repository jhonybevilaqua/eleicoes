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
