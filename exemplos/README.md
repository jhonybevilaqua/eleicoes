# Arquivos de exemplo

Conteúdo **fictício**, gerado pelo simulador com a apuração travada em 63%,
usando `config/config.recomendado.yaml`. Serve para o time montar e amarrar a
cena do LiveBoard agora, meses antes de o TSE publicar qualquer coisa.

Os nomes de campo, a estrutura e os caminhos são **exatamente** os do dia da
eleição — só o conteúdo é inventado. Quem amarrar a cena contra estes arquivos
não precisa refazer nada depois.

Para regerar (por exemplo, depois de mudar as listas de campos):

```bash
gctse -c config/config.recomendado.yaml exemplo --pasta exemplos
gctse -c config/config.recomendado.yaml exemplo --progresso 100   # cena de fechamento
```

## O que tem aqui

| Pasta | O quê |
|---|---|
| `liveboard_fixo/` | JSON com `ordem: fixa` — a posição 1 é sempre o mesmo candidato. Para cena com foto ou cor por posição. |
| `liveboard_rank/` | JSON com `ordem: colocacao` — a posição 1 é sempre o 1º colocado. Para placar/ranking. |
| `web_json/` | modelo completo, para site e segunda tela. |
| `mapa/` | qual caminho do JSON guarda qual campo, um CSV por cena. **Amarre por aqui, não por tentativa e erro.** |

## Atenção

Os arquivos trazem `fase: "S"` e `selo: "PARCIAL - NAO OFICIAL"`. São dados de
ensaio — os nomes de candidato são inventados de propósito, para ninguém
confundir teste com apuração real. **Não use no ar.**
