// gctse GRAFICOS - tela "Deputados federais eleitos" (graficos.js).
// Os nomes, partidos, votos e fotos vem do TSE (boletim de deputado federal,
// lido pelo ESTADOS.bat). Aqui so a escolha do que mostrar.
//
//   estados ...... siglas dos estados que entram (ordem na tela: por regiao -
//                  Norte, Nordeste, Centro-Oeste, Sudeste, Sul - e, dentro da
//                  regiao, pelo nome do estado). Dentro do estado: do mais
//                  votado para o menos votado.
//   por_tela ..... candidatos por tela (5)
//   segundos ..... tempo de cada tela antes de trocar sozinha
window.GCTSE_DEPUTADOS = {
  estados: ["ce", "pr", "pe", "sp", "mg", "rn", "rj", "sc", "pa", "rs"],
  por_tela: 5,
  segundos: 8
};
