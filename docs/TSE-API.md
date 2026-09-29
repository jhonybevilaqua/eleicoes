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

`dados-simplificados` traz o placar — é o que as telas usam. `dados` traz o
arquivo completo, bem maior; só faz sentido se algum dia for preciso detalhe
por candidato que não vem no simplificado.

Se o TSE mudar o layout dos caminhos, ajuste `tse.padroes` no `telao.yaml` —
o código não precisa mudar.

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
(`src/telao/tse/parser.py`) cobre as abreviações usadas nos pleitos recentes:

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
telao inspecionar --abrangencia br --cargo 1
```

Qualquer diferença se corrige na seção `mapeamento` do `telao.yaml`, que entra
na frente das chaves padrão:

```yaml
mapeamento:
  candidato:
    nome: [nmUrna]        # se o TSE passar a usar 'nmUrna'
    votos: [qtVotos]
```

## Fase: a diferença entre simulado e oficial

O campo de fase indica se o boletim é oficial (`O`) ou simulado (`S`). O TSE
publica simulados nos dias que antecedem o pleito, **nos mesmos caminhos**. Um
sistema que ignora a fase coloca resultado fictício no ar com cara de resultado
real.

Quem decide o que fazer com isso é o **modo**, não a configuração:

| | Fase `S` | Selo |
|---|---|---|
| `TELAO-PRODUCAO.bat` | descartada | só em boletim não oficial |
| `TELAO-SIMULADO.bat` | aceita | **sempre**, mesmo em fase `O` |

Não há linha de configuração que mude isso — `seguranca.bloquear_nao_oficial`
é sobrescrito pelo modo de propósito. Era o caminho por onde um simulado podia
ir ao ar como resultado: bastava alguém desligar a trava num teste e esquecer
de religar.

Para ensaiar sem tocar o TSE, `telao ensaio` usa o simulador interno.

## Números em pt-BR

Tudo vem como texto: votos com ponto de milhar (`"12.345.678"`) e percentuais
com vírgula decimal (`"49,10"`). O parser converte via `util/numeros.py`, e as
telas recebem tanto o número formatado quanto o valor bruto — o formatado para
escrever, o bruto para calcular a barra.

## Checklist para os dias de teste

1. **`telao validar`** → confere a configuração e imprime a URL que vai ler.
   Abra essa URL no navegador. JSON significa cadeia fechada; 404 significa
   que o TSE ainda não publicou aquele arquivo.
2. **`telao descobrir`** → lista os pleitos publicados. Só é preciso se o TSE
   mudar os códigos; os de 4 de outubro de 2026 já estão na configuração.
3. **`telao inspecionar`** → baixa um boletim real e mostra as chaves que ele
   de fato tem. **É o passo do risco número um:** se o TSE renomear uma
   abreviação, o nome do candidato chega vazio na tela sem nenhum erro
   aparecer. Rode no nacional e numa UF.
4. **`TELAO-SIMULADO.bat`** durante a janela de simulado do TSE. Tudo sai
   carimbado, e o carimbo não desliga.

O roteiro completo, com o que conferir em cada dia e em que ordem, está em
[`DIAS-DE-TESTE.md`](DIAS-DE-TESTE.md).
