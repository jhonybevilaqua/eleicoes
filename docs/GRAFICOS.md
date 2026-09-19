# Gráficos, mapas e a série da apuração

O placar é o que mais aparece, mas não é o que o boletim do TSE tem de mais
denso. O mesmo arquivo que traz os candidatos traz eleitorado apto,
comparecimento, abstenção, brancos, nulos e o par seções totalizadas/total —
tudo isso já normalizado pelo parser e disponível em todos os exporters.

Este documento cobre o que a automação faz com esses números:

- o **mapa do Brasil**, pintado por partido ou por urnas totalizadas;
- a **composição do voto** (válidos, brancos, nulos, abstenção), com a
  geometria do gráfico já calculada;
- o **histórico**, que é o que permite curva de apuração, previsão de
  fechamento e marco de virada.

A arte de referência está em
[`graficos/modelos.html`](../graficos/modelos.html) — seis quadros em palco
16:9, com as medidas em projeto 1920 × 1080 e o nome do campo que alimenta cada
elemento. Abra no navegador antes de desenhar qualquer coisa.

---

## 1. O mapa

### O que sai

Um exporter do tipo `mapa` recebe as 27 unidades da federação como um grupo e
grava dois arquivos:

| Arquivo | Para quê |
|---|---|
| `mapa-presidente.svg` | mapa desenhado e pintado, canvas 1920 × 1080, entra na cena 1:1 |
| `mapa-presidente.json` | os mesmos números por UF, para site, segunda tela e GC que prefere dado a desenho |

O SVG é autocontido: sem script, sem imagem ligada, sem fonte obrigatória. Abre
no navegador, no Illustrator e no DataSource do GC.

### Dois modos

```yaml
exporters:
  mapa_partido:
    tipo: mapa
    modo: partido        # cor do partido de quem lidera cada estado
    destino: dados/saida/mapa
    titulo: "PRESIDENTE - LIDERANCA POR ESTADO"
    rotulo: sigla_pct    # sigla | sigla_pct | sigla_lider
    formatos: [svg, json]

  mapa_urnas:
    tipo: mapa
    modo: apuracao       # intensidade pelo percentual de urnas totalizadas
    destino: dados/saida/mapa
    cor_escala: "#2f97e8"
```

`modo: partido` responde *quem está na frente onde*. `modo: apuracao` responde
*quanto já apurou onde* — é o mapa que enche ao vivo, e o painel lateral traz o
total apurado e as urnas já apuradas praça a praça.

### Ligar as 27 praças

O mapa é um **grupo**, na mesma forma do rodízio: um exporter e uma lista de
alvos.

```yaml
mapas:
  mapa-presidente:
    exporter: mapa_partido
    alvos: [mapa-ac, mapa-al, mapa-am, ...]     # as 27

alvos:
  - { nome: mapa-ac, abrangencia: ac, cargo: 1, limite_candidatos: 2, exporters: [] }
  - { nome: mapa-al, abrangencia: al, cargo: 1, limite_candidatos: 2, exporters: [] }
  # ...
```

Duas escolhas que valem explicação:

- **`exporters: []`** — lista vazia explícita. Essas praças existem só para
  alimentar o mapa; não geram arquivo individual no hot folder.
- **`limite_candidatos: 2`** — o mapa usa 1º e 2º colocado e nada mais. Cortar
  no parser economiza memória e tamanho de JSON vinte e sete vezes.

O `config.recomendado.yaml` já traz esse bloco pronto. Se não for usar o mapa,
apague a seção `mapas` e os alvos `mapa-*`: são 27 requisições por ciclo que
deixam de existir.

### Custo de rede

27 arquivos a mais por ciclo. Com cache condicional ligado (o padrão), a
maioria das respostas volta `304` sem corpo, então o tráfego é pequeno — mas o
número de conexões não é. Se o ciclo começar a estourar o intervalo, suba
`coleta.paralelismo` de 4 para 8 antes de mexer em qualquer outra coisa.

### Exibir num segundo PC (o caminho mais curto)

Há dois jeitos de pôr o mapa no ar, e eles custam coisas muito diferentes:

