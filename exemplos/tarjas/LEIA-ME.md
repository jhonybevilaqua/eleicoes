# As três tarjas — arquivos para assinar no LiveBoard

Um arquivo JSON por tarja, no formato **raso**: sem estrutura aninhada, sem
índice de array. Cada item da cena aponta para uma chave única, escrita
exatamente como aparece no arquivo. É o formato com menos chance de vínculo
errado.

| Tarja | Arquivo | Slots |
|---|---|---|
| 1 · Presidente, com foto | `tarja_presidente/tarja-presidente.json` | 2 |
| 2 · Senador e governador | `tarja_majoritaria/tarja-{alvo}.json` | 2 |
| 3 · Rodízio de estados | `tarja_rodizio/tarja-rodizio.json` | 10 praças |

Os mapas de vínculo das tarjas 1 e 2 estão em `mapa/` — um CSV por cena, com
uma linha por campo. Abra numa planilha e vá marcando conforme assina.

---

## Tarja 1 · Presidente

```json
{
  "cargo": "PRESIDENTE",
  "abrangencia": "BRASIL",
  "apuracao_pct": "63,00%",
  "selo": "PARCIAL - NAO OFICIAL",
  "hora_atualizacao": "20:41",
  "cand1_visivel": "1",
  "cand1_nome": "MARIA ANDRADE",
  "cand1_partido": "PVL",
  "cand1_foto": "fotos/10.png",
  "cand1_percentual": "47,82%",
  "cand1_barra_px": 143,
  "cand1_cor": "#4a90d9",
  "cand1_eleito": "0",
  "cand2_…": "…"
}
```

**Treze campos por assinar.** Cinco do cabeçalho, oito por candidato.

| Item da cena | Chave |
|---|---|
| "APURAÇÃO / **PRESIDENTE**" | `cargo` |
| Bloco escuro "**BRASIL**" | `abrangencia` |
| Chip "URNAS APURADAS **63,00%**" | `apuracao_pct` |
| "PARCIAL — NÃO OFICIAL" (texto **e** visibilidade) | `selo` |
| Hora no rodapé | `hora_atualizacao` |
| Foto do 1º | `cand1_foto` |
| Nome do 1º | `cand1_nome` |
| Sigla do 1º | `cand1_partido` |
| Percentual do 1º | `cand1_percentual` |
| **Largura da barra do 1º** | `cand1_barra_px` |
| Cor da barra do 1º | `cand1_cor` |
| Selo ELEITO (visibilidade) | `cand1_eleito` |
| Bloco inteiro do 1º (visibilidade) | `cand1_visivel` |

E os mesmos oito com prefixo `cand2_`.

---

## Tarja 2 · Senador e governador

Mesma estrutura, **sem `foto`**. É uma cena só para os dois cargos — o que muda
é o arquivo de origem:

- governador do Paraná → `tarja-gov-pr.json`
- senador do Paraná → `tarja-sen-pr.json`

O campo `cargo` já vem preenchido com "GOVERNADOR" ou "SENADOR", então a cena
não precisa saber qual é.

---

## Tarja 3 · Rodízio

Esta é uma **lista**, não um objeto raso — é o que permite o GC rodar as praças.

```json
{
  "rodizio": "estados", "total": 10, "com_dado": 10,
  "pracas": [
    {"ordem": 1, "visivel": "1", "praca": "PARANÁ", "cargo": "GOVERNADOR",
     "apuracao_pct": "63,00%", "selo": "PARCIAL - NAO OFICIAL",
     "cand1_nome": "MARIA AND", "cand1_partido": "PVL", "cand1_percentual": "47,82%",
     "cand2_nome": "ROBERTO L", "cand2_partido": "PDR", "cand2_percentual": "41,15%"}
  ]
}
```

Aponte o DataSource para `pracas` e assine os campos **dentro do registro** —
o GC avança de registro em registro. São 14 campos, e valem para as 10 praças.

**A lista tem sempre 10 registros.** Praça sem boletim entra com `visivel = 0`.
Amarre a visibilidade do take a esse campo e ela é pulada sozinha, sem buraco
no rodízio.

**O nome trunca cedo aqui** (limite de 14 caracteres, porque a tarja é
estreita). Afira contra a arte real e ajuste em `config.tarjas.yaml`:

```yaml
  tarja_rodizio:
    texto:
      limites: {nome: 14}
```

---

## Como assinar sem errar

1. Abra o CSV de `mapa/` numa planilha, ao lado do LiveBoard.
2. Assine **um campo por vez**, marcando a linha no CSV.
3. Comece pelos cinco do cabeçalho — se eles aparecerem, o DataSource está
   certo e o resto é repetição.
4. Assine `cand1_*` inteiro e confira na tela **antes** de fazer `cand2_*`.
   Errar o padrão no primeiro e repetir no segundo dobra o retrabalho.
5. Deixe `cand1_barra_px` por último: é o que dá mais trabalho e o que você quer
   testar com calma.

## Depois de assinar

Troque o valor no JSON à mão (por exemplo `"cand1_percentual": "99,99%"`) e veja
a cena reagir. É o teste mais rápido de que o vínculo pegou — e não depende do
TSE nem de rodar o sistema.

## Atenção

Dados fictícios, fase `S`. Material de montagem — não vai ao ar.
