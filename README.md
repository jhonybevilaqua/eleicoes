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

> **Nunca usou?** Comece por [`docs/PRIMEIRO-USO.md`](docs/PRIMEIRO-USO.md) —
> passo a passo do zero até o placar na cena, sem pressupor conhecimento de
> programação.

## Instalação

**Windows — executável, sem instalar Python** (recomendado para o PC de operação)

O GitHub compila a versão Windows a cada mudança: aba **Actions** → fluxo
**Executavel Windows** → última execução → **Artifacts** → `gctse-windows.zip`.
Extraia numa pasta e rode `1-validar.bat`. Nada é instalado no Windows.

Marcar uma tag (`git tag v1.0.0 && git push --tags`) publica o mesmo pacote
como **Release**, com link permanente e sem exigir login.

**Windows — a partir do código-fonte**

```bat
scripts\instalar.bat
```

Depois disso, rode os comandos como `gctse <comando>` de dentro da pasta do
projeto — o atalho `gctse.bat` usa o ambiente instalado, sem precisar ativar
nada.

**Linux**

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -e .
cp config/config.operacao.yaml config/config.yaml
```

Requisito: Python 3.9 ou superior.

## Primeiros passos

```bash
gctse modo                    # em que modo está: simulado ou produção
gctse validar                 # confere a configuração e mostra as URLs montadas
gctse descobrir               # lista os pleitos publicados pelo TSE (pega os códigos)
gctse inspecionar --abrangencia br --cargo 1   # mostra as chaves reais do arquivo
gctse exemplo --em-branco     # cria a estrutura sem dado nenhum (monte a cena hoje)
gctse celulas                 # mapa de vínculos para amarrar a cena (ClassX)
gctse ensaio --duracao 600    # simula uma apuração completa em 10 min
gctse uma-vez                 # um único ciclo (bom para agendador)
gctse rodar                   # operação contínua
```

No Windows, sem ativar a venv: `.venv\Scripts\python.exe -m gctse rodar`.

## Montar a cena do GC antes do pleito

Os dados reais de 2026 só existem no dia, mas a cena não precisa esperar.

```bash
gctse exemplo --destinos-reais --em-branco   # estrutura completa, zero conteúdo
gctse exemplo --progresso 63                 # chapa fictícia, para VER a cena montada
gctse exemplo --progresso 100                # como a cena fica no fechamento
```

`--em-branco` é o que o pacote entregue leva: todos os campos existem, zerados,
com travessão no lugar dos nomes. Dá para amarrar o LiveBoard campo por campo
sem um único nome inventado em disco — e se um desses arquivos for ao ar por
engano, o que aparece é um placar vazio, não um resultado falso.

Sem a flag, a chapa fictícia serve para **ver** a cena montada, com barra e
foto. Use nos ensaios, não no PC que vai ao ar.

O mapa de vínculos (qual campo do JSON alimenta qual item da cena) sai em
`MAPA-CASTALIA/`.

## Configuração

Dois modelos para partir:

- **`config/config.operacao.yaml`** — a que vai no pacote: as três tarjas, o
  rodízio dos 10 estados e os dois modos (simulado e produção). Copie esta se
  estiver começando.
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
| `mapa` | SVG 1920×1080 pintado + JSON por UF | **mapa do Brasil** na cena, site, segunda tela |

Cada exporter tem `destino`, `encoding` e `nome_arquivo` próprios, então dá
para escrever ao mesmo tempo no hot folder do GC, na pasta do web e num
webhook. Detalhes e exemplos por marca em [`docs/GC-INTEGRACAO.md`](docs/GC-INTEGRACAO.md).

**ClassX LiveBoard**: o exporter `classx` gera CSV, JSON ou XML com os mesmos
nomes de campo e geometria fixa — sempre o mesmo número de registros, do
primeiro ao último boletim. Em JSON/XML o vínculo é por nome, então não há
célula para deslocar; em CSV, a geometria garantida faz a célula continuar
válida. Campos numéricos vêm em versão crua (`votos_num`) para o `Sort` com
"As number". `gctse celulas` imprime o mapa de onde cada campo está.

## Telão — o outro sistema deste repositório

Um programa **separado**, com executável e configuração próprios, que desenha
telas inteiras de 1920 × 1080 e as entrega para um PC de exibição. O gctse
alimenta as tarjas do GC; o telão faz as telas cheias. Os dois rodam
independentes — dar problema num não derruba o outro.

```bash
telao descobrir     # códigos do pleito no TSE
telao validar       # confere antes do ar
telao ensaio        # treina com dado fictício
telao rodar         # no ar
telao mesa          # janela para escolher a tela que vai ao ar
```

Seis telas: liderança por estado (mapa por cor de partido), como cada estado
votou, como o Brasil votou (brancos/nulos/abstenção), apuração nacional,
apuração por estado e o placar.

E um **monitor vertical de cena** (1080 × 1920) que sai do mesmo ciclo e roda
sozinho, trocando de informação a cada 10 segundos: urnas apuradas, brancos e
nulos, comparecimento, placar, mapa e as 27 UFs em coluna. Receita completa em
[`docs/TELAO.md`](docs/TELAO.md).

## Mapas e gráficos

Além do placar, o mesmo boletim sustenta o mapa do Brasil, a composição do voto
e a curva de apuração — tudo com a geometria já calculada, para o GC não fazer
conta:

```bash
gctse exemplo                              # gera também os dois SVGs de mapa
python scripts/gerar_modelos_graficos.py   # regera a arte de referência
```

- **Tela num segundo PC** — o exporter grava também um HTML que mostra o mapa
  em tela cheia e se atualiza sozinho, para quem quer só o mapa numa tela
  dedicada. Para o conjunto de telas com mesa de seleção, veja o **telão**.
- **Mapa por partido** — cada UF na cor do partido de quem lidera ali.
- **Mapa por urnas** — cada UF pela fração de seções totalizadas; enche ao vivo,
  com o total apurado ao lado.
- **Brancos, nulos e abstenção** — percentuais prontos, mais `stroke-dasharray`
  da rosca e as larguras da barra empilhada em pixels.
- **Curva e previsão de fechamento** — a que horas as urnas terminam, no ritmo
  dos últimos boletins. Para escala e intervalo, não para o ar.

A arte de referência com as medidas e o campo que alimenta cada elemento está
em [`graficos/modelos.html`](graficos/modelos.html). Receita completa em
[`docs/GRAFICOS.md`](docs/GRAFICOS.md).

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

- `dados/estado/painel.html` — **tela de validação**: abra no navegador e deixe
  num monitor. Mostra, por praça, o percentual de urnas, 1º e 2º colocado e a
  situação de cada alvo. Recarrega sozinha; é arquivo estático, sem servidor.
- `dados/estado/saude.json` — situação de cada alvo a cada ciclo, para o
  monitoramento da emissora acompanhar.
- `dados/estado/historico.jsonl` — uma linha por boletim publicado. É o que
  permite curva de apuração, previsão de fechamento e marco de virada.
- `dados/estado/graficos.json` — série, projeção e viradas por alvo, reescrito
  a cada ciclo.
- `logs/gctse.log` — log rotativo diário, 14 dias.
- `alertas` — webhook (Teams ou Power Automate) para falha repetida, alvo
  parado ou fase inesperada, com supressão de repetição.

## Documentação

- [`docs/PRIMEIRO-USO.md`](docs/PRIMEIRO-USO.md) — instalar e chegar ao primeiro placar
- [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) — como as peças se encaixam e onde mexer
- [`docs/TSE-API.md`](docs/TSE-API.md) — endpoints, campos e o que confirmar em 2026
- [`docs/GC-INTEGRACAO.md`](docs/GC-INTEGRACAO.md) — receita por marca de GC
- [`docs/TARJAS.md`](docs/TARJAS.md) — os seis modelos de tarja, o HTML e o PDF
- [`docs/GRAFICOS.md`](docs/GRAFICOS.md) — mapa do Brasil, brancos e nulos, curva de apuração
- [`docs/TELAO.md`](docs/TELAO.md) — o telão: sistema de exibição em tela cheia
- [`docs/DIAS-DE-TESTE.md`](docs/DIAS-DE-TESTE.md) — roteiro dos dias de teste do TSE
- [`docs/CASTALIA.md`](docs/CASTALIA.md) — fazer o gráfico acompanhar o percentual no Castalia
- [`docs/OPERACAO.md`](docs/OPERACAO.md) — runbook do dia da eleição e contingência

## Testes

```bash
python -m pytest tests -q
```