| | Montar no GC | **Tela num segundo PC** |
|---|---|---|
| O que a arte faz | desenha 27 objetos e amarra a cor de cada um a um campo | nada |
| Exige do GC | cor de objeto vinda de dado, vezes 27 | nada |
| Como entra no switcher | camada do GC | entrada de vídeo, como uma fonte qualquer |
| Risco no D-1 | vínculo errado em 1 dos 27 estados passa despercebido | não existe vínculo para errar |

Se o mapa não precisa compor **por cima** da cena do GC, a segunda opção é a
certa. O desenho já chega pronto; não há conta nem cor para o gerador de
caracteres resolver.

**Como funciona.** Com `tela` na lista de formatos, o exporter grava, ao lado do
SVG, um `mapa-presidente.html`. Essa página mostra o mapa em tela cheia, sem
cursor e sem barra de navegação, e relê o SVG sozinha de 10 em 10 segundos. A
saída de vídeo desse PC entra no switcher como uma fonte comum.

```yaml
exporters:
  mapa_partido:
    tipo: mapa
    formatos: [svg, json, tela]
    tela_intervalo_segundos: 10
```

No PC de exibição:

```bat
TELA-MAPA.bat
TELA-MAPA.bat "\\PC-OPERACAO\gctse\dados\saida\mapa\mapa-presidente.html"
```

O segundo formato é o caso normal: o PC de exibição **não precisa do gctse
instalado**, só precisa enxergar a pasta compartilhada do PC que coleta. O
`.bat` abre Chrome (ou Edge) em modo quiosque, com perfil próprio — assim uma
aba que alguém abrir no navegador de uso comum não derruba o que está no ar.

**Três decisões que só aparecem quando isso está no ar:**

1. **Duas camadas, não um `reload`.** Recarregar a página inteira pisca branco
   por um quadro, e um quadro branco no ar é um erro visível. A imagem nova
   carrega escondida e só aparece quando está inteira — a troca é uma
   dissolvência.
2. **Falha mantém o quadro.** Se a leitura falhar — arquivo sendo trocado,
   pasta de rede oscilando —, o último mapa bom continua no ar. Tela preta por
   causa de um soluço de rede seria pior do que um mapa vinte segundos
   atrasado.
3. **Nada é escrito por cima.** A hora do boletim já está desenhada dentro do
   mapa. Para conferir se a tela está atualizando durante o teste, abra com
   `?debug=1` — aí um rodapé discreto mostra a hora da última troca e o número
   de falhas. Sem o parâmetro, não aparece nada.

**Conferir no ensaio.** Rode `gctse ensaio --duracao 600` num PC e deixe a tela
aberta no outro: o mapa vai encher ao longo de dez minutos. É o teste que prova
a cadeia inteira — coleta, escrita, pasta compartilhada e exibição.

**Escala do Windows.** O `.bat` já passa `--force-device-scale-factor=1`. Sem
isso, um PC com escala em 125% renderiza o mapa menor que a tela e sobra borda.

### E se o mapa precisar compor sobre a cena do GC?

Aí a tela separada não serve, porque ela é uma fonte de vídeo opaca. Duas
saídas:

- **`fundo_transparente: true`** no exporter e o SVG entra como camada no GC,
  com fundo alfa — continua sem vínculo nenhum para montar.
- **Montar no GC pelo JSON**, com os 27 objetos nomeados (`uf-sp`, `uf-pr`…) e
  a cor de cada um amarrada a `estados.SP.cor`. É o caminho que dá controle
  total de animação e o que mais custa para montar e conferir. Antes de
  escolhê-lo, confirme no Castalia se **cor de preenchimento aceita valor vindo
  de campo de dado** — se não aceitar, esse caminho não existe, e a resposta
  volta a ser a tela separada.

### Cores de partido

```yaml
texto:
  cores_partido:
    PVL: "#2f97e8"
    PDR: "#c0392b"
```

A sigla vai em caixa alta. A mesma cor vale para a barra do placar, a tarja e o
mapa — é por ela que o telespectador se orienta entre um bloco e outro.

Partido sem cor configurada recebe uma cor de uma **paleta de reserva**, para o
mapa não sair de uma cor só durante os ensaios. A atribuição é estável dentro
da noite (mesma cor em todos os ciclos), mas não é decisão de arte: defina
`cores_partido` antes do ar. Para desligar a reserva e deixar tudo em
`cor_padrao`, use `paleta_reserva: false` no exporter.

