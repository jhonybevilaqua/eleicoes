// Ajustes da APRESENTACAO (troca automatica de tela).
// Edite com o Bloco de Notas, salve e aperte F5 na apresentacao
// (ou feche e abra de novo o APRESENTACAO-*.bat).
window.GCTSE_APRESENTACAO = {

  // Segundos que cada grafico fica na tela.
  tempo_segundos: 15,

  // Ordem dos graficos em cada formato. Para tirar um, apague a linha.
  // Tambem valem "resumo:estado" (uma tela do Resumo) e "estado:pr"
  // (Governador e Senador de um estado). No GERENCIADOR, o botao
  // "escolher as telas do rodizio" troca esta lista sem editar arquivo.
  horizontal: [
    "presidente-h",     // Presidente - Brasil
    "votos-h",          // Como o Brasil votou
    "urnas-h",          // Apuracao nacional
    "estados-h",        // Como cada estado votou (mapa)
    "lideranca-h",      // Lideranca por estado
    "abstencao-h",      // Abstencao, brancos e nulos
    "abstencao-mapa-h"  // Mapa da abstencao
  ],
  vertical: [
    "urnas-v",          // Urnas apuradas
    "votos-v",          // Brancos e nulos
    "presidente-v",     // Presidente
    "comparecimento-v", // Comparecimento
    "lideranca-v",      // Lideranca por estado
    "abstencao-v",      // Abstencao, brancos e nulos
    "abstencao-mapa-v"  // Mapa da abstencao
  ],

  // Monitor VERTICAL: 0 quando o Windows ja esta em "Retrato" (a tela e
  // 1080x1920). Se o monitor foi virado mas o Windows continua em
  // "Paisagem" (1920x1080), use 90 ou -90 para girar a imagem.
  girar_vertical: 0,

  // Transicao entre graficos (segundos). 0 = corte seco.
  transicao_segundos: 0.6,

  // Barrinha fina embaixo mostrando o tempo ate o proximo grafico.
  barra_progresso: false,

  // RODIZIOS PRONTOS (botoes no GERENCIADOR, bloco AUTOMATICO): um clique
  // poe a Apresentacao automatica no ar com estas telas e este tempo.
  // "presloc:sp" = Presidente | SP; "presloc:nordeste" = Presidente | Nordeste.
  rodizios_prontos: [
    { nome: "Abertura (17h)", tempo: 12,
      h: ["apuracao-h", "presmapa-h", "pres2t-h", "evolucao-h", "turnos-h"],
      v: ["apuracao-v", "presmapa-v", "pres2t-v", "evolucao-v", "turnos-v"] },
    { nome: "Apuração", tempo: 12,
      h: ["presmapa-h", "virar-h", "evolucao-h", "decisivos-h", "regioes-h", "gov2t-h", "gov12-h", "margem-h", "viradas-h", "apuracao-h"],
      v: ["presmapa-v", "virar-v", "evolucao-v", "decisivos-v", "regioes-v", "gov2t-v", "gov12-v", "margem-v", "viradas-v", "apuracao-v"] },
    { nome: "Fechamento", tempo: 15,
      h: ["eleito-h", "pres2t-h", "presmapa-h", "pres1t-h", "viradas-h", "ganho-h", "abstuf-h", "turnos-h", "governadores-h", "gov2t-h", "gov12-h", "govpres-h"],
      v: ["eleito-v", "pres2t-v", "presmapa-v", "pres1t-v", "viradas-v", "ganho-v", "abstuf-v", "turnos-v", "governadores-v", "gov2t-v", "gov12-v", "govpres-v"] }
  ],

  // FAVORITOS: atalhos no topo do GERENCIADOR (fica fixo no ar ao clicar).
  favoritos: {
    h: ["eleito-h", "pres2t-h", "presmapa-h", "virar-h", "evolucao-h", "gov2t-h", "viradas-h", "margem-h", "apuracao-h"],
    v: ["eleito-v", "pres2t-v", "presmapa-v", "virar-v", "evolucao-v", "gov2t-v", "viradas-v", "margem-v", "apuracao-v"]
  }
};
