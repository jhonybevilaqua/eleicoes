# Tarjas de apuração — EV News 2026

Seis modelos de tarja para a noite de apuração, na linguagem visual do EV News.
A arte e as medidas ficam em [`tarjas/modelos.html`](../tarjas/modelos.html) —
abra no navegador para ver cada modelo em proporção 1920×1080, com as guias de
área segura e o estado de fechamento.

Para imprimir ou circular: [`tarjas/Tarjas-EV-News-2026.pdf`](../tarjas/Tarjas-EV-News-2026.pdf)
— A4 paisagem, um modelo por página, cada um nos dois estados lado a lado.
A mesma página gera o PDF (modo `?impressao`), então mexer na arte e rodar
`python scripts/gerar_pdf_tarjas.py` mantém os dois em sincronia.

## Os modelos

| Código | Modelo | Foto | Altura | Quando usar |
|---|---|---|---|---|
| T1 | Presidente — duelo | sim | 280 px | placar principal da noite |
| T2 | Governador — duelo | sim | 280 px | uma cena por UF coberta |
| T3 | Senador — sem foto | não | 252 px | cabe nome longo |
| T4 | Deputado — compacta | não | 224 px | proporcionais, percentuais baixos |
| T5 | Passagem ao vivo | não | 124 px | por baixo de entrevista |
| T6 | Selo de apuração | não | canto | permanente durante o bloco |

Todos mostram as quatro informações obrigatórias: praça, 1º colocado, 2º
colocado, percentual de urnas apuradas e percentual de votos válidos.

## Os dois percentuais não são a mesma coisa

| Campo | O que é | Onde aparece |
|---|---|---|
| `resumo.apuracao_pct` | **urnas apuradas** — quanto da apuração já saiu | chip da cartola |
| `candidatos[n].percentual` | **votos válidos** daquele candidato | número grande |

Trocar um pelo outro no ar é o erro mais caro desta cobertura. Nomeie os objetos
da cena com os dois nomes por extenso, nunca com abreviação.

## Fotos

Nomeie os arquivos pelo **número da urna**, não pelo nome — o número é o
identificador estável:

```yaml
texto:
  padrao_foto: "fotos/{numero}.png"
```

O campo `candidatos[n].foto` passa a chegar montado no JSON
(`fotos/13.png`). Enquadramento: retrato 3:4, cabeça e ombros, fundo recortado.
Deixe uma `fotos/_sem.png` de fallback — em proporcional aparece candidato sem
foto no acervo.

## Cores por partido

```yaml
texto:
  cores_partido:
    PVL: "#2f97e8"
    PDR: "#7d93b3"
  cor_padrao: "#8a8a8a"
```

O campo `candidatos[n].cor` alimenta a barra. A mesma sigla mantém a mesma cor
em todas as praças e cargos — é por ela que o telespectador se orienta entre um
bloco e outro.

## Detalhes que a arte precisa respeitar

**Proporcional tem número pequeno.** Em deputado, o 1º colocado costuma ficar
entre 2% e 5%. O campo do percentual precisa caber `4,12%` sem parecer quebrado,
e a barra precisa ser legível com preenchimento mínimo — por isso T4 e T5
normalizam a barra pelo líder, não pelo total.

**Linha vazia é caso normal.** Amarre a visibilidade de cada bloco de candidato
ao campo `visivel` do slot. Antes de a apuração começar, a tarja aparece só com
a cartola e o chip zerado, em vez de mostrar campos em branco.

**O selo de parcial é uma trava, não um enfeite.** Enquanto `resumo.selo` vier
preenchido, mostre-o. Ele só fica vazio quando o boletim é oficial.

**Praça por extenso.** Use `apelido_abrangencia` na config para o nome sair
"PARANÁ" e não "PR".
