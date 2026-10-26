# Eleições 2026 — backup final e guia para as próximas eleições

Sistemas usados pela TV Evangelizar na apuração de 2026 (1º turno 04/10 e
2º turno 25/10/2026). Tudo aqui funcionou no ar.

| Sistema | Versão final | Pasta no repositório | Pacote pronto |
|---|---|---|---|
| **TARJAS** (GC — Castalia/LiveBoard) | 7.3.1 | `entrega/` | `entregas/2026/GCTSE-TARJAS-7.3.1.zip` |
| **GRÁFICOS** (telas 1280×720 e 540×960, OBS) | 3.29.4 | `graficos/` | `entregas/2026/GCTSE-ELEICOES-2026-COMPLETO.zip` (GRAFICOS + TARJAS juntos; sem fotos: `web/fotos-config.js` = false) |

Esta versão está no branch `claude/gc-tse-api-automation-v3nvef`, que é o
branch principal do repositório. Para baixar tudo depois: GitHub → botão
*Code* → *Download ZIP*. Os pacotes prontos para instalar estão em
`entregas/2026/`.

Manuais de operação (dentro de cada pacote):
- TARJAS: `entrega/LEIA-ME.txt`, `entrega/DIA-DA-ELEICAO.txt`,
  `entrega/OPERACAO.txt`, `entrega/CAMPOS.txt` (campos do JSON das tarjas —
  a estrutura não pode mudar, as cenas dependem dela).
- GRÁFICOS: `graficos/LEIA-ME.txt`.

## De onde vêm os dados

- **Ao vivo:** site de divulgação de resultados do TSE
  (`resultados.tse.jus.br`), arquivos
  `{ciclo}/{eleicao}/dados/{uf}/{uf}-c{cargo}-e{eleicao}-u.json`.
- **Eleição anterior (comparações):** o TSE tira do ar a eleição anterior
  no site de resultados. Use o Portal de Dados Abertos do TSE
  (`dadosabertos.tse.jus.br`, *Resultados*) com o `IMPORTAR-2022.bat`. Ele
  grava `graficos/dados-2022.json`.
- **Gênero dos candidatos / perfil do eleitor:** Portal de Dados Abertos,
  com `IMPORTAR-CANDIDATOS.bat` e `IMPORTAR-PERFIL-ELEITOR.bat`. O
  comparecimento por perfil ("quem foi às urnas") o TSE só publica depois de
  cada turno.
- **Mapa por município:** malha municipal do IBGE (domínio público).

Regra mantida durante todo o projeto: **só número oficial do TSE** (ou da
tabela da redação, quando indicado). Nenhum dado de teste nos pacotes.

## O que mudar para a próxima eleição

### 1. Códigos do TSE (todo pleito muda)
O TSE publica os códigos novos perto da eleição. Em 2026 foram:

| | 1º turno | 2º turno |
|---|---|---|
| Pleito | 3220 | 3221 |
| Presidente | 6257 | 6258 |
| Governador / Senador / Câmara | 6259 | 6260 (governador) |

- TARJAS: `entrega/config.json` (`ciclo`, `eleicao`, `eleicao_por_cargo`,
  `eleicao_por_cargo_1t`).
- GRÁFICOS: `graficos/config-graficos.json` (`ciclo`, `eleicao_presidente`,
  `eleicao_presidente_1turno`, `eleicao_estaduais`,
  `eleicao_estaduais_1turno`, `eleicao_camara`). O `CODIGOS-2-TURNO.bat`
  lê os códigos do 2º turno no próprio TSE e pede confirmação.
- `ciclo` passa de `ele2026` para o do novo ano (ex.: `ele2030`).

### 2. Eleições municipais (2028)
Os sistemas foram feitos para eleição **geral** (Presidente, Governador,
Senado, Câmara). Em 2028 os cargos são Prefeito e Vereador (códigos de cargo
11 e 13) e os arquivos são por município. A estrutura de coleta, painel,
giro, eleito automático e cores serve, mas as tarjas e as telas precisam ser
adaptadas para prefeito/vereador. Comece com tempo (2–3 meses antes).

### 3. Eleição anterior para comparação (2030)
- Em 2030, a "eleição anterior" passa a ser **2026**. Antes de o TSE tirar
  2026 do site de resultados, rode `ARQUIVO-HISTORICO-2026.bat` (GRÁFICOS):
  ele guarda o 1º e o 2º turno completos de 2026 num .zip.
- O `importar-2022.ps1` lê os arquivos do Portal de Dados Abertos
  (`votacao_candidato_munzona_AAAA`, `votacao_partido_munzona_AAAA`,
  `detalhe_votacao_munzona_AAAA`, `Historico_Totalizacao_Presidente_BR_*T_AAAA`).
  Para outro ano, troque o ano nos padrões de nome de arquivo e nos códigos
  de eleição gravados no JSON (544/545/546/547 eram os de 2022).

### 4. Depois da apuração (Jornalismo)
- Com 100% das urnas: `SALVAR-TELAS.bat` (ou botão "salvar telas" no
  gerenciador) grava todas as telas com dado em PNG Full HD, com as fotos,
  em `graficos/TELAS-SALVAS/`.
- `COPIA-DE-SEGURANCA.bat` e `ARQUIVO-HISTORICO-2026.bat` para guardar tudo.

### 5. Antes do dia
- Testar com o TSE real (1º turno já publicado) e com o modo ensaio.
- Conferir os campos das tarjas na cena (`CONFERIR.bat`, `CAMPOS.txt`).
- Máquina reserva com a mesma pasta, coletando junto.

## Montar os pacotes de novo

- **GRÁFICOS:** todos os arquivos versionados de `graficos/` (`git ls-files`),
  **menos** `web/dados.js` e `web/estados.js` (gerados ao vivo), mais uma
  pasta `importar/` vazia. A versão SEM FOTOS muda só
  `web/fotos-config.js` para `window.GCTSE_FOTOS_DO_TSE = false;`.
- **TARJAS:** a pasta `entrega/` com o nome `GCTSE`.

## Ferramenta de conferência dos scripts PowerShell

`ferramentas/checar-ps1/checar.sh arquivo.ps1` (precisa do `pwsh`). Aponta
erro de sintaxe, função sem definição e variável com o mesmo nome em
maiúscula/minúscula (o PowerShell não diferencia `$Cargo` de `$cargo`).
Rode em todo `.ps1` alterado antes de gerar pacote.
