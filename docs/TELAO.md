# Telão — gráficos de tela cheia num PC de exibição

## O que é

Um segundo PC mostrando gráficos em tela cheia, alimentados pelo boletim do
TSE, com a saída de vídeo entrando no switcher como uma fonte qualquer.

**O GC não participa.** Cada quadro sai daqui como um SVG 1920 × 1080 já
desenhado e pintado, reescrito a cada boletim. Não há cena para montar, não há
vínculo para conferir no D-1, não há conta para o gerador de caracteres
resolver — e, principalmente, não há concorrência com a operação do GC, que no
dia estará ocupada com as tarjas.

```
PC que coleta                          PC de exibição
┌───────────────────┐                  ┌───────────────────┐
│ gctse rodar       │   pasta          │ TELAO.bat         │
│   ├─ tarjas → GC  │   compartilhada  │   Chrome quiosque │──► switcher
│   └─ telão ───────┼─────────────────►│   tela cheia      │
│ gctse mesa        │                  └───────────────────┘
│   (escolhe)       │
└───────────────────┘
```

O PC de exibição **não precisa do gctse instalado**. Só precisa enxergar a
pasta compartilhada.

## Os quadros

| tipo | O que mostra | Precisa de |
|---|---|---|
| `placar` | candidatos, barra, percentual e votos | um alvo |
| `composicao` | rosca de válidos/brancos/nulos + abstenção | um alvo |
| `contador` | urnas totalizadas, número grande | um alvo |
| `curva` | ritmo da apuração e previsão de fechamento | histórico ligado |
| `mapa` | o mapa do Brasil já pintado | um grupo de `mapas` |

## Configurar

```yaml
telao:
  ativo: true
  destino: dados/saida/telao
  intervalo_segundos: 8

  quadros:
    - id: presidente
      tipo: placar
      alvo: presidente-br
      titulo: "PRESIDENTE - BRASIL"
      limite_candidatos: 6

    - id: mapa-partido
      tipo: mapa
      mapa: mapa-presidente
      titulo: "MAPA - LIDERANCA POR ESTADO"

    - id: composicao
      tipo: composicao
      alvo: presidente-br
      titulo: "COMO O BRASIL VOTOU"
```

O `id` é o nome do arquivo (`presidente.svg`) e a chave que a mesa usa. O
`titulo` é o que aparece no quadro e na lista da mesa.

`gctse validar` acusa quadro apontando para alvo ou mapa que não existe. Quadro
com tipo desconhecido é descartado com aviso no log, em vez de impedir o
sistema de subir — um erro de digitação num quadro não pode derrubar a
operação no dia da eleição.

## No dia

**No PC que coleta:**

```bat
INICIAR.bat        já grava o telão junto com as tarjas
MESA.bat           janela para escolher o quadro que vai ao ar
```

**No PC de exibição:**

```bat
TELAO.bat "\\PC-OPERACAO\gctse\dados\saida\telao\index.html"
```

Abre Chrome (ou Edge) em modo quiosque, com perfil próprio — uma aba que
alguém abrir no navegador de uso comum não derruba o que está no ar.

### Quem escolhe o quadro

Três caminhos, e eles convivem:

| | Como | Quando usar |
|---|---|---|
| **Mesa** | `MESA.bat`, um botão por quadro | o normal — quem dirige fica no PC de operação |
| **Linha de comando** | `gctse no-ar composicao` | atalho na área de trabalho, script, agendador |
| **Teclado da própria tela** | `1`–`9`, setas | quem opera está sentado no PC de exibição |

A tela obedece a mesa em cerca de **1 segundo**. O teclado assume o comando
quando usado; `M` devolve o comando para a mesa. `R` liga e desliga o rodízio
automático (20 s por quadro), útil em bloco sem apresentador. `D` mostra um
rodapé discreto com a hora da última troca e o número de falhas — para
conferência, some do ar quando desligado.

**Fechar a mesa não tira nada do ar.** A seleção é um arquivo; se a mesa
fechar, o último quadro escolhido continua. Não há servidor, não há porta
aberta, não há conexão para cair no meio da transmissão.

## Decisões que só aparecem no ar

**Não pisca.** Recarregar a página inteira dá um quadro branco, e quadro branco
no ar é erro visível. A imagem nova carrega escondida e só assume quando está
completa — a troca é dissolvência.

**Falha mantém o quadro.** Se a leitura falhar (arquivo sendo trocado, pasta de
rede oscilando), o último quadro bom continua no ar. Tela preta por soluço de
rede seria pior do que um quadro vinte segundos atrasado.

**Sem boletim não é tela preta.** Praça que ainda não publicou gera um quadro
dizendo "aguardando boletim". Preto parece cabo solto e manda o operador
procurar defeito no lugar errado.

**Dois relógios, não um.** A tela relê a *seleção* a cada segundo — quem clica
na mesa espera o quadro entrar agora — e o *desenho* no intervalo configurado,
porque o SVG só muda quando chega boletim novo.

**`<script>`, não `fetch`.** O navegador bloqueia `fetch` **e**
`XMLHttpRequest` em `file://`, inclusive para um arquivo vizinho. Por isso o
telão grava `quadros.js` e `no-ar.js` além dos `.json`: a tela lê os `.js`, que
carregam sem esse bloqueio. Os `.json` continuam existindo para a mesa e para o
monitoramento.

**Série curta não vira previsão.** No início da noite o TSE publica em rajada —
vários boletins em poucos segundos. Uma regressão sobre isso devolveria ritmos
absurdos e um horário de fechamento sem sentido, então o quadro de curva só
desenha depois de 5 minutos de série (`minimo_minutos`).

**Cor por candidato.** No placar, cair na `cor_padrao` deixaria todas as barras
iguais, e o telespectador lê a cor antes de ler o nome. Partido sem cor em
`texto.cores_partido` recebe uma da paleta de reserva. Para voltar à barra
neutra, `telao.paleta_reserva: false`.

## Testar antes do dia

```bash
gctse ensaio --duracao 900
```

Deixe o `TELAO.bat` aberto no outro PC e a mesa aberta no primeiro. Em quinze
minutos você vê a apuração inteira acontecer: o placar virando, o mapa
enchendo, a curva se formando. É o teste que prova a cadeia toda — coleta,
desenho, pasta compartilhada, exibição e mesa.

Os quadros do ensaio saem marcados com o selo **PARCIAL — NÃO OFICIAL**, porque
o simulador gera fase `S`. É a mesma trava que impede um simulado do TSE de ir
ao ar com cara de resultado.

## Limites conhecidos

**A tela é uma fonte de vídeo opaca.** Ela não compõe por cima da cena do GC.
Se algum quadro precisar entrar sobre imagem, use `fundo_transparente: true` no
exporter de mapa e entre como camada no GC — ou monte aquele quadro específico
no GC pelo JSON.

**Um PC de exibição, um quadro por vez.** Para dois quadros simultâneos em
telas diferentes, rode dois `TELAO.bat` em dois PCs (ou duas saídas de vídeo):
cada um obedece à mesma mesa. Para uma tela fixa só no mapa, sem mesa, use a
tela própria do exporter de mapa (`formatos: [svg, json, tela]`).

**Fonte.** O SVG pede Barlow Condensed e cai em Arial Narrow quando ela não
está instalada. Instale a fonte no PC de exibição para o resultado bater com a
arte, ou troque em `telao.fonte`.
