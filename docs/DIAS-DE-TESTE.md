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

## Terça de manhã — descobrir os códigos

Assim que o TSE publicar a configuração do teste:

```bat
cd C:\gctse\TELAO
telao.exe descobrir
```

Ele lista os pleitos disponíveis. Anote o código do **teste** e, se já
estiver publicado, o do **pleito oficial**.

Abra `telao.yaml` no Bloco de Notas e preencha os dois:

```yaml
modos:
  simulado:
    tse:
      ciclo: ele2026
      pleito: "<código do teste>"
      eleicao: "<código do teste>"
  producao:
    tse:
      ciclo: ele2026
      pleito: "<código oficial>"
      eleicao: "<código oficial>"
```

Preencha **os dois agora**. É o que faz a virada de quinta para domingo ser uma
troca de atalho, e não uma edição de configuração sob pressão.

```bat
telao.exe validar
```

Tem de dizer `Configuracao OK` sem pendência. Se reclamar que o código está em
`000`, é porque ainda falta preencher aquele modo.

## Nos três dias de teste

```bat
TELAO-SIMULADO.bat
```

**Todas as telas saem carimbadas** com `SIMULADO — TESTE, NÃO É RESULTADO`, e
o carimbo não desliga. É proposital: se esse atalho for aberto por engano no
dia 4, o carimbo aparece no ar e o erro é visto na hora.

### O que conferir, em ordem de importância

| | O quê | Como saber que está certo |
|---|---|---|
| 1 | **Os nomes dos candidatos aparecem** | Se vierem vazios, o TSE mudou uma abreviação — é o risco número um, e a correção é uma linha em `mapeamento`. Me chame. |
| 2 | **Os números batem com o site do TSE** | Abra o site do TSE ao lado e confira urnas apuradas e percentual do 1º colocado. Têm de ser idênticos. |
| 3 | **Os 27 estados pintam** | Nenhum pode ficar cinza depois que o TSE publicar todos. Cinza = aquela praça não chegou. |
| 4 | **O carimbo está em todas as telas** | Inclusive no monitor vertical, inclusive nas telas de mapa. |
| 5 | **A mesa responde em ~1 segundo** | Clique numa tela e cronometre. |
| 6 | **O rodízio vertical gira** | 10 s por tela, seis telas, volta ao começo. |
| 7 | **As cores de partido** | Estado vizinho com cor parecida? É agora que se resolve com a arte, não no dia 4. |

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

**3. Troque o atalho.** No dia 4, `TELAO-PRODUCAO.bat` em vez de
`TELAO-SIMULADO.bat`. Só isso. Não precisa recompilar nem editar configuração.

**4. Apague o histórico de teste**, se quiser a curva limpa:
`telao-vertical\historico-simulado.jsonl` e o `historico-simulado.jsonl` da
pasta do telão. O de produção é outro arquivo e não foi tocado.

## O que o sistema não deixa você errar

- **Esquecer de escolher o modo cai em produção.** Modo em branco, ausente ou
  escrito errado vale `producao` — o lado seguro.
- **Em produção, boletim simulado é descartado**, aconteça o que acontecer na
  configuração. A trava é decidida pelo modo, não por um valor de arquivo.
- **Código de pleito em `000` impede subir** contra o TSE, em vez de passar a
  noite em "aguardando boletim" com uma URL que sempre devolve 404.
- **Praça sem boletim fica cinza com a sigla legível**, nunca buraco no mapa.
- **Falha de leitura mantém a última tela boa no ar**, nunca tela preta.
