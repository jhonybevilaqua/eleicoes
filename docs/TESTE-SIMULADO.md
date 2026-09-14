# Teste com o simulado do TSE

O TSE publica boletins de teste antes do pleito, nos mesmos caminhos do dia
oficial, em **fase `S`**. É a única chance de validar a cadeia inteira contra a
estrutura real de 2026 antes da eleição — e a janela fecha.

> **Pré-requisito que não dá para contornar:** o PC precisa alcançar
> `resultados.tse.jus.br` na porta 443. Se o chamado com a TI ainda não saiu,
> o teste não acontece. Confirme antes de marcar a equipe.

## Por que um arquivo de configuração separado

O simulado vem em fase `S`, e a trava que protege o ar rejeita exatamente isso.
Para testar é preciso desligá-la — e **essa trava nunca deve ser desligada no
`config.yaml` de produção**. Alguém esquece de religar, e um simulado vai ao ar
com cara de resultado.

Por isso existe o `config/config.teste-simulado.yaml`: trava desligada, saída
numa pasta de teste, log próprio. Nada nele encosta na configuração do ar, então
não há o que "restaurar depois".

## A sequência

Sempre com `-c config/config.teste-simulado.yaml`.

### 1 · Descobrir os códigos do pleito

```
gctse -c config/config.teste-simulado.yaml descobrir
```

Anote o código do pleito e o da eleição e preencha `tse.pleito` e
`tse.eleicao` no arquivo. É a única informação que não dá para adivinhar.

### 2 · Conferir as URLs montadas

```
gctse -c config/config.teste-simulado.yaml validar
```

Confira se as URLs impressas fazem sentido. Se `pleito` ainda estiver `000`,
você vai ver `e000000` nas URLs — sinal de que o passo 1 não foi aplicado.

### 3 · Conferir os nomes dos campos

```
gctse -c config/config.teste-simulado.yaml inspecionar --abrangencia br --cargo 1
```

Compare a saída com a tabela de [`TSE-API.md`](TSE-API.md). O TSE já renomeou
campos entre pleitos. Se algo mudou, corrija a seção `mapeamento` — é YAML, não
precisa recompilar nada:

```yaml
mapeamento:
  candidato:
    nome: [nmUrna]
    votos: [qtVotos]
```

### 4 · GRAVAR AS AMOSTRAS

```
gctse -c config/config.teste-simulado.yaml amostrar
```

**Este é o passo mais valioso do dia.** Ele salva os JSON reais em
`dados/amostras/`. Com eles você reproduz o teste offline quantas vezes quiser,
por meses, sem depender do TSE:

```yaml
coleta:
  fonte: arquivo
  pasta_amostras: dados/amostras
```

Quando a janela do simulado fechar, esses arquivos não voltam. Grave em mais de
um momento da apuração simulada — começo, meio e fim — para ter estados
diferentes.

### 5 · Rodar e acompanhar

```
gctse -c config/config.teste-simulado.yaml rodar
```

Abra `dados/teste-simulado/painel.html` no navegador e deixe num monitor. Ele se
recarrega sozinho a cada 20 s e mostra, por praça: percentual de urnas, 1º e 2º
colocado, e a situação de cada alvo.

A faixa amarela no topo avisa quando a fonte não é o TSE oficial. Durante o
simulado ela **não** aparece (a fonte é o TSE), mas cada praça mostra a etiqueta
`SIMULADO` — é assim que se distingue.

### 6 · Fechar a ponta no GC

Aponte o DataSource do Castalia para `dados/teste-simulado/gc/` e confira na
cena:

- [ ] nome e sigla do 1º e do 2º
- [ ] percentual de votos batendo com o painel
- [ ] **a barra acompanhando o número** — o ponto crítico
- [ ] o percentual de urnas no chip, diferente do percentual de votos
- [ ] praça sem boletim some (campo `visivel`)
- [ ] rodízio passando pelas praças na ordem configurada
- [ ] nome mais longo não estourando o lower third

## O que observar além da cena

**Quanto tempo o TSE leva entre atualizações.** O log mostra `sem-mudanca` entre
os ciclos em que nada mudou. Isso calibra o `intervalo_segundos` para o dia.

**Se algum alvo dá 404.** Pode ser que aquela praça/cargo não faça parte do
simulado. Não é necessariamente erro — confira com `inspecionar` na URL exata
que aparece no log.

**Se algum campo vem vazio.** Quase sempre é nome de campo que mudou. Volte ao
passo 3.

## Depois do teste

- [ ] Guardar `dados/amostras/` — é o ativo que sobra do dia.
- [ ] Guardar `logs/teste-simulado.log`.
- [ ] Anotar os códigos de pleito/eleição que funcionaram.
- [ ] Registrar qualquer ajuste de `mapeamento` que precisou ser feito, e
      **replicar no `config.yaml` de produção** — é o único conteúdo do teste
      que precisa migrar.
- [ ] Conferir que o `config.yaml` de produção segue com
      `bloquear_nao_oficial: true`. Ele não foi tocado, mas a conferência custa
      dez segundos.

## Reproduzir depois, sem o TSE

Com as amostras gravadas:

```yaml
coleta:
  fonte: arquivo
  pasta_amostras: dados/amostras
```

A cadeia inteira roda offline, com dado real, quantas vezes você quiser. É assim
que se investiga um problema encontrado no dia do teste sem precisar de outra
janela do TSE.
