# Kit de teste — qual formato o LiveBoard amarra melhor

O **mesmo boletim**, com os **mesmos nomes de campo**, nos três formatos que o
DataSource do LiveBoard aceita. O teste leva uns 5 minutos e decide a
configuração de toda a cobertura.

| Arquivo | Type no DataSource |
|---|---|
| `governador-pr-json.json` | JSON |
| `governador-pr-xml.xml` | XML |
| `governador-pr-csv.csv` (+ `-resumo.csv`) | CSV — separador `;`, delimitador `"`, nomes na primeira linha |

## Como testar

Para cada formato, crie um DataSource e tente amarrar **estes quatro objetos**:

1. **Texto** → nome do 1º colocado
2. **Texto** → percentual do 1º colocado
3. **Largura ou escala de um retângulo** → a barra do 1º colocado
4. **Visibilidade** de um objeto → o campo `visivel` do 4º slot (deve estar
   invisível, porque só há 3 candidatos)

O item 3 é o que decide. Se um formato não permitir amarrar geometria, ele está
fora, por mais confortável que seja nos outros três.

## Onde está cada campo

| | JSON | XML | CSV |
|---|---|---|---|
| nome do 1º | `candidatos[0].nome` | `/dados/candidatos/candidato[1]/nome` | coluna `nome`, linha 2 |
| percentual do 1º | `candidatos[0].percentual` | `.../percentual` | coluna `percentual` |
| barra do 1º | `candidatos[0].barra_px` | `.../barra_px` | coluna `barra_px` |
| visível do 4º | `candidatos[3].visivel` | `candidato[4]/visivel` | coluna `visivel`, linha 5 |

No JSON há também o bloco `plano`, com tudo achatado (`plano.cand1_nome`,
`plano.cand1_barra_px`). Se o LiveBoard não navegar bem por índice de array,
use o `plano` — é a mesma informação, com chave única.

## Campos de geometria da barra

Os quatro descrevem a mesma barra, para um trilho de **420 px**. Use o que o
Castalia aceitar:

| Campo | Exemplo | Para um objeto que… |
|---|---|---|
| `barra_px` | `123` | tem largura |
| `barra_resto_px` | `297` | só pode ser movido (máscara) |
| `barra_esc` | `0.2928` | tem escala |
| `barra_idx` | `29` | troca de quadro |

Detalhes em [`docs/CASTALIA.md`](../../docs/CASTALIA.md).

## Atenção

Dados fictícios, fase `S`. É material de teste — não vai ao ar.
