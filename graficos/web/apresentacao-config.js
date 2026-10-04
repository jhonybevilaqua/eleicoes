// Ajustes da APRESENTACAO (troca automatica de tela).
// Edite com o Bloco de Notas, salve e aperte F5 na apresentacao
// (ou feche e abra de novo o APRESENTACAO-*.bat).
window.GCTSE_APRESENTACAO = {

  // Segundos que cada grafico fica na tela.
  tempo_segundos: 15,

  // Ordem dos graficos em cada formato. Para tirar um, apague a linha.
  horizontal: [
    "presidente-h",     // Presidente - Brasil
    "votos-h",          // Como o Brasil votou
    "urnas-h",          // Apuracao nacional
    "estados-h",        // Como cada estado votou (mapa)
    "lideranca-h",      // Lideranca por estado
    "abstencao-h"       // Abstencao, brancos e nulos
  ],
  vertical: [
    "urnas-v",          // Urnas apuradas
    "votos-v",          // Brancos e nulos
    "presidente-v",     // Presidente
    "comparecimento-v", // Comparecimento
    "lideranca-v",      // Lideranca por estado
    "abstencao-v"       // Abstencao, brancos e nulos
  ],

  // Monitor VERTICAL: 0 quando o Windows ja esta em "Retrato" (a tela e
  // 1080x1920). Se o monitor foi virado mas o Windows continua em
  // "Paisagem" (1920x1080), use 90 ou -90 para girar a imagem.
  girar_vertical: 0,

  // Transicao entre graficos (segundos). 0 = corte seco.
  transicao_segundos: 0.6,

  // Barrinha fina embaixo mostrando o tempo ate o proximo grafico.
  barra_progresso: false
};
