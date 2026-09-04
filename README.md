# gctse — Apuração TSE → GC

Automação que lê os boletins de apuração publicados pelo TSE, normaliza os
dados e entrega no formato que o gerador de caracteres da emissora consome
(XML, CSV, JSON, tab fields, templateData ou POST HTTP).

Feito para operação de transmissão: roda sem operador, não coloca dado não
oficial no ar, não deixa o placar andar para trás e continua no ar com o
último boletim válido quando a rede oscila.

```
TSE (JSON)  ──►  coleta  ──►  normalização  ──►  guardas  ──►  exporters  ──►  GC
                (ETag,          (modelo            (fase,       (XML/CSV/       (hot folder
                 retry)          único)             ordem,       JSON/HTTP)      ou API)
                                                    dedupe)
```

## Instalação

**Windows (PC de operação)**

```bat
scripts\instalar.bat
```

**Linux**

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -e .
cp config/config.example.yaml config/config.yaml
```

Requisito: Python 3.9 ou superior.

## Primeiros passos

```bash
gctse validar                 # confere a configuração e mostra as URLs montadas
gctse descobrir               # lista os pleitos publicados pelo TSE (pega os códigos)
gctse inspecionar --abrangencia br --cargo 1   # mostra as chaves reais do arquivo
gctse celulas                 # mapa de células para amarrar a cena (ClassX)
gctse ensaio --duracao 600    # simula uma apuração completa em 10 min
gctse uma-vez                 # um único ciclo (bom para agendador)
gctse rodar                   # operação contínua
```

No Windows, sem ativar a venv: `.venv\Scripts\python.exe -m gctse rodar`.

## Configuração

Tudo fica em `config/config.yaml` (modelo comentado em
`config/config.example.yaml`). As quatro seções que você mais vai mexer:

| Seção | Para quê |
|---|---|
| `tse` | códigos do pleito e padrões de URL |
| `alvos` | quais abrangências × cargos alimentam o GC |
| `exporters` | formato, pasta e encoding de cada saída |
| `texto` | caixa alta, limite de caracteres, formato de número |

**Alvo** é um par abrangência × cargo. Abrangência é `br`, a sigla da UF
(`pr`) ou UF + código TSE do município (`pr75353`). Cargos: 1 Presidente,
3 Governador, 5 Senador, 6 Dep. Federal, 7 Dep. Estadual, 8 Dep. Distrital,
11 Prefeito, 13 Vereador.

```yaml
alvos:
  - nome: governador-pr
    abrangencia: pr
    cargo: 3
    limite_candidatos: 6
    exporters: [gc_xml, gc_csv]
```

## Exporters disponíveis

| tipo | Saída | Uso típico |
|---|---|---|
| `classx` | CSV de grade fixa + mapa de células | **ClassX LiveBoard** |
| `xml` | XML (perfis `generico`, `tabular`, `atributos`) | GC com data linkage, Chyron, Viz Pilot |
| `csv` | CSV/TSV, layout `linhas` ou `largo` | Ross XPression DataLinq, Chyron, planilhas |
| `json` | JSON (`completo`, `gc`, `largo`, `bruto`) | GC web, segunda tela, site |
| `casparcg` | `templateData` XML + JSON | CasparCG |
| `viz_tab` | texto com TAB | Viz Trio (import de tab fields) |
| `http` | POST/PUT JSON | API do GC, broker, Power Automate/Teams |

Cada exporter tem `destino`, `encoding` e `nome_arquivo` próprios, então dá
para escrever ao mesmo tempo no hot folder do GC, na pasta do web e num
webhook. Detalhes e exemplos por marca em [`docs/GC-INTEGRACAO.md`](docs/GC-INTEGRACAO.md).

**ClassX LiveBoard**: o exporter `classx` gera CSV de geometria fixa — sempre
o mesmo número de linhas e colunas, do primeiro ao último boletim — para que o
vínculo por célula nunca leia o campo errado. `gctse celulas` imprime o mapa
de qual célula guarda qual campo, para amarrar a cena sem adivinhar.

## Guardas de segurança no ar

Quatro travas que existem para evitar erro em transmissão ao vivo:

1. **Fase não oficial bloqueada** — o TSE publica simulados antes do pleito
   (fase `S`). Boletim que não estiver em fase `O` é descartado, então um
   simulado não vira placar real. (`seguranca.bloquear_nao_oficial`)
2. **Anti-regressão** — a CDN do TSE pode servir uma cópia antiga. Boletim com
   hora de geração anterior à já publicada é descartado: o placar não anda
   para trás no ar. (`seguranca.bloquear_regressao`)
3. **Deduplicação** — se o conteúdo não mudou, o arquivo não é reescrito. O
   hot folder não “pisca” e o operador não vê take falso de atualização.
4. **Escrita atômica** — todo arquivo é escrito em `.tmp` e promovido com
   `os.replace()`, então o GC nunca lê um arquivo pela metade.

Há ainda `pct_minimo_para_publicar`, para segurar o placar até um percentual
mínimo de seções totalizadas.

## Supervisão

- `dados/estado/saude.json` — situação de cada alvo a cada ciclo, para o
  monitoramento da emissora acompanhar.
- `logs/gctse.log` — log rotativo diário, 14 dias.
- `alertas` — webhook (Teams ou Power Automate) para falha repetida, alvo
  parado ou fase inesperada, com supressão de repetição.

## Documentação

- [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) — como as peças se encaixam e onde mexer
- [`docs/TSE-API.md`](docs/TSE-API.md) — endpoints, campos e o que confirmar em 2026
- [`docs/GC-INTEGRACAO.md`](docs/GC-INTEGRACAO.md) — receita por marca de GC
- [`docs/OPERACAO.md`](docs/OPERACAO.md) — runbook do dia da eleição e contingência

## Testes

```bash
python -m pytest tests -q
```