Duas checagens antes de fechar a paleta:

1. cores vizinhas no mapa precisam ser distinguíveis por quem não separa
   vermelho de verde — é 1 em cada 12 homens;
2. o mapa impresso em preto e branco não pode virar um cinza só.

### Praça sem boletim

Sai em cinza (`cor_sem_dado`), com a sigla legível. Buraco no mapa parece erro
de arte; cinza informa que o dado não chegou. Os 27 estados estão sempre
desenhados, do primeiro ao último boletim do dia.

### Rótulo de estado pequeno

DF, SE, AL, PB, RN, PE, ES e RJ não comportam texto dentro do desenho e recebem
rótulo na coluna à direita, com linha de chamada. A lista está em
`LEGENDA_EXTERNA`, em `src/gctse/malha_br.py`.

### Crédito da malha

A geometria vem de [`@svg-maps/brazil`](https://github.com/VictorCazanave/svg-maps),
de Victor Cazanave, sob **Creative Commons Attribution 4.0**. Uso comercial é
permitido; o crédito é obrigatório. O exporter já grava a linha de crédito no
rodapé do SVG — se a arte redesenhar o mapa por cima, mantenha a linha.

---

## 2. Composição do voto: brancos, nulos e abstenção

### Os percentuais

Já vêm prontos em todos os exporters, em versão formatada e numérica:

| Campo | Base | Observação |
|---|---|---|
| `pct_validos` | votos apurados | |
| `pct_brancos` | votos apurados | |
| `pct_nulos` | votos apurados | |
| `pct_brancos_nulos` | votos apurados | a soma, calculada de uma vez — não é a soma de dois arredondados |
| `pct_comparecimento` | eleitorado apto | |
| `pct_abstencao` | eleitorado apto | |

**As duas bases não se misturam.** Válidos, brancos e nulos são medidos sobre
os votos apurados e fecham 100% entre si. Abstenção é medida sobre o eleitorado
apto — quem não foi votar não está dentro dos votos apurados. Pôr os quatro na
mesma rosca produz um gráfico que não fecha, e ninguém percebe no ar.

Quando você quer mesmo os quatro juntos, use `base: eleitorado` na configuração
de geometria: aí a base inteira passa a ser o eleitorado apto e as quatro
fatias fecham 100% corretamente.

### A geometria pronta

Aritmética de circunferência é justamente o que nenhum gerador de caracteres
faz bem. Configure e receba pixels e graus:

```yaml
exporters:
  liveboard_rank:
    composicao:
      trilho_px: 900      # barra empilhada
      rosca_raio: 120     # rosca
      base: apurados      # apurados | eleitorado
```

Campos gerados:

| Campo | O que é |
|---|---|
| `comp_validos_px` | largura da fatia, em pixels |
| `comp_validos_x` | onde a fatia começa — para CG que só move objeto |
| `comp_trilho_px` | largura total |
| `rosca_validos_dash` | `stroke-dasharray` pronto: `"arco resto"` |
| `rosca_validos_offset` | `stroke-dashoffset` — onde o anel começa |
| `rosca_validos_graus` / `rosca_validos_giro` | o mesmo em graus |
| `rosca_circunferencia` | conferência: a soma dos arcos fecha exatamente aqui |

As larguras saem de uma soma **acumulada** arredondada, não de cada pedaço
arredondado por conta própria: a barra fecha exata no trilho e não sobra 1 px
de fundo aparecendo entre duas fatias.

Sem a seção `composicao`, nenhum campo de geometria é gerado — os percentuais
continuam disponíveis.

### Ritmo e reversibilidade

| Campo | O que é |
|---|---|
| `secoes_restantes` | quantas urnas faltam |
| `votos_restantes` | estimativa de votos que faltam apurar, por regra de três |
| `reversivel` | `1` quando a diferença entre 1º e 2º cabe no que falta |
| `diferenca_lider` / `diferenca_pct` | vantagem do 1º sobre o 2º |

`votos_restantes` é estimativa: seção grande e seção pequena não valem igual.
Serve para responder no ar se a diferença ainda é reversível — não para
projetar resultado.

---

## 3. Histórico: a série que os gráficos de evolução exigem

O `estado.json` guarda **só o último** boletim de cada alvo: ele existe para
deduplicar e barrar regressão, e sobrescreve o valor anterior a cada ciclo.
Isso resolve o ar e impede qualquer gráfico de evolução.

O histórico guarda os pontos.

```yaml
coleta:
  historico: true
  arquivo_historico: dados/estado/historico.jsonl
  arquivo_graficos: dados/estado/graficos.json
  pontos_por_grafico: 240
```

- **`historico.jsonl`** — uma linha JSON por boletim publicado, acrescentada no
  fim do arquivo. Formato aberto: Excel, Power BI, pandas e o próprio painel
  leem. São ~700 linhas por alvo num dia de apuração.
- **`graficos.json`** — reescrito a cada ciclo com o que os gráficos precisam:
  série recente, previsão de fechamento e marcos de virada, por alvo.

Só entra no histórico o que foi de fato **publicado** — boletim bloqueado por
fase, descartado por regressão ou abaixo do mínimo não vira ponto. `gctse
ensaio` e `gctse exemplo` escrevem em arquivos próprios: a curva do ensaio não
entra na série que a coordenação vai ler no dia.

### Previsão de fechamento

```json
"projecao": {
  "pct": 84.2,
  "pontos_por_minuto": 1.9,
  "urnas_por_minuto": 8968.0,
  "minutos": 8,
  "previsao": "22:10",
  "totalizada": false
}
```

Regressão linear sobre os últimos 12 pontos. A janela é recente de propósito: a
noite começa rápida e termina arrastada, e uma média do dia inteiro projetaria
um fechamento cedo demais justamente quando o dado importa.

**É projeção de ritmo, não de resultado.** Responde "a que horas as urnas
terminam de ser totalizadas", para decidir escala de equipe, intervalo
comercial e liberação de praça. Não diz nada sobre quem vence, e não deve ir ao
ar como se dissesse.

Quando o ritmo é zero ou negativo — apuração parada, boletim repetido —
`previsao` volta vazia em vez de um horário inventado.

### Marcos de virada

```json
"viradas": [
  {"hora": "20:41", "assumiu": "20", "perdeu": "10", "pct_apurado": 54.3}
]
```

Detectado pela troca do **número** na primeira posição — o número é o
identificador estável; a grafia do nome muda entre boletins. Vira tarja no ar e
retranca no dia seguinte.

### No painel

`dados/estado/painel.html` ganhou duas colunas:

- **Br+Nu** — brancos e nulos somados, sobre os votos apurados;
- **Fecha** — a previsão de 100% no ritmo atual.

---

## 4. Gerar o demonstrativo de arte

```bash
python scripts/gerar_modelos_graficos.py
```

Reescreve `graficos/modelos.html` a partir de
`graficos/modelos.template.html`. A geometria dos estados vem do mesmo módulo
que a automação usa no ar, e os números de cada quadro saem do **mesmo
exporter** que grava o arquivo do GC — se o cálculo mudar, a página muda junto,
em vez de virar um desenho antigo que ninguém lembra de atualizar.

Roda offline, sem rede e sem dado do TSE. O script também regrava
`graficos/exemplo-mapa-partido.svg` e `graficos/exemplo-mapa-urnas.svg` — os
mesmos arquivos que o dia da eleição produz, com dado fictício, para a arte
abrir no vetor e medir sem rodar nada.

Para ver os arquivos reais com dado fictício, incluindo os dois SVGs de mapa:

```bash
gctse exemplo --pasta exemplos
```

---

## 5. Ordem sugerida de implantação

1. **Composição do voto.** O dado já chega; é só exibir. Zero custo de rede.
2. **Mapa modo `apuracao`.** Não depende de decisão de arte — a escala de cor é
   uma só.
3. **Mapa modo `partido`.** Exige a paleta fechada com a arte.
4. **Curva e previsão.** Exige o histórico rodando desde o começo da noite; se
   ligar às 21h, a série começa às 21h.
5. **Mapa municipal de uma praça.** O TSE publica por município
   (`pr75353`); o Paraná são 399 alvos. Rode com paralelismo maior e avalie o
   custo antes.
