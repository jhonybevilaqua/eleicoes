// COMPARATIVO de abstencao, brancos e nulos (1o turno, Presidente).
// 2026 vem AO VIVO do boletim do TSE (dados.js). 2022 vem do arquivo do
// TSE que o ESTADOS.bat baixa (estados.js); sem ele, vale o numero abaixo.
// 2018 nao esta nos arquivos coletados: numeros oficiais do TSE de 2018
// (1o turno), os mesmos da arte que a redacao enviou.
// Brancos e nulos = % dos votos; abstencao = % do eleitorado.
window.GCTSE_COMPARATIVO = {
  anos: [
    { ano: 2018, abstencao: 20.33, brancos: 2.65, nulos: 6.14 },
    { ano: 2022, abstencao: 20.95, brancos: 1.59, nulos: 2.82 }
  ],
  // COMPARECIMENTO 1o x 2o TURNO desde 2002 (tela "Comparecimento 1o x 2o
  // desde 2002"): quantos eleitores votaram em cada turno, Presidente.
  // Numeros oficiais do TSE, os mesmos da arte do g1 (25/10/2026).
  // 2026: a tela usa o boletim do TSE ao vivo (dados.js) quando o 1o turno
  // guardado e o 2o turno com 100% das urnas estao la; senao, a linha abaixo.
  comparecimento: [
    { ano: 2002, t1: 94805583, t2: 91664259 },
    { ano: 2006, t1: 104820459, t2: 101998221 },
    { ano: 2010, t1: 111193747, t2: 106606214 },
    { ano: 2014, t1: 115122883, t2: 112683879 },
    { ano: 2018, t1: 117364654, t2: 115933451 },
    { ano: 2022, t1: 123682372, t2: 124252796 },
    { ano: 2026, t1: 125275835, t2: 128233460 }
  ]
};
