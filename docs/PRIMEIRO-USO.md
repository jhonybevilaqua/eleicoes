# Primeiro uso — do zero até o placar na cena

Guia para quem vai instalar. Não precisa saber programar; precisa de um PC com
acesso ao GC e permissão para instalar software.

---

## Caminho A — executável, sem instalar nada (recomendado)

Use este se você não pode instalar Python nas máquinas. A pasta é
autocontida: não instala nada no Windows, não mexe no registro, e para
"desinstalar" basta apagá-la.

### A1. Baixar o executável

O GitHub compila a versão Windows automaticamente a cada mudança no projeto.

1. Abra o repositório no GitHub, aba **Actions**.
2. Clique no fluxo **Executavel Windows** e abra a execução mais recente que
   esteja com o visto verde.
3. Na seção **Artifacts**, baixe **gctse-windows.zip**.

> Para baixar artefatos do Actions é preciso estar logado no GitHub. Se a
> equipe não tiver conta, marque uma tag no projeto (`git tag v1.0.0 &&
> git push --tags`): o mesmo pacote vira uma **Release**, com link público e
> permanente, que não expira.

### A2. Instalar

Extraia o zip numa pasta do PC de operação, por exemplo `C:\gctse`. Pronto —
não há instalador.

A pasta contém:

```
gctse.exe                 o programa
_internal\                bibliotecas (não separe do .exe)
config\                   as configurações que você edita
docs\                     esta documentação
1-validar.bat             confere se está tudo certo
2-gerar-exemplos.bat      gera os arquivos para montar a cena
3-ensaio.bat              simula uma apuração completa
4-rodar.bat               operação real, no dia
LEIA-ME.txt               resumo de uma página
```

### A3. Usar

Dê duplo clique nos `.bat` na ordem. Comece por **`1-validar.bat`**: se ele
responder "Configuracao OK", está tudo funcionando.

Depois pule direto para o passo **6. Montar a cena no LiveBoard**, mais abaixo.

> **Se o antivírus reclamar:** executáveis gerados por PyInstaller às vezes são
> sinalizados por engano. Peça à TI para liberar a pasta. Como o código-fonte e
> o processo de compilação são públicos, dá para auditar — e, se a política
> exigir, compilar internamente com `scripts\build.bat` numa máquina que tenha
> Python.

---

## Caminho B — a partir do código-fonte

Use se você tem liberdade para instalar Python, ou se vai mexer no código.

### B1. Instalar o Python (uma vez)

Baixe o Python 3.9 ou superior em <https://www.python.org/downloads/> e instale.

> **Marque "Add Python to PATH" na primeira tela do instalador.** Se esquecer,
> os comandos abaixo não vão funcionar e é preciso reinstalar.

Para conferir, abra o Prompt de Comando e digite:

```
python --version
```

Deve responder `Python 3.x.x`.

### B2. Baixar o projeto

**Com Git:**

```
git clone https://github.com/jhonybevilaqua/eleicoes.git
cd eleicoes
git checkout claude/gc-tse-api-automation-v3nvef
```

**Sem Git:** abra o repositório no navegador, escolha a branch
`claude/gc-tse-api-automation-v3nvef`, clique em **Code → Download ZIP** e
extraia numa pasta, por exemplo `C:\gctse`.

### B3. Instalar

No Prompt de Comando, dentro da pasta do projeto:

```
scripts\instalar.bat
```

Isso cria o ambiente, instala as dependências e copia
`config\config.recomendado.yaml` para `config\config.yaml` — o arquivo que
você vai editar.

Em Linux:

```
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt -e .
cp config/config.recomendado.yaml config/config.yaml
```

---

## 4. Conferir que funcionou

```
gctse validar
```

No executável, isso é o `1-validar.bat`.

Deve listar os alvos e as URLs montadas. Se aparecer "Configuracao OK", está
instalado.

> Em Linux, use `.venv/bin/gctse` no lugar de `gctse`.

---

## 5. Gerar os arquivos de exemplo

```
gctse exemplo
```

No executável, é o `2-gerar-exemplos.bat`.

