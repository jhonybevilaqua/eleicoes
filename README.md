# Telão — telas de apuração do TSE

Lê os boletins da Divulgação de Resultados do TSE e desenha **telas inteiras**,
prontas para entrar no switcher como fonte de vídeo. Sem ninguém digitar nada.

| | Resolução | Para quê |
|---|---|---|
| **Tela cheia** | 1920 × 1080 | seis telas, você escolhe qual vai ao ar |
| **Monitor de cena** | 1080 × 1920 | seis telas girando sozinhas, a cada 10 s |

O sistema não produz mais nada — não alimenta gerador de caracteres, não
escreve arquivo para outro programa ler. Um executável, uma configuração, uma
pasta, e o que sai dela são desenhos.

## As telas

**Tela cheia (1920 × 1080)**

1. **Liderança por estado** — mapa pintado pela cor do partido de quem lidera
2. **Como cada estado votou** — o mesmo mapa, com a lista das 27 UFs ao lado
3. **Como o Brasil votou** — válidos, brancos, nulos e abstenção
4. **Apuração nacional** — o contador de urnas, em número grande
5. **Apuração por estado** — mapa pintado pelo percentual já totalizado
6. **Placar** — os candidatos, com barra, percentual e votos

**Monitor vertical (1080 × 1920)** — urnas apuradas, brancos e nulos,
comparecimento, placar, mapa e a lista dos 27 estados.

## Começar

**Windows, sem instalar Python** (o caminho normal para o PC de operação)

GitHub → aba **Actions** → fluxo **Executavel Windows** → última execução →
**Artifacts** → `telao-windows.zip`. Extraia numa pasta fixa e abra
`LEIA-ME.txt`.

**A partir do código**

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -e .
telao validar          # confere a configuração e mostra a URL que vai ler
telao ensaio           # apuração fictícia completa, sem tocar o TSE
telao rodar            # no ar
```

## Não há nada para preencher

Os códigos do TSE para o 1º turno de 4 de outubro de 2026 já estão no
`config/telao.yaml`:

| | |
|---|---|
| pleito | **3220** |
| 6257 | Eleição Geral Federal — presidente, senador, deputado federal |
| 6259 | Eleições Gerais Estaduais — governador, deputado estadual |

Um pleito carrega várias eleições, e **cada cargo só existe no arquivo da
sua** — pedir governador com o código federal devolve 404. O sistema escolhe
sozinho, pelo cargo configurado em `apuracao.cargo`.

## Simulado e produção

O modo vem do **atalho que você abre**, não de arquivo:

```
TELAO-SIMULADO.bat    dias de teste do TSE
TELAO-PRODUCAO.bat    o dia da eleição
```

Os dois leem a **mesma URL** — nos dias de teste o TSE publica o simulado nos
mesmos caminhos, mudando a fase do boletim de `O` para `S`. O modo decide o que
se faz com isso:

- **produção** só aceita fase `O`. Nenhuma linha de configuração derruba essa
  trava.
- **simulado** aceita fase `S` e carimba **todas** as telas com um selo que não
  desliga — inclusive em boletim que o TSE publique marcado como oficial.
- esquecer de escolher vale **produção**, o lado seguro.

## Antes do primeiro boletim

As telas saem **inteiras, com os campos vazios**: barras, rosca, contador,
lista e mapa em cinza, com zeros e travessões. Nada é inventado — é a mesma
estrutura que o TSE vai preencher. Dá para montar e enquadrar tudo hoje, e se
uma dessas telas for ao ar por engano o que aparece é um placar visivelmente
vazio, não um resultado falso.

## O que o sistema não deixa errar

- **Boletim não oficial não vai ao ar** em produção, aconteça o que acontecer
  na configuração.
- **O número não anda para trás**: boletim mais antigo que o exibido é
  descartado (a CDN do TSE pode servir cópia velha de outro nó).
- **Praça sem boletim fica cinza** com a sigla legível, nunca buraco no mapa —
  e praça com boletim e zero voto também, em vez de pintar a cor de quem por
  acaso está no topo de uma lista zerada.
- **Falha de leitura mantém a última tela boa no ar**, nunca tela preta.
- **404 repetido espaça as tentativas** em vez de insistir: o TSE bloqueia o IP
  por 10 minutos depois de muitos, e 404 é o estado normal por horas.
- **Erro de configuração para o atalho** com a explicação na tela, em vez de
  reiniciar a cada 10 segundos.

## Documentação

- [`docs/TELAO.md`](docs/TELAO.md) — o sistema inteiro: telas, mesa, exibição,
  monitor vertical, decisões de desenho
- [`docs/DIAS-DE-TESTE.md`](docs/DIAS-DE-TESTE.md) — roteiro dos dias de teste
  do TSE
- [`docs/TSE-API.md`](docs/TSE-API.md) — como o TSE publica, e o que muda entre
  pleitos
