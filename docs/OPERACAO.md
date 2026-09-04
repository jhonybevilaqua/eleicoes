# Runbook — dia da eleição

## Agora · O que não depende do TSE

Só três coisas esperam o TSE publicar: os códigos do pleito, a conferência dos
nomes de campo e os números dos candidatos (após o registro). Todo o resto pode
e deve ser feito com antecedência.

- [ ] Liberar, com a TI, o acesso do PC de operação a `resultados.tse.jus.br`
      (443). É o item com maior prazo de espera — comece por ele.
- [ ] Instalar no PC de operação e deixar o serviço subindo sozinho
      (`scripts\rodar.bat` ou systemd).
- [ ] Validar a cadeia contra dado real com `config/config.validacao-2022.yaml`
      (ver `docs/TSE-API.md`). Isso derruba a maior parte do risco técnico.
- [ ] `gctse exemplo` e montar/amarrar as cenas do LiveBoard contra
      `exemplos/`, usando o mapa em `exemplos/mapa/`.
- [ ] Aferir `texto.limites.nome` contra o lower third real — meça no ar, não
      no olho.
- [ ] Definir as praças e os cargos que vão ao ar, e quantas posições cada cena
      mostra (`slots`).
- [ ] Configurar e testar o webhook de alertas (Teams ou Power Automate).
- [ ] Definir a escala de plantão do dia e quem decide tirar o placar do ar.

## D-30 · Preparação

- [ ] `gctse descobrir` assim que o TSE publicar a configuração do pleito;
      preencher `tse.ciclo`, `tse.pleito`, `tse.eleicao`.
- [ ] `gctse validar` — conferir as URLs montadas para cada alvo.
- [ ] `gctse inspecionar` em um alvo de cada tipo (BR, UF, município);
      ajustar `mapeamento` se alguma chave tiver mudado.
- [ ] Definir os alvos que vão ao ar (praças e cargos) e o
      `limite_candidatos` de cada template.
- [ ] Apontar `destino` de cada exporter para o hot folder real do GC e
      confirmar permissão de escrita da conta que roda o serviço.
- [ ] Escolher o `Type` do DataSource: JSON ou XML (vínculo por nome, sem
      célula para deslocar) ou CSV. Testar os dois na cena antes de decidir.
- [ ] Decidir a `ordem` de cada cena do LiveBoard: `colocacao` (ranking) ou
      `fixa` (candidato preso à posição). Cena com foto por posição exige `fixa`.
- [ ] Se usar o `Sort` do DataSource, apontar para `votos_num` (não para
      `votos`) e marcar "As number".
- [ ] `gctse exemplo` — gerar os arquivos de exemplo e amarrar a cena contra
      eles, com o mapa em `exemplos/mapa/`, não por tentativa e erro. Isso pode
      ser feito meses antes: a estrutura é a mesma do dia.
- [ ] `gctse exemplo --progresso 100` — conferir a cena de fechamento (eleito,
      100% totalizado) antes de precisar dela no ar.

## D-7 · Ensaio técnico

- [ ] `gctse ensaio --duracao 600` com a saída apontando para uma pasta de
      **teste**, não a do ar.
- [ ] Validar no GC: giro do placar, nomes longos, percentuais, selo
      “PARCIAL — NÃO OFICIAL”, virada de liderança, 100% totalizado.
- [ ] Conferir no LiveBoard, durante o ensaio, que nenhuma célula troca de
      significado entre o começo e o fim da apuração simulada.
- [ ] Ensaiar a contingência (abaixo) com o time de plantão.
- [ ] Ligar os alertas (`alertas.ativo: true`) e testar o webhook.
- [ ] Durante a janela de simulado do TSE: rodar com
      `bloquear_nao_oficial: false`, ainda em pasta de teste, para validar com
      dado real. **Devolver a trava para `true` ao terminar.**

## D-1 · Congelamento

- [ ] `seguranca.bloquear_nao_oficial: true` — conferir no arquivo.
- [ ] `saida.destino` de cada exporter apontando para a pasta do ar.
- [ ] Limpar `dados/estado/estado.json` (estado do ensaio não serve para o dia).
- [ ] Iniciar o serviço e deixar rodando: `scripts\rodar.bat` (Windows) ou
      `systemctl enable --now gctse` (Linux). Ambos reiniciam sozinhos.
- [ ] Confirmar que `dados/estado/saude.json` está sendo atualizado.

## Dia · Operação

Antes do início da apuração, os alvos aparecem como `falha(404)` ou
`falha(não publicado)` — é esperado: o TSE ainda não publicou os arquivos.

Acompanhe por dois pontos:

- `dados/estado/saude.json` — situação por alvo, atualizada a cada ciclo:
  `publicado(%)`, `sem-mudanca`, `aguardando(%)`, `bloqueado(fase=...)`,
  `regressao-descartada`, `falha(...)`.
- `logs/gctse.log` — linha por alvo com percentual, número de candidatos e
  arquivos escritos.

## Contingência

| Situação | O que fazer |
|---|---|
| Processo caiu | O wrapper (`rodar.bat` / systemd) reinicia em 10 s. O estado em disco evita reescrita desnecessária. |
| TSE fora do ar / rede oscilando | Nada a fazer: o último boletim válido continua nos arquivos e no ar. Os alertas avisam. Não apague a saída. |
| Alvo em `bloqueado(fase=S)` | O TSE está publicando simulado naquele caminho. **Não desligue a trava.** Confirme o horário oficial de início da divulgação. |
| Alvo em `falha(404)` depois do início | Confira `tse.pleito`/`tse.eleicao` e a abrangência. Rode `gctse inspecionar --url <a URL do log>`. |
| Campo saindo vazio no GC | O TSE mudou a chave. Rode `gctse inspecionar`, ajuste `mapeamento` e reinicie — não precisa mexer no template. |
| Placar precisa sair do ar | Pare o serviço. Os arquivos ficam parados com o último valor; quem tira do ar é o GC. |
| Precisa forçar reescrita | `saida.reescrever_sempre: true` e reiniciar. Use só se o GC perdeu o arquivo. |
| LiveBoard mostrando campo trocado | Alguém mudou `formato`, `layout`, `ordem`, `slots` ou as listas de campos. Rode `gctse celulas` e compare com o vínculo da cena. |
| Ordenação do LiveBoard saindo errada | O `Sort` está apontando para uma coluna formatada. Troque para `votos_num` com "As number". |
| Linha sobrando na cena | Amarre a visibilidade do objeto ao campo `visivel` do slot (`0` = não existe candidato ali). |

**Não faça no ar:** editar arquivo de saída na mão (o próximo ciclo sobrescreve),
apagar `estado.json` com o sistema rodando (reescreve tudo e o hot folder pisca),
ou baixar `intervalo_segundos` para menos de 10 s (não acelera a apuração — o
TSE totaliza no ritmo dele — e aumenta o risco de bloqueio).

## Pós-pleito

- [ ] Guardar `logs/` e `dados/estado/saude.json` do dia.
- [ ] `gctse amostrar` no fim, para ter o boletim final arquivado.
- [ ] Registrar no relatório: indisponibilidades do TSE, alvos que falharam,
      tempo médio de ciclo e ajustes de mapeamento feitos no dia. Isso vira
      insumo para o segundo turno e para o pleito seguinte.
