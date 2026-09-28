# Os três dias de teste do TSE — roteiro

Terça, quarta e quinta o TSE publica boletins de teste. É a única chance de
provar a cadeia inteira contra o dado real antes do dia 4. Este é o roteiro,
na ordem.

## Antes de terça (faça hoje)

**1. Baixe e extraia o pacote.**
GitHub → aba **Actions** → fluxo **Executavel Windows** → última execução →
**Artifacts** → `gctse-windows.zip`. Extraia numa pasta fixa, por exemplo
`C:\gctse`. Não instala nada; para desinstalar, apague a pasta.

**2. Prove que roda, sem internet e sem TSE.**

```bat
cd C:\gctse\TELAO
TELAO-ENSAIO.bat
```

Dado inventado, apuração completa em 15 minutos. Abra `TELAO-TELA.bat` noutra
janela e `TELAO-VERTICAL.bat` na terceira. Se as telas aparecem e giram, o
pacote está íntegro — antes de qualquer discussão sobre o TSE.

**3. Instale a fonte.** Barlow Condensed, nos dois PCs de exibição. Sem ela o
desenho cai em Arial Narrow e as medidas mudam.

**4. Ponha o monitor vertical em retrato.** Configurações → Sistema → Vídeo →
Orientação: Retrato. Sem isso o Windows entrega 1920 × 1080 ao navegador.

**5. Libere a rede.** O PC que coleta precisa alcançar
`resultados.tse.jus.br` na porta 443. Peça à TI com antecedência — é o item
que mais atrasa esse tipo de operação.

**Atenção a uma regra do TSE:** *"múltiplos erros 404 podem provocar o bloqueio
temporário do endereço IP"* — 10 minutos, e reiniciam a contagem se você tentar
de novo antes. Isso importa porque 404 é o estado **normal** por horas: antes
de as urnas fecharem, nenhum arquivo existe. O sistema já trata isso — a praça
que responde 404 vai sendo consultada cada vez mais devagar, até 5 minutos, e
volta ao ritmo normal no ciclo seguinte ao primeiro boletim. Mas **não abra
duas cópias** apontando para o mesmo pleito, e não fique reiniciando o atalho
em sequência: aí a proteção reinicia junto.

O outro limite do TSE, 100 requisições por IP por segundo, não é problema:
o sistema faz 28 leituras a cada 20 segundos, com no máximo 8 ao mesmo tempo.

## Terça de manhã — descobrir os códigos

Assim que o TSE publicar a configuração do teste:

```bat
cd C:\gctse
gctse.exe descobrir
```

Ele lista os pleitos disponíveis. Anote o código do **teste** e, se já
estiver publicado, o do **pleito oficial**.

São **dois arquivos** para preencher, com a mesma estrutura: `config.yaml`
(o GC) e `TELAO\telao.yaml` (as telas). Abra cada um no Bloco de Notas e
preencha os dois modos:

```yaml
modos:
  simulado:
    tse:
      pleito: "<código do teste>"
      eleicoes:
        federal: "<código do teste>"
        estadual: "<código do teste>"
  producao:
    tse:
      pleito: "3220"
      eleicoes:
        federal: "6257"
        estadual: "6259"
```

O `ciclo: ele2026` fica na seção `tse` de cima, fora dos modos — é o mesmo
para os dois.

**O modo produção já vem preenchido** com o que o TSE publicou para o 1º turno
de 4 de outubro. Só o bloco `simulado` fica pendente, até saírem os códigos do
teste.

### Por que são dois códigos de eleição, e não um

Um pleito é a data; uma eleição é o conjunto de cargos. O pleito 3220 carrega
três eleições:

| Código | Eleição | Cargos |
|---|---|---|
| 6257 | Eleição Geral Federal | presidente, senador, deputado federal |
| 6259 | Eleições Gerais Estaduais | governador, deputado estadual e distrital |
| 6261 | Eleição Conselho Distrital | — (não usamos) |

**Cada cargo só existe no arquivo da sua eleição.** Pedir governador com o
código federal não devolve erro claro: devolve 404. O sistema escolhe sozinho
pelo cargo — presidente e senador vão no 6257, governador no 6259 — e o
`validar` mostra a URL montada para cada alvo, para você conferir antes de
subir.

Preencha **os dois agora**, nos **dois arquivos**. É o que faz a virada de
quinta para domingo ser uma troca de atalho, e não uma edição de configuração
sob pressão.

```bat
gctse.exe validar
TELAO\telao.exe -c TELAO\telao.yaml validar
```

