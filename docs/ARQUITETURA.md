# Arquitetura

## Fluxo de um ciclo

```
                    ┌─────────────────────────────────────────────┐
                    │              pipeline.rodar()               │
                    │        (a cada intervalo_segundos)          │
                    └──────────────────┬──────────────────────────┘
                                       │  para cada alvo, em paralelo
                                       ▼
   fontes.py ──► ClienteTSE.buscar_json()      ETag/If-Modified-Since, retry+backoff
                                       │
                                       ▼
   tse/parser.py ──► analisar()                JSON abreviado → modelo Apuração
                                       │
                                       ▼
   pipeline._publicar()                        4 guardas: fase, regressão, dedupe, mínimo
                                       │
                                       ▼
   exporters/*.py ──► exportar()               XML / CSV / JSON / templateData / TAB / HTTP
                                       │
                                       ▼
   estado.py ──► registrar()                   impressão digital + hora de geração
```

## Módulos

| Arquivo | Responsabilidade |
|---|---|
| `config.py` | lê YAML/JSON, expande `${VAR}`, valida e monta os alvos |
| `tse/endpoints.py` | monta as URLs a partir de padrões configuráveis |
| `tse/cliente.py` | HTTP com timeout, retentativa e cache condicional |
| `tse/parser.py` | converte o JSON do TSE no modelo normalizado |
| `tse/descoberta.py` | lê os pleitos publicados e inspeciona arquivos |
| `modelos.py` | `Apuracao` e `Candidato` — o contrato interno |
| `estado.py` | dedupe e anti-regressão, persistido em disco |
| `fontes.py` | origem dos dados: TSE, simulador ou amostras em disco |
| `simulador.py` | boletins fictícios que evoluem no tempo, para ensaio |
| `exporters/` | um módulo por formato de saída |
| `alertas.py` | webhook de plantão com supressão de repetição |
| `pipeline.py` | orquestra tudo e aplica as guardas |
| `cli.py` | comandos de linha |

## Decisões que valem explicar

**Mapeamento declarativo em vez de código.** O TSE usa chaves abreviadas
(`vap`, `pvap`, `pst`) que já mudaram entre pleitos. Em `tse/parser.py` cada
campo do modelo aponta para uma *lista* de chaves aceitas e vence a primeira
que existir; a seção `mapeamento` da config entra na frente dessa lista. Se
o TSE renomear um campo em 2026, o ajuste é uma linha de YAML — sem
recompilar, sem republicar, sem mexer nos templates do GC.

**Modelo normalizado no meio.** Coleta e exporters não se conhecem. Trocar de
GC não mexe na coleta; mudança do TSE não mexe nos templates.

**Escrita atômica sempre.** Hot folder lê o arquivo assim que ele aparece. Sem
`.tmp` + `os.replace()`, o GC lê metade de um CSV e coloca um placar truncado
no ar. Não é hipótese remota — é o modo de falha mais comum de integração por
pasta.

**Estado em disco.** Reiniciar o processo no meio da apuração não pode
reescrever tudo nem aceitar um boletim velho. O estado guarda, por alvo, a
impressão digital do último boletim e a hora de geração no TSE.

**Alvos independentes.** Cada alvo é processado isolado, em `ThreadPoolExecutor`,
com exceção capturada. Um cargo com arquivo ainda não publicado não impede o
placar de presidente de atualizar.

**Geometria fixa no exporter `classx`.** O LiveBoard amarra objeto a célula, e
célula só é endereço confiável se o arquivo tiver sempre o mesmo formato. Por
isso o número de linhas de candidato vem da configuração, não do TSE: sobrou,
corta; faltou, preenche vazio com `visivel = 0`. O mapa de células é derivado
da mesma configuração (`mapa_celulas()`), então o que o operador amarra e o
que o sistema escreve não podem divergir.

**Sem banco de dados.** Um processo, arquivos de estado em JSON, saída em
arquivo. Menos peça para falhar às 21h de um domingo de apuração, e qualquer
técnico do plantão consegue inspecionar tudo com um editor de texto.

## Onde mexer para cada mudança

| Mudança | Onde |
|---|---|
| TSE renomeou um campo | `mapeamento` no `config.yaml` |
| TSE mudou o caminho das URLs | `tse.padroes` no `config.yaml` |
| Novo cargo ou nova praça no ar | `alvos` no `config.yaml` |
| Novo formato de arquivo para o GC | novo módulo em `exporters/` + registro em `exporters/__init__.py` |
| Célula do LiveBoard apontando errado | `layout`/`ordem`/`slots` do exporter `classx`; conferir com `gctse celulas` |
| Nome estourando o lower third | `texto.limites` no `config.yaml` |
| Acento quebrado no ar | `encoding` do exporter (`cp1252`) ou `texto.remover_acentos` |
