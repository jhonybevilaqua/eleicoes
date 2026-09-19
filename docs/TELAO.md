# Telão — sistema de exibição em tela cheia

## O que é

Um programa **separado do gctse**. O gctse alimenta as tarjas do gerador de
caracteres; o telão desenha telas inteiras de 1920 × 1080 e as entrega prontas
para um PC de exibição, cuja saída de vídeo entra no switcher como uma fonte
qualquer.

Os dois não se falam: executável próprio (`telao.exe`), configuração própria
(`telao.yaml`), pasta própria, coleta própria. Dar problema num não derruba o
outro, e a operação do GC — que no dia estará ocupada com as tarjas — não
divide atenção com o telão.

```
PC que coleta                          PC de exibição
┌─────────────────────────┐            ┌───────────────────┐
│ TELAO-COLETA.bat        │  pasta     │ TELAO-TELA.bat    │
│   lê o TSE, desenha     │  comparti- │   Chrome quiosque │──► switcher
│   as telas ────────────┼─ lhada ───►│   tela cheia      │
│ TELAO-MESA.bat          │            └───────────────────┘
│   você escolhe a tela   │
└─────────────────────────┘
```

O PC de exibição **não precisa de nada instalado**. Só precisa enxergar a pasta
compartilhada.

## As telas

| id | O que mostra |
|---|---|
| `lideranca` | **Liderança por estado** — o mapa do Brasil pintado pela cor do partido de quem lidera cada UF, com a contagem de estados por partido e a composição do voto |
| `estados` | **Como cada estado votou** — o mesmo mapa, com as 27 UFs listadas ao lado: partido vencedor e percentual |
| `como-votou` | **Como o Brasil votou** — válidos, brancos e nulos numa rosca; abstenção fora dela |
| `apuracao-nacional` | **Apuração nacional** — o contador de urnas do país, em número grande |
| `apuracao-estados` | **Apuração por estado** — o mapa pintado pelo percentual de urnas totalizadas, com as praças mais atrasadas |
| `placar` | os candidatos, com barra, percentual e votos |

Apague da config o que não for usar: menos tela é menos coisa para escolher
errado no meio do bloco.

## Instalar e configurar

O telão vem dentro do mesmo pacote Windows, na subpasta `TELAO\`. Não instala
nada; para desinstalar, apague a pasta.

```yaml
# telao.yaml
tse:
  ciclo: ele2026
  pleito: "000"     # telao descobrir
  eleicao: "000"

apuracao:
  cargo: 1          # 1 Presidente | 3 Governador | 5 Senador
  estados: todos    # ou uma lista: [pr, sc, rs, sp]
```

Você diz o **cargo**; as 28 praças (nacional + 27 UFs) saem sozinhas. Não há
lista de alvos para montar — esse é o trabalho que a config do gctse faz e que
aqui não faz sentido, porque o telão sempre quer a mesma coisa.

Listar estados serve para emissora regional: o mapa continua inteiro, com as
praças de fora em cinza, e a coleta cai de 28 requisições por ciclo para o que
você realmente exibe.

```bash
telao descobrir     # pega os códigos do pleito no TSE
telao validar       # confere tudo antes do ar
telao ensaio        # treina com dado fictício, sem tocar o TSE
telao rodar         # no ar
```

## No dia

**No PC que coleta:**

```bat
TELAO-COLETA.bat     lê o TSE e redesenha as telas. Reinicia sozinho se cair.
TELAO-MESA.bat       janela com um botão por tela: você clica, ela entra no ar.
```

**No PC de exibição:**

```bat
TELAO-TELA.bat "\\PC-OPERACAO\gctse\TELAO\telao\index.html"
```

Abre Chrome (ou Edge) em modo quiosque, com perfil próprio — uma aba que
alguém abrir no navegador de uso comum não derruba o que está no ar.

### Quem escolhe a tela

| | Como | Quando usar |
|---|---|---|
| **Mesa** | `TELAO-MESA.bat` | o normal — quem dirige fica no PC de operação |
| **Linha de comando** | `telao no-ar como-votou` | atalho na área de trabalho, script |
| **Teclado da própria tela** | `1`–`6`, setas | quem opera está sentado no PC de exibição |

A exibição obedece a mesa em cerca de **1 segundo**. O teclado assume o comando
quando usado; `M` devolve para a mesa. `R` liga e desliga o rodízio automático
(20 s por tela), útil em bloco sem apresentador. `D` mostra um rodapé discreto
com a hora da última troca e o número de falhas — some do ar quando desligado.

**Fechar a mesa não tira nada do ar.** A seleção é um arquivo; se a mesa
fechar, a última tela escolhida continua. Não há servidor, não há porta aberta,
não há conexão para cair no meio da transmissão.

## Cores de partido

É o que pinta cada estado no mapa de liderança — a pergunta principal deste
sistema.

```yaml
aparencia:
  cores_partido:
    PVL: "#2f97e8"
    PDR: "#c0392b"