Os dois têm de dizer `Configuracao OK` sem pendência. Se reclamar que o código
está em `000`, é porque ainda falta preencher aquele modo — e, se você abrir o
atalho antes disso, ele **para e explica** em vez de ficar reiniciando: código
de pleito não se conserta sozinho.

## Nos três dias de teste

Dois atalhos, um em cada janela:

```bat
GC-SIMULADO.bat            (na pasta C:\gctse)
TELAO\TELAO-SIMULADO.bat   (as telas cheias)
```

**Tudo sai carimbado** com o selo de simulado — as tarjas do GC e as telas do
telão —, e o carimbo não desliga. É proposital: se um desses atalhos for
aberto por engano no dia 4, o carimbo aparece no ar e o erro é visto na hora.

O carimbo é decidido pelo **dia**, não pelo campo que vem no arquivo do TSE:
mesmo que o TSE publique o boletim de teste marcado como oficial, ele sai
carimbado.

### O que conferir, em ordem de importância

| | O quê | Como saber que está certo |
|---|---|---|
| 1 | **Os nomes dos candidatos aparecem** | Se vierem vazios, o TSE mudou uma abreviação — é o risco número um, e a correção é uma linha em `mapeamento`. Me chame. |
| 2 | **Os números batem com o site do TSE** | Abra o site do TSE ao lado e confira urnas apuradas e percentual do 1º colocado. Têm de ser idênticos. |
| 3 | **Os 27 estados pintam** | Nenhum pode ficar cinza depois que o TSE publicar todos. Cinza = aquela praça não chegou. |
| 4 | **O carimbo está em tudo** | Nas tarjas do GC, no monitor vertical e nas telas de mapa. |
| 5 | **A mesa responde em ~1 segundo** | Clique numa tela e cronometre. |
| 6 | **O rodízio vertical gira** | 10 s por tela, seis telas, volta ao começo. |
| 7 | **As cores de partido** | Estado vizinho com cor parecida? É agora que se resolve com a arte, não no dia 4. |

Sobre o item 1: a Justiça Eleitoral ainda está julgando os registros de
candidatura, então **até o fim dessa fase não existe lista definitiva de
candidatos**. Nome vazio ou lista curta nos dias de teste pode ser isso, e não
defeito. O que não pode acontecer é a tela sumir: se a lista vier vazia, o
placar desenha as vagas com travessão e o resto do painel segue.

### Se algo der errado

Rode com o rodapé de conferência ligado: abra a tela e aperte `D`, ou use
`TELAO-TELA.bat "...\index.html?debug=1"`. Ele mostra a hora da última troca e
quantas falhas houve.

O log fica em `logs\telao.log`. Se precisar me mandar, esse arquivo mais um
print da tela resolvem quase tudo.

## Depois dos testes — preparar o dia 4

**1. Confirme o código oficial.** Rode `telao.exe descobrir` de novo: o pleito
oficial pode só aparecer depois dos testes.

**2. Feche as cores de partido** em `telao.yaml`, seção `aparencia`. Elas são
o que pinta o mapa — sem elas, o sistema usa uma paleta de reserva que serve
para ensaiar, não para o ar.

**3. Troque os atalhos.** No dia 4, `GC-PRODUCAO.bat` e `TELAO-PRODUCAO.bat`
em vez dos dois `-SIMULADO`. Só isso. Não precisa recompilar nem editar
configuração.

**4. Apague o histórico de teste**, se quiser a curva limpa:
`historico-simulado.jsonl` na pasta do telão. O de produção é outro arquivo e
não foi tocado.

## O que o sistema não deixa você errar

- **Esquecer de escolher o modo cai em produção.** Modo em branco, ausente ou
  escrito errado vale `producao` — o lado seguro.
- **Em produção, boletim simulado é descartado**, aconteça o que acontecer na
  configuração. A trava é decidida pelo modo, não por um valor de arquivo.
- **Código de pleito em `000` impede subir** contra o TSE, em vez de passar a
  noite em "aguardando boletim" com uma URL que sempre devolve 404.
- **Praça sem boletim fica cinza com a sigla legível**, nunca buraco no mapa —
  e praça com boletim mas zero voto apurado também fica cinza, em vez de
  pintar a cor de quem por acaso está no topo de uma lista zerada.
- **O pacote não traz nenhum dado inventado.** As tarjas e as telas nascem em
  branco: campos zerados, travessão no lugar dos nomes. Se uma delas for ao ar
  por engano, o que aparece é um placar vazio, não um resultado falso.
- **Falha de leitura mantém a última tela boa no ar**, nunca tela preta.