Cria a pasta `exemplos\` com os arquivos **exatamente como sairão no ar** —
mesmos nomes de campo, mesma estrutura — só com conteúdo fictício. E também o
mapa de vínculos em `exemplos\mapa\`.

É a partir daqui que o time monta a cena. Não precisa esperar a eleição.

---

## 6. Montar a cena no LiveBoard

1. No LiveBoard, crie um **DataSource** com **Type = JSON**.
2. Aponte para `exemplos\liveboard_rank\governador-pr.json` (ou o arquivo da
   cena que você está montando).
3. Abra `exemplos\mapa\mapa-celulas-governador-pr-liveboard_rank.csv` numa
   planilha. Ele diz qual caminho do JSON guarda qual campo.
4. Amarre cada objeto da cena pelo caminho indicado — por exemplo
   `candidatos[0].nome_partido` para o nome do 1º colocado com o partido.
5. Amarre a **visibilidade** de cada linha ao campo `visivel` do slot
   (`0` = não existe candidato ali, a linha some sozinha).

Se for usar o **Sort** do DataSource, aponte para `votos_num`, nunca para
`votos` — `2.400.000` é texto, não número.

Detalhes e as outras opções (XML, CSV, cena com foto fixa) em
[`GC-INTEGRACAO.md`](GC-INTEGRACAO.md).

---

## 7. Ensaiar com o placar se mexendo

```
gctse ensaio --duracao 600
```

No executável, é o `3-ensaio.bat`. Simula uma apuração completa em 10 minutos, escrevendo nas pastas de saída
configuradas. Deixe a cena no ar (num monitor de teste) e acompanhe: giro do
placar, nome longo estourando, virada de liderança, chegada aos 100%.

`Ctrl+C` encerra.

Para congelar num momento específico:

```
gctse exemplo --progresso 100     # como fica no fechamento, com eleito
gctse exemplo --progresso 5       # como fica no começo da apuração
```

---

## 8. Ajustar ao que vocês vão colocar no ar

Abra `config\config.yaml` num editor de texto. O que costuma precisar de
ajuste:

| O quê | Onde |
|---|---|
| Praças e cargos que vão ao ar | seção `alvos` |
| Quantas posições cada cena mostra | `slots` de cada exporter |
| Pasta que o LiveBoard lê | `destino` de cada exporter |
| Nome estourando o lower third | `texto.limites.nome` — **meça no ar** |
| Números dos candidatos da cena com foto fixa | `candidatos_fixos` |

Depois de qualquer mudança em `slots`, `formato`, `ordem` ou nas listas de
campos, rode `gctse celulas` e confira se os vínculos da cena continuam certos.

---

## 9. Validar contra dado real do TSE

Rode da rede da emissora (precisa de acesso a `resultados.tse.jus.br`):

```
gctse -c config\config.validacao-2022.yaml uma-vez
```

Isso busca o 2º turno de 2022, que continua publicado. Confira em
`dados\validacao-2022\gc\presidente-br.json`: Lula 60.345.999 (50,90%) e
Bolsonaro 58.206.354 (49,10%). Se bater, a cadeia inteira está correta.

Se der erro de conexão, é bloqueio de rede — peça à TI a liberação de
`resultados.tse.jus.br` na porta 443. **Esse é o item de maior prazo de espera
do projeto; abra o chamado cedo.**

---

## 10. No dia da eleição

Preencher os três valores que só o TSE publica:

```
gctse descobrir
```

Anote o código do pleito e da eleição, coloque em `tse.pleito` e `tse.eleicao`
no `config\config.yaml`, e confira as chaves com:

```
gctse inspecionar --abrangencia br --cargo 1
```

Então deixe rodando:

```
scripts\rodar.bat        (código-fonte)
4-rodar.bat              (executável)
```

Esse script reinicia sozinho se o processo cair. Acompanhe por
`dados\estado\saude.json` e `logs\gctse.log`.

O passo a passo completo do dia, com contingência, está em
[`OPERACAO.md`](OPERACAO.md).

---

## Se algo der errado

| Sintoma | O que fazer |
|---|---|
| `python` não é reconhecido | só no caminho B: Python não está no PATH — reinstale marcando a opção |
| `Ambiente nao encontrado` | só no caminho B: rode `scripts\instalar.bat` |
| Antivírus bloqueou o .exe | peça liberação à TI, ou compile internamente com `scripts\build.bat` |
| O .exe abre e fecha na hora | rode pelos `.bat`, que pausam ao final e mostram a mensagem |
| `gctse.exe` não acha a config | a pasta `_internal` e a pasta `config` precisam estar junto do .exe |
| `arquivo de configuracao nao encontrado` | copie `config\config.recomendado.yaml` para `config\config.yaml` |
| `falha(404)` antes da eleição | normal — o TSE ainda não publicou os arquivos |
| Erro de conexão | liberação de rede para `resultados.tse.jus.br:443` |
| Acento errado no ar | troque `encoding` do exporter para `cp1252` |
| Campo vazio na cena | rode `gctse celulas` e compare com o vínculo |