```

**Ajustar com a arte antes do D-7.** Duas regras que evitam retrabalho:

1. a mesma sigla tem a mesma cor em toda a programação, do placar ao mapa —
   é por ela que o telespectador se orienta entre um bloco e outro;
2. partidos vizinhos no mapa precisam ser distinguíveis no ar, inclusive por
   quem não separa vermelho de verde (1 em cada 12 homens). Imprima o mapa em
   preto e branco: se dois estados vizinhos viram o mesmo cinza, o
   telespectador também perde.

Partido sem cor definida recebe uma da paleta de reserva, para o mapa não sair
de uma cor só durante os ensaios. Serve para ensaiar, não é decisão de arte.

## As travas continuam valendo

O telão coleta por conta própria, então as duas travas do gctse foram
repetidas aqui — com o mesmo critério e com teste próprio:

1. **Fase.** O TSE publica simulados nos mesmos caminhos antes do pleito.
   Boletim fora da fase `O` é descartado, então um simulado não vira tela cheia
   com cara de resultado. (`seguranca.bloquear_nao_oficial`)
2. **Regressão.** A CDN pode servir cópia antiga de um nó diferente. Boletim
   com hora de geração anterior à última aceita é descartado: o número no telão
   não anda para trás. (`seguranca.bloquear_regressao`)

Não desligue nenhuma das duas em produção.

## Decisões que só aparecem no ar

**Não pisca.** Recarregar a página inteira dá um quadro branco, e quadro branco
no ar é erro visível. A imagem nova carrega escondida e só assume quando está
completa — a troca é dissolvência.

**Falha mantém o quadro.** Se a leitura falhar (arquivo sendo trocado, pasta de
rede oscilando), a última tela boa continua no ar. Tela preta por soluço de
rede seria pior do que uma tela vinte segundos atrasada.

**Sem boletim não é tela preta.** Praça que ainda não publicou gera uma tela
dizendo "aguardando boletim", e no mapa o estado fica cinza com a sigla
legível. Buraco no mapa parece erro de arte; preto parece cabo solto.

**Dois relógios, não um.** A exibição relê a *seleção* a cada segundo — quem
clica na mesa espera a tela entrar agora — e o *desenho* no intervalo
configurado, porque o SVG só muda quando chega boletim novo.

**`<script>`, não `fetch`.** O navegador bloqueia `fetch` **e**
`XMLHttpRequest` em `file://`, inclusive para um arquivo vizinho. Por isso a
seleção e a lista de telas são gravadas também como `.js`, que carregam sem
esse bloqueio. Os `.json` continuam para a mesa e para o monitoramento.

**Apuração nacional soma UFs só enquanto precisa.** Quando o arquivo nacional
do TSE existe, ele manda — é o próprio TSE somando. A soma das UFs só entra
antes disso, e a tela diz "soma das praças" para ninguém ler um parcial como
total oficial.

## O que o telão compartilha com o gctse

A **biblioteca** de leitura do TSE: o cliente HTTP com cache condicional, o
parser das abreviações do boletim, a malha do Brasil e o desenho do mapa.

Isso é deliberado. Reescrever aqui significaria manter duas cópias das travas
que impedem um simulado de ir ao ar e, no dia em que o TSE mudar uma
abreviação, corrigir uma e esquecer a outra. Pior: o mapa da tarja e o mapa do
telão poderiam discordar sobre quem venceu num estado, ao vivo, no mesmo bloco.

O que **não** é compartilhado: configuração, pasta de saída, processo,
executável e ciclo de coleta. Você pode rodar o telão num PC onde o gctse nunca
foi aberto.

## Testar antes do dia

```bash
telao ensaio --duracao 900
```

Deixe o `TELAO-TELA.bat` aberto no outro PC e a mesa aberta no primeiro. Em
quinze minutos você vê a apuração inteira acontecer: o mapa se pintando, o
placar virando, o contador subindo. É o teste que prova a cadeia toda — coleta,
desenho, pasta compartilhada, exibição e mesa.

As telas do ensaio saem marcadas **PARCIAL — NÃO OFICIAL**, porque o simulador
gera fase `S`. É a mesma trava que impede um simulado do TSE de ir ao ar.

Para gerar as telas uma vez só, sem loop — útil para a arte conferir:

```bash
telao exemplo --pasta telas --progresso 63
```

## Limites conhecidos

**A tela é uma fonte de vídeo opaca.** Ela não compõe por cima da cena do GC.
Se algum quadro precisar entrar sobre imagem, isso é trabalho do gctse (o
exporter de mapa tem `fundo_transparente`), não do telão.

**Uma tela por vez, por PC.** Para duas telas simultâneas, rode dois
`TELAO-TELA.bat` em dois PCs ou duas saídas de vídeo: cada um obedece à mesma
mesa.

**Fonte.** O SVG pede Barlow Condensed e cai em Arial Narrow quando ela não
está instalada. Instale a fonte no PC de exibição para o resultado bater com a
arte, ou troque em `aparencia.fonte`.

**Um cargo por vez.** `apuracao.cargo` vale para todas as telas. Para exibir
presidente e governador no mesmo bloco, rode duas cópias do telão em pastas
diferentes, cada uma com seu `telao.yaml`.
