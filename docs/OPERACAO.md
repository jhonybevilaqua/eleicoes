# Runbook — dia da eleição

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

## D-7 · Ensaio técnico

- [ ] `gctse ensaio --duracao 600` com a saída apontando para uma pasta de
      **teste**, não a do ar.
- [ ] Validar no GC: giro do placar, nomes longos, percentuais, selo
      “PARCIAL — NÃO OFICIAL”, virada de liderança, 100% totalizado.
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
