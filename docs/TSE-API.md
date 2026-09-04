# A fonte de dados do TSE

## O que é

O TSE não oferece uma API REST autenticada para a apuração. O que existe — e é
o que as emissoras usam — é a **Divulgação de Resultados**: um conjunto de
arquivos JSON estáticos publicados em CDN e reescritos a cada ciclo de
totalização (ordem de dezenas de segundos). Você não “chama um endpoint”, você
busca um arquivo e compara com o anterior.

Consequências práticas para a operação:

- Não há chave de acesso nem contrato de uso. Também não há SLA.
- Como é CDN, nós diferentes podem servir versões diferentes por alguns
  segundos — daí a trava anti-regressão.
- Cache condicional (`ETag` / `If-Modified-Since`) é o que permite pesquisar a
  cada 20 s sem tráfego relevante: a maioria das respostas volta `304`.

## Formato das URLs

Padrão usado nos últimos pleitos, e o que está configurado por padrão:

```
{base}/{ciclo}/{pleito}/dados-simplificados/{dir}/{abr}-c{cargo:04d}-e{eleicao:06d}-r.json
{base}/{ciclo}/{pleito}/dados/{dir}/{abr}-c{cargo:04d}-e{eleicao:06d}-r.json
```

| Trecho | Exemplo | Observação |
|---|---|---|
| `base` | `https://resultados.tse.jus.br/oficial` | `tse.base_url` |
| `ciclo` | `ele2026` | `tse.ciclo` |
| `pleito` | código do pleito/turno | **só existe quando o TSE publica** |
| `dir` | `br`, `pr` | UF para estadual e municipal |
| `abr` | `br`, `pr`, `pr75353` | UF + código **TSE** do município (não é o IBGE) |
| `cargo` | `0001` | 4 dígitos |
| `eleicao` | `000619` | 6 dígitos |

`dados-simplificados` traz o placar (é o que o GC precisa). `dados` traz o
arquivo completo, bem maior; use só se precisar de detalhe por candidato que
não vem no simplificado (`coleta.usar_dados_completos: true`).

Se o TSE mudar o layout dos caminhos em 2026, ajuste `tse.padroes` no
`config.yaml` — o código não precisa mudar.

## Códigos de cargo

| Código | Cargo | | Código | Cargo |
|---|---|---|---|---|
| 1 | Presidente | | 8 | Deputado Distrital |
| 3 | Governador | | 11 | Prefeito |
| 5 | Senador | | 13 | Vereador |
| 6 | Deputado Federal | | | |
| 7 | Deputado Estadual | | | |

Em 2026 (eleições gerais) valem 1, 3, 5, 6, 7 e 8.

## Campos do arquivo simplificado

O arquivo usa chaves abreviadas. O mapeamento padrão do parser
(`src/gctse/tse/parser.py`) cobre as abreviações usadas nos pleitos recentes:

| Campo do modelo | Chaves tentadas, em ordem |
|---|---|
| cargo | `carg`, `cdcargo`, `cargo` |
| abrangência (código/nome/tipo) | `cdabr` / `nmabr` / `tpabr` |
| fase | `f`, `fase`, `tf` |
| data e hora de geração | `dg` + `hg` |
| seções | `s` → `st` (totalizadas), `s` (total), `pst` (%) |
| votos válidos / brancos / nulos | `vv`·`vvc` / `vb` / `vn` |
| lista de candidatos | `cand`, `candidatos` |
| candidato: número / nome | `n` / `nm`, `nmurna` |
| candidato: partido / coligação | `cc` / `nv` |
| candidato: votos / % | `vap` / `pvap` |
| candidato: eleito | `e` (`"s"` = sim) |

**Confirme antes do dia.** Essas abreviações já mudaram entre pleitos e não há
garantia de que 2026 mantenha todas. O comando abaixo baixa um arquivo real e
lista as chaves que ele de fato tem:

```bash
gctse inspecionar --abrangencia br --cargo 1
```

Qualquer diferença se corrige na seção `mapeamento` do `config.yaml`, que entra
na frente das chaves padrão:

```yaml
mapeamento:
  candidato:
    nome: [nmUrna]        # se o TSE passar a usar 'nmUrna'
    votos: [qtVotos]
```

## Fase: a diferença entre simulado e oficial

O campo de fase indica se o boletim é oficial (`O`) ou simulado (`S`). O TSE
publica simulados nos dias que antecedem o pleito, nos mesmos caminhos. Um
sistema que ignora a fase coloca resultado fictício no ar com cara de
resultado real.

Por isso `seguranca.bloquear_nao_oficial: true` é o padrão, e o campo `selo`
fica disponível em todos os exporters para o template estampar
“PARCIAL — NÃO OFICIAL” quando for o caso. **Não desligue essa trava em
produção.** Para ensaiar, use `gctse ensaio`, que usa o simulador interno e
nunca toca o TSE.

## Números em pt-BR

Tudo vem como texto: votos com ponto de milhar (`"12.345.678"`) e percentuais
com vírgula decimal (`"49,10"`). O parser converte via
`util/numeros.py`; os exporters devolvem já formatado para o ar
(`12.345.678`, `49,10%`) e também em forma numérica (`votos_num`,
`percentual_num`) para quem precisa calcular ou desenhar barra.

## Checklist para 2026

Semanas antes do pleito, quando o TSE publicar a configuração:

1. `gctse descobrir` → anote o código do pleito e da eleição.
2. Preencha `tse.ciclo`, `tse.pleito`, `tse.eleicao` no `config.yaml`.
3. `gctse validar` → confira as URLs montadas para cada alvo.
4. `gctse inspecionar` em um alvo de cada tipo (BR, UF, município) → confira as
   chaves e ajuste `mapeamento` se preciso.
5. `gctse amostrar` → grave as amostras em `dados/amostras/` para poder
   reproduzir o dia offline (`coleta.fonte: arquivo`).
6. Na janela de simulado do TSE, rode com
   `seguranca.bloquear_nao_oficial: false` em uma pasta de saída **de teste**
   para validar a ponta a ponta com dado real do TSE. Devolva a trava para
   `true` antes do dia.
