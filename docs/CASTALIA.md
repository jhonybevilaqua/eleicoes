# Fazer o gráfico acompanhar o percentual — ClassX Castalia

## O problema, e por que ele fica fácil

A dificuldade que você descreveu — "fazer o gráfico acompanhar o número da
porcentagem" — quase sempre vem de pedir **aritmética ao gerador de
caracteres**. Se o CG recebe `47,82%` e precisa converter isso em largura de
barra, você fica dependente de ele ter expressão matemática, e de ela entender
vírgula decimal em pt-BR.

A saída é não pedir conta nenhuma. A automação já sabe o comprimento do trilho
no seu projeto, então ela entrega **a largura pronta, em pixels**. O CG só
aplica um número.

```yaml
exporters:
  liveboard_presidente:
    tipo: classx
    barra:
      trilho_px: 420      # comprimento do trilho na sua cena
      minimo_px: 6        # traço mínimo, para 0,1% não sumir
      base: validos       # validos | lider
      passos: 100         # granularidade do índice de quadro
```

Com isso, cada candidato passa a trazer:

| Campo | O que é | Para que serve |
|---|---|---|
| `barra_px` | largura da barra em pixels do projeto | CG que redimensiona um retângulo |
| `barra_resto_px` | o que sobra do trilho (`trilho − barra_px`) | CG que só **move** objeto |
| `barra_esc` | escala de 0 a 1, com ponto decimal (`0.4782`) | CG que faz *scale* de objeto |
| `barra_idx` | inteiro de 0 a `passos` | CG que só troca quadro/imagem |
| `barra_trilho_px` | o comprimento do trilho | conferência |
| `barra_pct` | percentual já normalizado por `base` | conferência |

Todos os cinco descrevem **a mesma barra**. Você usa o que o Castalia aceitar.

---

## Quatro estratégias, da que exige menos do CG para a que exige mais

### A · Largura direta — `barra_px`

O objeto da barra tem `width` amarrado a `barra_px`, ancorado à esquerda.
É a mais simples e a que menos pode dar errado. **Comece tentando esta.**

Requisito no Castalia: aceitar um campo de dado numérico na largura de um
objeto.

### B · Escala — `barra_esc`

A barra é desenhada no comprimento total do trilho e o objeto recebe
`scaleX = barra_esc`, com o ponto de ancoragem à esquerda.

Requisito: aceitar dado numérico na escala. Atenção ao ponto de ancoragem — se
ficar no centro, a barra cresce para os dois lados.

### C · Máscara móvel — `barra_resto_px`

Funciona em CG que **não redimensiona nada**, só move objeto. A barra cheia é
uma imagem estática; por cima dela, um retângulo da cor do fundo, com a largura
do trilho, posicionado em `x = fim_do_trilho − barra_resto_px`. Ele cobre o
pedaço que não foi conquistado.

É o truque clássico de broadcast e sobrevive a qualquer limitação de CG. Exige
que a cor do retângulo case exatamente com o fundo — se o fundo for gradiente,
use uma máscara/crop em vez de um retângulo opaco.

### D · Sprite de quadros — `barra_idx`

Para CG que só sabe trocar imagem. Você gera 101 PNGs (`barra_000.png` a
`barra_100.png`) e o campo de imagem recebe `barra_{barra_idx}.png`. Grosseiro,
pesado no acervo, mas funciona em absolutamente qualquer sistema.

Reduza `passos` para 20 ou 50 se 101 arquivos for demais — a diferença no ar é
imperceptível.

### E · Último recurso — o CG faz a conta

Só se nenhuma das anteriores servir. Use `percentual_num` (`47.82`, com ponto)
e **nunca** `percentual` (`47,82%`, texto pt-BR com vírgula e símbolo).

---

## O que confirmar no Castalia antes de decidir

Não conheço o interior do Castalia a ponto de te dar o caminho de menu, e
prefiro dizer isso a te mandar procurar um botão que talvez não exista. Estas
são as perguntas que decidem a estratégia — dá para respondê-las abrindo o
software:

1. Um objeto aceita **largura** vinda de um campo de dado? → estratégia **A**
2. Aceita **escala**? Onde fica o ponto de ancoragem? → **B**
3. Aceita **posição X**? → **C**
4. Aceita **caminho de imagem** montado com um campo? → **D**
5. Ele tem expressão matemática? Ela entende `47.82` com ponto? → **E**
6. Quando o dado muda, ele **anima** a transição ou salta? Dá para ajustar a
   duração?

Me diga as respostas e eu escrevo a receita fechada para a sua cena.

---

## Armadilhas que custam caro no ar

**Vírgula decimal.** `barra_esc` sai com ponto (`0.4782`) de propósito. Se o
Castalia interpretar `0,4782` como zero, a barra some — e some em silêncio.

**Proporcional some.** Em deputado o 1º colocado fica entre 2% e 5%; uma barra
sobre o total viraria um traço de 4px. Use `base: lider`, que faz o primeiro
colocado valer 100% e os demais proporcionais a ele. O **número** continua
mostrando o percentual real — só a barra é que é relativa.

**O 0,1% que desaparece.** `minimo_px` garante um traço visível para quem tem
voto, mas não se aplica a quem tem zero — candidato zerado fica com barra 0,
como deve ser.

**Número e barra têm que concordar.** Os dois vêm do mesmo `percentual` do
mesmo boletim, então já concordam. O risco é a cena amarrar o número a um alvo
e a barra a outro. Confira no ensaio.

**Animação × intervalo de coleta.** O sistema publica a cada 20 s. Se o CG
animar a transição da barra em 2 s, tudo bem. Se animar em 15 s, a barra ainda
está andando quando chega o boletim seguinte e nunca assenta.

---

## Como testar isso hoje

Não precisa esperar a apuração:

```bash
gctse ensaio --duracao 600      # placar se mexendo por 10 minutos
gctse exemplo --progresso 5     # começo da apuração, barras curtas
gctse exemplo --progresso 100   # fechamento
```

E, para um valor específico, edite o JSON de exemplo à mão e veja a cena
reagir — é o teste mais rápido para conferir se o vínculo pegou.
