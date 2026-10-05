// SENADO FEDERAL - composicao por partido (81 cadeiras): ATUAL e a partir
// de 2027 (os 27 eleitos em 2022 que continuam + os 54 eleitos em 2026).
// A composicao por partido NAO sai do boletim do TSE de 2026 (os senadores
// que continuam mudaram de partido desde 2022): estes numeros vieram da
// tabela que a redacao forneceu. Confira antes de ir ao ar.
// Edite com o Bloco de Notas, salve e aperte F5 na tela.
//   sigla, atual, em2027 (cadeiras) e cor (#rrggbb) de cada partido.
//   A soma de cada coluna deve dar 81 (a tela mostra a soma que encontrar).
window.GCTSE_SENADO = {
  // Credito no rodape (ex.: "Fonte: TSE e Senado Federal"). Vazio = sem credito.
  fonte: "",
  partidos: [
    { sigla: "AVANTE",    atual: 1,  em2027: 0,  cor: "#63e6be" },
    { sigla: "MDB",       atual: 9,  em2027: 8,  cor: "#2fb344" },
    { sigla: "NOVO",      atual: 1,  em2027: 3,  cor: "#ffd43b" },
    { sigla: "PDT",       atual: 2,  em2027: 1,  cor: "#e64980" },
    { sigla: "PL",        atual: 15, em2027: 28, cor: "#4c6ef5" },
    { sigla: "PODE",      atual: 3,  em2027: 2,  cor: "#a9e34b" },
    { sigla: "PP",        atual: 7,  em2027: 6,  cor: "#99e9f2" },
    { sigla: "PSB",       atual: 7,  em2027: 4,  cor: "#fd7e14" },
    { sigla: "PSD",       atual: 14, em2027: 4,  cor: "#b197fc" },
    { sigla: "PSDB",      atual: 3,  em2027: 2,  cor: "#a5d8ff" },
    { sigla: "PT",        atual: 9,  em2027: 10, cor: "#f03e3e" },
    { sigla: "REDE",      atual: 0,  em2027: 1,  cor: "#12b886" },
    { sigla: "REP",       atual: 6,  em2027: 5,  cor: "#8d99ae" },
    { sigla: "S/PARTIDO", atual: 1,  em2027: 1,  cor: "#dee2e6" },
    { sigla: "UNIÃO",     atual: 3,  em2027: 6,  cor: "#22b8cf" }
  ]
};
