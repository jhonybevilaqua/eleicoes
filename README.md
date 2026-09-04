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
cp config/config.recomendado.yaml config/config.yaml
```

Requisito: Python 3.9 ou superior.

## Primeiros passos

```bash
gctse validar                 # confere a configuração e mostra as URLs montadas
gctse descobrir               # lista os pleitos publicados pelo TSE (pega os códigos)
gctse inspecionar --abrangencia br --cargo 1   # mostra as chaves reais do arquivo
gctse exemplo                 # gera arquivos de exemplo + mapa (monte a cena hoje)
gctse celulas                 # mapa de vínculos para amarrar a cena (ClassX)
gctse ensaio --duracao 600    # simula uma apuração completa em 10 min
gctse uma-vez                 # um único ciclo (bom para agendador)
gctse rodar                   # operação contínua
```

No Windows, sem ativar a venv: `.venv\Scripts\python.exe -m gctse rodar`.

## Montar a cena do GC antes do pleito

Os dados reais de 2026 só existem no dia, mas a cena não precisa esperar. A
pasta [`exemplos/`](exemplos/) traz os arquivos com a **estrutura exata** do que
vai ao ar — mesmos nomes de campo, mesmos caminhos — mais o mapa de qual
caminho guarda qual campo. Aponte o DataSource do LiveBoard para eles e amarre
a cena hoje; no dia, os mesmos caminhos recebem o dado real.

```bash
gctse exemplo                      # regera em exemplos/, com 63% apurado
gctse exemplo --progresso 100      # como a cena fica no fechamento
```

## Configuração

Dois modelos para partir:

- **`config/config.recomendado.yaml`** — escolha fechada, pronta para rodar:
  JSON no LiveBoard, um exporter `fixa` para cena com foto por posição e um
  `colocacao` para o ranking, campos enxutos. Copie este se estiver começando.
- **`config/config.example.yaml`** — todas as opções documentadas, para
  consulta.
- **`config/config.validacao-2022.yaml`** — aponta para o pleito de 2022, que
  ainda está publicado, para validar a cadeia inteira contra dado real do TSE
  antes de 2026. Veja [`docs/TSE-API.md`](docs/TSE-API.md).

Tudo fica em `config/config.yaml`. As quatro seções que você mais vai mexer:

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
| `classx` | CSV, JSON ou XML de geometria fixa + mapa de vínculos | **ClassX LiveBoard** |
| `xml` | XML (perfis `generico`, `tabular`, `atributos`) | GC com data linkage, Chyron, Viz Pilot |
| `csv` | CSV/TSV, layout `linhas` ou `largo` | Ross XPression DataLinq, Chyron, planilhas |
| `json` | JSON (`completo`, `gc`, `largo`, `bruto`) | GC web, segunda tela, site |
| `casparcg` | `templateData` XML + JSON | CasparCG |
| `viz_tab` | texto com TAB | Viz Trio (import de tab fields) |
| `http` | POST/PUT JSON | API do GC, broker, Power Automate/Teams |

Cada exporter tem `destino`, `encoding` e `nome_arquivo` próprios, então dá
para escrever ao mesmo tempo no hot folder do GC, na pasta do web e num
webhook. Detalhes e exemplos por marca em [`docs/GC-INTEGRACAO.md`](docs/GC-INTEGRACAO.md).

**ClassX LiveBoard**: o exporter `classx` gera CSV, JSON ou XML com os mesmos
nomes de campo e geometria fixa — sempre o mesmo número de registros, do
primeiro ao último boletim. Em JSON/XML o vínculo é por nome, então não há
célula para deslocar; em CSV, a geometria garantida faz a célula continuar
válida. Campos numéricos vêm em versão crua (`votos_num`) para o `Sort` com
"As number". `gctse celulas` imprime o mapa de onde cada campo está.

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
