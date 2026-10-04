// Ajustes do GIRO DOS ESTADOS (Governador e Senador).
// Edite com o Bloco de Notas, salve e aperte F5 na tela do giro.
window.GCTSE_GIRO = {

  // Ordem dos estados no giro. Para tirar um, apague. Para comecar pelo
  // Parana, ponha "pr" em primeiro.
  ordem: ["ac", "al", "ap", "am", "ba", "ce", "df", "es", "go", "ma", "mt", "ms", "mg", "pa",
          "pb", "pr", "pe", "pi", "rj", "rn", "rs", "ro", "rr", "sc", "sp", "se", "to"],

  // Giro automatico (liga/desliga com ENTER): segundos em cada estado.
  tempo_auto_segundos: 10,

  // Transicao entre estados (segundos). 0 = corte seco.
  transicao_segundos: 0.5,

  // Foto oficial do candidato, direto do TSE (aparece no ELEITO e no
  // 2o TURNO). false = sem fotos.
  fotos_do_tse: true
};
