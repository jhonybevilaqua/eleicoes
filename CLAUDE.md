# CLAUDE.md — sistemas de apuração da TV Evangelizar

Guia para quem (pessoa ou Claude) for mexer nestes sistemas nas próximas
eleições. Feitos e usados no ar nas eleições gerais de 2026 (1º turno
04/10, 2º turno 25/10). Resumo operacional para a equipe:
`PROXIMAS-ELEICOES.md`.

## Quem usa e como responder

- Usuário: coordenação de Operações Técnicas da TV Evangelizar (TV, GC,
  OBS, DeckLink, Castalia/LiveBoard). Não é programador: explique em
  **português**, passo a passo, com o nome do .bat a abrir e o que deve
  aparecer na tela.
- Entregas são **.zip prontos** (enviados no chat) + commit no GitHub.

## Regras que não se negociam

1. **Só número oficial.** Tudo que vai ao ar vem do TSE (ou de tabela da
   redação, quando a tela diz). Nada inventado, nada interpolado, nenhuma
   estimativa sem a palavra "estimativa" na tela.
2. **Nada de teste nos pacotes.** Dado de teste só em pasta temporária,
   fora do repositório e dos zips; print de teste marcado como teste.
   Os pacotes não levam `web/dados.js`, `web/estados.js`,
   `web/municipios.js` (são gerados ao vivo).
3. **Tarjas: a estrutura do JSON é sagrada.** As cenas do Castalia estão
   vinculadas aos campos de `entrega/TARJAS/*.json` (ver
   `entrega/CAMPOS.txt`). Nunca acrescentar, renomear ou reordenar campo.
   Mudança de comportamento vai no conteúdo dos campos que já existem.
4. **Não derrubar o TSE nem ser bloqueado:** o TSE limita ~100 req/s por
   IP somando todas as coletas; muitos 404 seguidos podem bloquear o IP.
   Coletas são escalonadas de propósito (não "acelerar").
5. Commits terminam com as linhas de coautoria pedidas na sessão; não
   colocar nome de modelo em arquivo do repositório. Não usar o e-mail do
   usuário em serviço nenhum.
6. **Nunca perder dado da noite.** O TSE só publica o boletim do momento,
   não o histórico: o que a coleta não guardou, só volta dias depois
   (Histórico de totalização, Dados Abertos). Em 25/10/2026 o começo do
   "minuto a minuto" se perdeu porque a pasta instalada foi trocada
   durante a apuração. Por isso:
   - **Durante a apuração, nunca instalar pacote novo por cima nem em outra
     pasta.** Atualização no meio da noite = copiar só os arquivos que
     mudaram (`web\graficos.js` etc.) para a pasta que está no ar. Sempre
     dizer isso ao usuário junto com qualquer zip entregue no dia.
   - Os dados ficam SÓ na pasta instalada (nunca no zip):
     `evolucao-*.json`, `definicao-*.json`, `cores-atribuidas-*.json`,
     `web\dados.js`, `web\estados.js`, `web\municipios.js`, `logs\`,
     `dados-2022.json`, `web\fotos-tse\`, `copias-de-seguranca\`.
   - Cópia de segurança (botão "cópia") antes de qualquer troca e no fim
     da noite; levar o .zip para fora da máquina.
   - Logs são a rede de segurança: `logs\graficos-AAAA-MM-DD.log` (1º
     colocado a cada 20 s) e o log das TARJAS `gctse-AAAA-MM-DD.log` (os
     dois candidatos a cada mudança). `IMPORTAR-EVOLUCAO.bat` refaz o
     minuto a minuto por eles, ou pelo Histórico de totalização do TSE
     (`Historico_Totalizacao_Presidente_BR_2T_AAAA`, a melhor fonte).
   - Desde a 3.29 a coleta grava cópia extra de `evolucao-*.json` e
     `definicao-*.json` em `Documentos\GCTSE-BACKUP` (config `copia_extra`)
     e, ao abrir, restaura/JUNTA os pontos de lá (nunca mistura com um
     arquivo de origem "historico do TSE").

## Os dois sistemas

### TARJAS (GC) — pasta `entrega/` (no pacote se chama `GCTSE`)
- PowerShell puro (Windows 10/11, sem instalar nada).
- `gctse.ps1` (~4.000 linhas): coleta do TSE e grava os JSON das tarjas em
  `TARJAS/` (tarja-presidente, tarja-governador, tarja-senador, listas,
  rodízio). `PAINEL.ps1`: painel web em `http://localhost:8099` (escolhe
  estado, 1º/2º turno, giro automático, eleito no ar, congelar).
- `INICIAR.bat` abre tudo (coleta + painel). Config: `config.json`
  (códigos do TSE, bloco `painel`: `giro_ao_abrir`, `giro_segundos`,
  `eleito_automatico`).
