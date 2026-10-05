// CAMARA DOS DEPUTADOS - 513 cadeiras.
// A bancada ELEITA em 2026 vem do TSE (deputados federais marcados como
// eleitos em cada estado; o ESTADOS.bat conta). Aqui ficam so:
//   cores ... cor de cada partido (sigla como o TSE escreve, em maiusculas)
//   atual ... OPCIONAL: composicao atual da Camara por partido (nao sai do
//             TSE). Vazio = a tela mostra so a bancada eleita.
//             Ex.: atual: { "PL": 92, "PT": 68, "UNIÃO": 59 }
//   fonte_atual ... credito da composicao atual (ex.: "Câmara dos Deputados")
// Edite com o Bloco de Notas, salve e aperte F5 na tela.
window.GCTSE_CAMARA = {
  atual: {},
  fonte_atual: "",
  cores: {
    "PL": "#2f6bff", "PT": "#e5132d", "UNIÃO": "#22b8cf", "PP": "#99e9f2", "PSD": "#b197fc",
    "REPUBLICANOS": "#8d99ae", "MDB": "#2fb344", "PSB": "#fd7e14", "PDT": "#e64980",
    "PSDB": "#a5d8ff", "PODE": "#a9e34b", "PSOL": "#ffd8a8", "PC DO B": "#c92a2a",
    "PV": "#69db7c", "CIDADANIA": "#ff8787", "AVANTE": "#63e6be", "SOLIDARIEDADE": "#ffa94d",
    "NOVO": "#ffd43b", "REDE": "#12b886", "PRD": "#748ffc", "MISSÃO": "#f783ac",
    "DC": "#ced4da", "PMB": "#e599f7", "AGIR": "#91a7ff", "MOBILIZA": "#fcc2d7"
  }
};