- Manuais: `LEIA-ME.txt`, `DIA-DA-ELEICAO.txt`, `OPERACAO.txt`.
- Versão final 2026: **7.3.1** (`$Versao` no gctse.ps1 e `VERSAO.txt`).

### GRÁFICOS (telas de TV via OBS/DeckLink) — pasta `graficos/`
- Coletas PowerShell que gravam arquivos `.js` lidos pelas páginas web:
  - `graficos.ps1` (GRAFICOS.bat) → `web/dados.js`: Presidente (Brasil,
    estados, exterior, capitais), **evolução minuto a minuto**
    (`evolucao-<ciclo>-<eleicao>-oficial.json`), hora da definição.
  - `estados.ps1` (ESTADOS.bat) → `web/estados.js`: governador, senado,
    câmara, assembleias, comparações com 2022 (`dados-2022.json`).
  - `municipios.ps1` (MUNICIPIOS.bat) → `web/municipios.js`: Presidente
    em cada cidade (lento de propósito, `req_por_segundo`).
- `gerenciador.ps1` (GERENCIADOR.bat, o único .bat do dia a dia): servidor
  em `http://localhost:8098`, abre as coletas e os dois OBS, reabre coleta
  que parar, painel `web/gerenciador.html` (abas de telas, no ar H/V,
  dados do TSE, cópia, salvar telas).
- `web/graficos.js` (~4.500 linhas, uma IIFE): cada tela é `G["id-h"]` /
  `G["id-v"]` que devolve um SVG (1280×720 ou 540×960). A lista do painel
  está em `window.GCTSE_GRAFICOS.lista`. Tela sem dado chama
  `marcaVazio()` (vira `data-vazia`) e o painel esconde. `grafico.html?g=id`
  mostra uma tela; `saida.html` é a saída do OBS.
- Importadores (Portal de Dados Abertos do TSE, pasta `importar/`):
  `importar-candidatos.ps1` (gênero), `importar-perfil-eleitor.ps1`
  (eleitorado e comparecimento por perfil — o comparecimento de cada turno
  o TSE só publica DEPOIS do turno), `importar-2022.ps1` (eleição anterior).
  `atualizar-dados.ps1` roda as etapas; botão "dados do TSE".
- `guardar-tse.ps1`: cópia local do TSE e fotos em `web/fotos-tse/`.
- `salvar-telas.ps1` (SALVAR-TELAS.bat / botão "salvar telas"): todas as
  telas com dado em PNG Full HD **com as fotos**, em `TELAS-SALVAS/`,
  usando o Chrome/Edge em modo headless. Botão "Salvar PNG" (tecla P) de
  cada tela também leva as fotos (via `/foto` do gerenciador).
- `importar-evolucao.ps1` (IMPORTAR-EVOLUCAO.bat / botão "Minuto a minuto
  (histórico)"): refaz o minuto a minuto pelo Histórico de totalização do
  TSE (reconhece 1º/2º turno pelo conteúdo; calcula a hora do
  MATEMATICAMENTE ELEITO e grava `definicao-*.json`) ou pelos logs.
  Passo a passo: `COMO-IMPORTAR-MINUTO-A-MINUTO.txt`.
- `reprise.ps1` (REPRISE-DA-NOITE.bat): treino. Servidor local no formato
  do TSE (127.0.0.1:8790) montado do Histórico de totalização, acelerado,
  e uma CÓPIA separada do GRAFICOS em `reprise/` (config com base_url
  local, porta 8097, `reprise: true` → marca "REPRISE — NÃO VAI AO AR",
  `copia_extra: "nao"`). Só Presidente/Brasil (o histórico é só do Brasil).
- `copia-seguranca.ps1` (botão "cópia") e ARQUIVO-HISTORICO-2026.bat
  (`guardar-tse.ps1 -Historico`: guarda a eleição inteira num .zip antes
  de o TSE tirar do ar).
- Versão final 2026: **3.29** (`$Versao` em graficos.ps1 e estados.ps1,
  topo do `LEIA-ME.txt`).

### Outros
- `src/gctse` (Python): protótipo do início do projeto; **não** é o que foi
  ao ar. `tarjas/`: artes e PDF das tarjas. `entregas/2026/`: os zips finais.

## TSE — o que aprendemos

- Ao vivo: `https://resultados.tse.jus.br/oficial/{ciclo}/{eleicao}/dados/{uf}/{uf}-c{cargo:4}-e{eleicao:6}-u.json`
  (municípios: `{uf}{cdmun5}-c...`; lista de municípios em
  `config/mun-e{eleicao:6}-cm.json`). Fotos:
  `.../{eleicao}/fotos/{uf}/{sqcand}.jpeg`.
- Campos usados: `carg/agr/par/cand`, `st` (situação), `dvt`, `pvap`,
  `vap`, `s.pst` (% seções), `e.esnt` (eleitores das seções não
  totalizadas).
- Códigos 2026: pleito 1º turno 3220 (Presidente 6257; Gov/Sen/Câmara
  6259), 2º turno 3221 (Presidente 6258; Governador 6260). Mudam a cada
  eleição; `CODIGOS-2-TURNO.bat` lê do TSE e pede confirmação.
- **O TSE não marcou "eleito" no 1º turno a tempo**: os sistemas calculam
  **matematicamente eleito** (1º colocado tem mais votos que o 2º + todos
  os eleitores das seções não totalizadas) além da marca do TSE.
- **Votos anulados sub judice** (ex.: retotalização do RJ em 10/10/2026):
  o candidato some do resultado válido; a tarja mostra quem o TSE declarou.
- Estado de 2º turno que o TSE não publicou (404, ex.: Tocantins) fica fora do giro.
- **A eleição anterior sai do site de resultados** (2022 dava `NoSuchKey`
  em 2026). Fonte confiável: Portal de Dados Abertos
  (`votacao_candidato_munzona_AAAA`, `votacao_partido_munzona_AAAA`,
  `detalhe_votacao_munzona_AAAA`, `Historico_Totalizacao_Presidente_BR_*T_AAAA`;
  CSV Latin-1 separado por `;`). Os arquivos atuais de 2022 trazem
  retotalizações (Roraima ficou sem maioria na "votação em partido").

## PowerShell — armadilhas (Windows PowerShell 5.1 é o alvo)

- Nomes de variável **não diferenciam maiúscula**: `$Cargo` e `$cargo` são
  a mesma variável (já causou bug). Rode
  `ferramentas/checar-ps1/checar.sh arquivo.ps1` (precisa de `pwsh`) em
  todo .ps1 alterado: sintaxe, função sem definição, colisão de nomes.
- `PSCustomObject` vira `""` em string: não testar `"$v" -ne ""` em objeto.
- Função que devolve array é desmontada no retorno; `ConvertFrom-Json` de
  uma lista JSON no 5.1 devolve UM objeto (desmonte com `ForEach-Object`).
- `OrderedDictionary` tem `.Contains`, não `.ContainsKey`.
- `Start-Process -ArgumentList` junta com espaço: argumento com espaço vai
  entre aspas.
- Arquivos .ps1 com BOM UTF-8; .bat com CRLF e só ASCII.
- Matar processo pelo PID salvo, nunca `pkill -f` com padrão genérico.

## Como testar sem o TSE

- Dados de teste em pasta temporária (nunca no repo): copiar `graficos/web`
  e pôr um `dados.js`/`estados.js`/`municipios.js` de teste; servir com
  `python3 -m http.server` e abrir cada `grafico.html?g=<id>` no Chromium
  (Playwright), checando erro de JS e texto fora da tela (`svg text` com
  `getBoundingClientRect` fora de W×H). As 167 telas/páginas passaram em
  25/10/2026.
- `node --check web/*.js`; scripts inline dos .html com `new Function`.
- `pwsh` roda os .ps1 no Linux (parte Windows-only, como janelas, não).

## Montar os pacotes

- GRÁFICOS: `git ls-files` de `graficos/` menos `web/dados.js` e
  `web/estados.js`, mais `importar/` vazia. Variante SEM FOTOS: em
  `web/fotos-config.js`, `window.GCTSE_FOTOS_DO_TSE = false;`.
  Nome: `GCTSE-GRAFICOS-<versão>-COM-FOTOS.zip` / `-SEM-FOTOS.zip`.
- TARJAS: arquivos de `entrega/` com a mesma lista do pacote anterior,
  pasta `GCTSE`. Nome: `GCTSE-TARJAS-<versão>.zip`.
- Conferir que não há dado de teste dentro dos zips.

## Para a próxima eleição

- **2028 é municipal** (Prefeito = cargo 11, Vereador = 13, por
  município): coleta, painel, giro, eleito automático e cores servem; as
  tarjas e as telas precisam ser refeitas para prefeito/vereador.
- **2030**: trocar `ciclo` e códigos nos dois configs; a eleição anterior
  passa a ser 2026 — guardar com ARQUIVO-HISTORICO-2026.bat enquanto o TSE
  ainda publica, e adaptar `importar-2022.ps1` (ano nos nomes dos arquivos
  e códigos 544/545/546/547 → os de 2026).
- Testar com o TSE real (1º turno publicado) semanas antes; ensaio com a
  equipe; máquina reserva com a mesma pasta.
