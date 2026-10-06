// gctse GRAFICOS - desenha os graficos de Presidente a partir de dados.js.
// Tudo e SVG: escala para qualquer tela e vira PNG sem perder qualidade.
(function () {
  "use strict";

  // Paleta categorica validada contra o fundo #0b1220 (8 cores; as 3
  // primeiras passam tambem comparando todas contra todas - as do mapa).
  var PALETA = ["#2b84ff", "#ef5b16", "#00aa76", "#c98400", "#e8478a", "#159c15", "#9078ff", "#f05252"];
  var C = {
    fundo: "#0b1220", texto: "#ffffff", apagado: "#8ea3bd", apagado2: "#6b7f99",
    trilho: "#283548", linha: "#1f2b3c", vermelho: "#d03b3b", verde: "#16b216",
    destaque: "#2b84ff", validos: "#7398cf", brancos: "#dfe6f2", nulos: "#e8964a",
    abstencao: "#7f8ca3", comparec: "#2b84ff", semDado: "#6b7688", outros: "#7f8ca3"
  };
  var FONTE = "'Segoe UI', 'DejaVu Sans', Arial, sans-serif";
  // Cor do PARTIDO (pedido da redacao): PT vermelho, PL azul. Os demais pela
  // paleta, sem o azul e o vermelho (para nao confundir com PL e PT).
  // config-graficos.json "cores" continua mandando por cima de tudo.
  var CORES_PARTIDO = { "PT": "#e5132d", "PL": "#2f6bff" };
  var PALETA_OUTROS = ["#ef5b16", "#00aa76", "#c98400", "#e8478a", "#159c15", "#9078ff"];
  // ARTE da TV: fundo (web\arte\fundo-h.jpg / fundo-v.jpg) e logo ELEICOES
  // 2026 (web\arte\logo.png) no canto superior direito. Sem o arquivo,
  // fica o fundo liso de sempre e nenhuma logo.
  function arteFundo(W, H) {
    var v = H > W ? "v" : "h";
    return '<image href="arte/fundo-' + v + '.jpg" data-arte="fundo-' + v + '" x="0" y="0" width="' + W + '" height="' + H +
      '" preserveAspectRatio="xMidYMid slice"/>';
  }
  function arteLogo(W, H, margem) {
    var v = H > W, w = v ? 100 : 182, h = Math.round(w * 355 / 1044), x = W - margem - w, y = v ? 4 : 14;
    return '<image href="arte/logo.png" data-arte="logo" x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '"/>';
  }


  // ---------------------------------------------------------------- formatos
  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pct(v) { return (v == null || isNaN(v)) ? "—" : Number(v).toFixed(2).replace(".", ",") + "%"; }
  function inteiro(v) {
    if (v == null || isNaN(v)) return "—";
    return Math.round(v).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  }
  function corta(t, n) { t = String(t || ""); return t.length > n ? t.slice(0, n - 1) + "…" : t; }

  // ----------------------------------------------------------------- dados
  // O Windows PowerShell 5.1 as vezes grava lista como {"value":[...],"Count":n}:
  // aceita os dois jeitos.
  function comoLista(x) { return Array.isArray(x) ? x : (x && Array.isArray(x.value) ? x.value : []); }
  function normalizar(d) {
    if (!d || d.__ok) return d;
    [d.br].concat(Object.keys(d.ufs || {}).map(function (k) { return d.ufs[k]; })).forEach(function (a) {
      if (a && a.tem) a.candidatos = comoLista(a.candidatos);
    });
    d.__ok = true;
    return d;
  }
  function D() { return normalizar(window.GCTSE_DADOS) || { modo: "OFICIAL", br: { tem: false }, ufs: {} }; }
  function br() { var b = D().br; return (b && b.tem) ? b : null; }
  function uf(u) { var x = (D().ufs || {})[u]; return (x && x.tem) ? x : null; }
  function candidatos(b) { return (b && b.candidatos) ? b.candidatos : []; }
  function lider(b) {
    var cs = candidatos(b);
    return (cs.length && cs[0].votos > 0) ? cs[0] : null;
  }

  function cor(c) {
    if (!c) return C.semDado;
    var cores = D().cores || {};
    if (cores[c.numero]) return cores[c.numero];
    if (cores[c.partido]) return cores[c.partido];
    var sg = String(c.partido || "").toUpperCase().trim();
    if (CORES_PARTIDO[sg]) return CORES_PARTIDO[sg];
    var slot = (D().cor_slot || {})[c.numero];
    if (slot == null || slot >= PALETA.length) return C.outros;
    return PALETA_OUTROS[slot % PALETA_OUTROS.length];
  }

  function selo() {
    var d = D(), b = br();
    if (d.modo === "SIMULADO") return { texto: "SIMULADO — NÃO OFICIAL", cor: C.vermelho };
    if (b && b.andamento === "f") return { texto: "TOTALIZAÇÃO FINAL", cor: C.verde };
    // Antes da 1a urna (arquivo do TSE ja publicado com tudo zerado, ou
    // nenhum arquivo ainda): selo neutro, nada de vermelho.
    var pct = b && b.secoes ? b.secoes.pct : null;
    if (!b || !(pct > 0)) return { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho };
    // 100% das secoes apuradas (pst do TSE), mas o TSE ainda nao marcou o
    // Brasil como final (exterior/revisao): nao e mais "parcial" no ar.
    if (pct >= 100) return { texto: "100% DAS URNAS", cor: C.verde };
    return { texto: "PARCIAL", cor: C.vermelho };
  }
  function subtitulo() {
    var b = br();
    if (!b) return "aguardando o primeiro boletim";
    var h = String(b.hora || "").slice(0, 5);
    return h ? "atualizado às " + h + " (horário do TSE)" : "boletim do TSE";
  }
  function estadosComBoletim() {
    var n = 0, ufs = D().ufs || {};
    for (var k in ufs) if (ufs[k] && ufs[k].tem) n++;
    return n;
  }

  // ----------------------------------------------------------- pecas de SVG
  function t(x, y, txt, o) {
    o = o || {};
    return '<text x="' + x + '" y="' + y + '" font-size="' + (o.s || 16) + '"' +
      (o.b ? ' font-weight="700"' : "") + ' fill="' + (o.c || C.texto) + '"' +
      (o.a ? ' text-anchor="' + o.a + '"' : "") +
      (o.ls ? ' letter-spacing="' + o.ls + '"' : "") +
      (o.max ? ' data-max="' + o.max + '"' : "") +
      (o.extra || "") + ">" + esc(txt) + "</text>";
  }
  function r(x, y, w, h, c, rx) {
    return '<rect x="' + x + '" y="' + y + '" width="' + Math.max(0, w) + '" height="' + h + '" fill="' + c + '"' +
      (rx ? ' rx="' + rx + '"' : "") + "/>";
  }
  // O selo tem a largura medida DEPOIS de desenhado (ver ajustarSelos).
  function seloH(W, sl) {
    var s = sl || selo();
    // a esquerda da logo (canto superior direito)
    return '<g data-selo="dir" data-x="' + (W - 73 - 200) + '">' + r(W - 520, 29, 247, 32, s.cor, 3) +
      t(W - 281, 51, s.texto, { s: 18, b: true, a: "end" }) + "</g>";
  }
  function seloV(W, sl) {
    var s = sl || selo();
    return r(35, 127, W - 70, 26, s.cor, 2) + t(W / 2, 146, s.texto, { s: 16, b: true, a: "middle" });
  }
  function cabecalhoH(W, titulo, sub) {
    return t(73, 57, titulo, { s: 36, b: true, ls: 1, max: W - 73 - 540 }) + t(73, 85, sub, { s: 19, c: C.apagado, max: W - 146 }) + seloH(W);
  }
  function cabecalhoV(W, titulo, sub) {
    return r(35, 48, 6, 38, C.destaque) + t(53, 80, titulo, { s: 32, b: true, ls: 1, max: W - 53 - 35 }) +
      t(53, 106, sub, { s: 16, c: C.apagado, max: W - 53 - 35 }) + seloV(W);
  }
  function svg(W, H, corpo) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + W + " " + H + '" width="' + W + '" height="' + H +
      '" font-family="' + FONTE + '">' + r(0, 0, W, H, C.fundo) + arteFundo(W, H) + corpo + arteLogo(W, H, 35 + (W > H ? 38 : 0)) + "</svg>";
  }
  function barra(x, y, w, h, frac, c) {
    frac = Math.max(0, Math.min(1, frac || 0));
    return r(x, y, w, h, C.trilho, 4) + (frac > 0 ? r(x, y, Math.max(8, w * frac), h, c, 4) : "");
  }
  function etiqueta(x, y, c) {
    if (c && c.eleito) return r(x, y - 15, 74, 20, C.verde, 3) + t(x + 37, y, "ELEITO", { s: 13, b: true, a: "middle" });
    if (c && c.segundo_turno) return r(x, y - 15, 86, 20, C.destaque, 3) + t(x + 43, y, "2º TURNO", { s: 13, b: true, a: "middle" });
    return "";
  }

  // Foto oficial do TSE (sem pasta). Some se o TSE nao tiver; 3 falhas sem
  // nenhum acerto desligam as fotos (404 em excesso pode bloquear o IP).
  var FOTO = { falhou: {}, falhas: 0, acertos: 0 };
  window.__gctseFotoP = function (img, ok) {
    var url = img.getAttribute("href");
    if (ok) { FOTO.acertos++; return; }
    if (!FOTO.falhou[url]) { FOTO.falhou[url] = true; FOTO.falhas++; }
    var g = img.parentNode; if (g && g.parentNode) g.parentNode.removeChild(g);
    clearTimeout(FOTO.timer);
    FOTO.timer = setTimeout(function () { if (window.__gctseRedesenhar) window.__gctseRedesenhar(); }, 300);
  };
  function urlFoto(c) {
    var tse = D().tse;
    // Chave unica em web\fotos-config.js (sem ela: sem fotos). O PNG sai sem
    // fotos: o navegador nao deixa embutir imagem de outro site no PNG.
    if (window.GCTSE_FOTOS_DO_TSE !== true || window.__gctseSemFotos) return "";
    if (!tse || !tse.base || !c || !c.sqcand) return "";
    if (FOTO.falhas >= 3 && FOTO.acertos === 0) return "";
    var url = tse.base + "/" + tse.ciclo + "/" + tse.eleicao + "/fotos/br/" + c.sqcand + ".jpeg";
    return FOTO.falhou[url] ? "" : url;
  }
  function foto(url, x, y, w, h) {
    return "<g>" + r(x, y, w, h, C.trilho, 3) + '<image href="' + esc(url) + '" x="' + x + '" y="' + y + '" width="' + w +
      '" height="' + h + '" preserveAspectRatio="xMidYMid slice" onload="__gctseFotoP(this,true)" onerror="__gctseFotoP(this,false)"/></g>';
  }

  // Rosca: arcos proporcionais com 2px de separacao entre as fatias.
  function rosca(cx, cy, raio, esp, fatias) {
    var total = 0, i, out = '<circle cx="' + cx + '" cy="' + cy + '" r="' + raio + '" fill="none" stroke="' + C.trilho +
      '" stroke-width="' + esp + '"/>';
    for (i = 0; i < fatias.length; i++) total += Math.max(0, fatias[i].v || 0);
    if (total <= 0) return out;
    var circ = 2 * Math.PI * raio, acum = 0, gap = fatias.filter(function (f) { return f.v > 0; }).length > 1 ? 2 : 0;
    for (i = 0; i < fatias.length; i++) {
      var v = Math.max(0, fatias[i].v || 0);
      if (v <= 0) continue;
      var len = circ * v / total;
      var vis = Math.max(0.5, len - gap);
      out += '<circle cx="' + cx + '" cy="' + cy + '" r="' + raio + '" fill="none" stroke="' + fatias[i].c +
        '" stroke-width="' + esp + '" stroke-dasharray="' + vis.toFixed(2) + " " + (circ - vis).toFixed(2) +
        '" stroke-dashoffset="' + (-acum).toFixed(2) + '" transform="rotate(-90 ' + cx + " " + cy + ')"/>';
      acum += len;
    }
    return out;
  }

  // Mapa: estados pintados com a cor de quem lidera em cada um.
  var PEQUENOS = ["rn", "pb", "pe", "al", "se", "df", "es", "rj"];
  function mapa(x, y, escala, opc) {
    var M = window.MAPA_BRASIL, out = '<g transform="translate(' + x + " " + y + ") scale(" + escala + ')">';
    var k, e, u, l;
    for (k in M.estados) {
      e = M.estados[k]; u = uf(k); l = lider(u);
      out += '<path d="' + e.path + '" fill="' + (l ? cor(l) : C.semDado) + '" stroke="' + C.fundo +
        '" stroke-width="' + (1.2 / escala).toFixed(2) + '" stroke-linejoin="round"/>';
    }
    // rotulos (texto com contorno escuro para ler sobre qualquer cor)
    var contorno = ' stroke="' + C.fundo + '" stroke-width="' + (3 / escala).toFixed(2) + '" paint-order="stroke" stroke-linejoin="round"';
    for (k in M.estados) {
      if (opc.chamadas && PEQUENOS.indexOf(k) >= 0) continue;
      if (!opc.chamadas && PEQUENOS.indexOf(k) >= 0 && opc.semPequenos) continue;
      e = M.estados[k]; u = uf(k); l = lider(u);
      var fs = opc.fonte / escala;
      out += '<text x="' + e.cx + '" y="' + (e.cy + (opc.sub ? -2 / escala : fs * 0.35)) + '" font-size="' + fs.toFixed(1) +
        '" font-weight="700" fill="#fff" text-anchor="middle"' + contorno + ">" + k.toUpperCase() + "</text>";
      if (opc.sub) {
        out += '<text x="' + e.cx + '" y="' + (e.cy + fs * 0.95) + '" font-size="' + (fs * 0.8).toFixed(1) +
          '" fill="#fff" text-anchor="middle"' + contorno + ">" + esc(l ? corta(l.partido, 9) : "—") + "</text>";
      }
    }
    out += "</g>";
    if (opc.chamadas) {
      // estados pequenos: sigla puxada para fora do mapa, com uma linha
      var pos = { rn: 130, pb: 156, pe: 182, al: 208, se: 234, df: 300, es: 370, rj: 420 };
      var xc = x + 640 * escala;
      for (var i = 0; i < PEQUENOS.length; i++) {
        k = PEQUENOS[i]; e = M.estados[k]; u = uf(k); l = lider(u);
        var yc = y + pos[k] * escala + (k === "rn" ? 0 : 0);
        var ex = x + e.cx * escala, ey = y + e.cy * escala;
        out += '<line x1="' + ex.toFixed(1) + '" y1="' + ey.toFixed(1) + '" x2="' + (xc - 4) + '" y2="' + yc.toFixed(1) +
          '" stroke="' + C.apagado2 + '" stroke-width="1"/>';
        out += r(xc - 3, yc - 7, 10, 14, l ? cor(l) : C.semDado, 1);
        out += t(xc + 12, yc + 5, k.toUpperCase() + " " + (l ? corta(l.partido, 8) : "—"), { s: 14, b: true });
      }
    }
    return out;
  }

  // Quantos estados cada candidato lidera.
  function placarEstados() {
    var cont = {}, ref = {}, ufs = D().ufs || {};
    for (var k in ufs) {
      var l = lider(uf(k));
      if (!l) continue;
      cont[l.numero] = (cont[l.numero] || 0) + 1; ref[l.numero] = l;
    }
    var lista = [];
    for (var n in cont) lista.push({ c: ref[n], n: cont[n] });
    lista.sort(function (a, b) { return b.n - a.n || String(a.c.numero).localeCompare(String(b.c.numero)); });
    return lista;
  }

  // ------------------------------------------------------------- graficos
  var G = {};

  // ===== horizontais 1280x720 ==========================================
  // Com mais candidatos do que linhas, a ultima vira "OUTROS N CANDIDATOS"
  // com a soma - assim a tela fecha 100%.
  function linhasPresidente(cs, n) {
    if (cs.length <= n) return cs.slice(0, n);
    var resto = cs.slice(n - 1), soma = { nome: "OUTROS " + resto.length + " CANDIDATOS", partido: "soma dos demais",
      votos: 0, pct: 0, outros: true };
    resto.forEach(function (k) { soma.votos += k.votos || 0; soma.pct += k.pct || 0; });
    return cs.slice(0, n - 1).concat([soma]);
  }
  // "FULANO à frente por X pontos (N votos)" - so com votos de verdade.
  function diferenca(cs) {
    if (cs.length < 2 || !(cs[0].votos > 0)) return "";
    return cs[0].nome + " à frente por " + Number(cs[0].pct - cs[1].pct).toFixed(2).replace(".", ",") +
      " pontos (" + inteiro(cs[0].votos - cs[1].votos) + " votos)";
  }
  // Marca dos 50% na barra: quem passa dela vence no 1o turno.
  function marca50(x, y, w, h) { return r(x + w / 2 - 1.5, y - 4, 3, h + 8, "#ffffff", 0); }

  G["presidente-h"] = function () {
    var W = 1280, H = 720, b = br(), todos = candidatos(b), cs = linhasPresidente(todos, 6);
    var o = cabecalhoH(W, "PRESIDENTE — BRASIL", "% dos votos válidos  ·  " + subtitulo());
    o += t(727, 124, "50% DOS VÁLIDOS", { s: 13, b: true, c: C.apagado, a: "middle", ls: 1 });
    for (var i = 0; i < 6; i++) {
      var c = cs[i], cy = 152 + i * 84.4, url = c && !c.outros ? urlFoto(c) : "", dx = 0;
      o += r(73, cy - 20, 6, 42, c ? cor(c) : C.outros, 1);
      if (url) { o += foto(url, 87, cy - 30, 54, 72); dx = 64; }
      o += t(93 + dx, cy + 3, c ? (c.outros ? c.nome : corta(c.nome, 22)) : "—", { s: 26, b: true, max: 320 - dx });
      o += t(93 + dx, cy + 29, c ? corta(c.partido, 30) : "—", { s: 15, c: C.apagado, max: 320 - dx });
      o += etiqueta(427, cy - 20, c);
      o += barra(427, cy - 13, 600, 30, c ? c.pct / 100 : 0, c && !c.outros ? cor(c) : C.outros) + marca50(427, cy - 13, 600, 30);
      o += t(1027, cy + 39, c ? inteiro(c.votos) : "0", { s: 15, c: C.apagado, a: "end" });
      o += t(1200, cy + 10, c ? pct(c.pct) : "0,00%", { s: 30, b: true, a: "end" });
    }
    var s = b ? b.secoes : null;
    o += t(73, 690, s ? inteiro(s.totalizadas) + " de " + inteiro(s.total) + " urnas · " + pct(s.pct) : "0 de 0 urnas",
      { s: 14, c: C.apagado2 });
    var dif = diferenca(todos);
    if (dif) o += t(1200, 690, dif, { s: 18, b: true, a: "end", max: 760 });
    o += t(727, 666, "▏ 50% dos válidos = vence no 1º turno", { s: 13, c: C.apagado2, a: "middle" });
    return svg(W, H, o);
  };

  G["votos-h"] = function () {
    var W = 1280, H = 720, b = br(), v = b ? b.votos : {}, e = b ? b.eleitorado : {};
    var o = cabecalhoH(W, "COMO O BRASIL VOTOU", subtitulo());
    o += rosca(347, 413, 153, 70, [{ v: v.validos, c: C.validos }, { v: v.brancos, c: C.brancos }, { v: v.nulos, c: C.nulos }]);
    var bn = (v.pct_brancos != null && v.pct_nulos != null) ? v.pct_brancos + v.pct_nulos : null;
    o += t(347, 410, b ? pct(bn) : "0,00%", { s: 60, b: true, a: "middle" });
    o += t(347, 446, "BRANCOS + NULOS", { s: 18, c: C.apagado, a: "middle", ls: 2 });
    var linhas = [["Válidos", C.validos, v.pct_validos, v.validos], ["Brancos", C.brancos, v.pct_brancos, v.brancos],
                  ["Nulos", C.nulos, v.pct_nulos, v.nulos]];
    for (var i = 0; i < 3; i++) {
      var y = 211 + i * 56, L = linhas[i];
      o += r(673, y - 10, 20, 20, L[1], 2) + t(707, y + 9, L[0], { s: 26, b: true }) +
        t(914, y + 9, b ? pct(L[2]) : "0,00%", { s: 24, c: C.apagado }) + t(1207, y + 9, b ? inteiro(L[3]) : "0", { s: 24, a: "end" });
    }
    o += '<line x1="673" y1="385" x2="1207" y2="385" stroke="' + C.linha + '" stroke-width="1"/>';
    o += t(707, 426, "Abstenção", { s: 26, b: true }) + t(914, 426, b ? pct(e.pct_abstencao) : "0,00%", { s: 24, c: C.apagado }) +
      t(1207, 426, b ? inteiro(e.abstencao) : "0", { s: 24, a: "end" });
    o += t(707, 460, "Válidos, brancos e nulos sobre os votos", { s: 15, c: C.apagado2 }) +
      t(707, 480, "apurados. Abstenção sobre o eleitorado apto.", { s: 15, c: C.apagado2 });
    o += t(73, 690, "Fonte: TSE — Divulgação de Resultados", { s: 14, c: C.apagado2 });
    return svg(W, H, o);
  };

  G["urnas-h"] = function () {
    var W = 1280, H = 720, b = br(), s = b ? b.secoes : null;
    var o = cabecalhoH(W, "APURAÇÃO NACIONAL", subtitulo());
    o += t(73, 220, "URNAS TOTALIZADAS", { s: 22, c: C.apagado, ls: 4 });
    o += t(73, 333, s ? inteiro(s.totalizadas) : "0", { s: 110, b: true, max: 1134 });
    o += t(73, 381, (s ? "de " + inteiro(s.total) + " · " + pct(s.pct) : "de 0 · 0,00%"), { s: 30, c: C.apagado });
    o += barra(73, 440, 1134, 20, s ? (s.pct || 0) / 100 : 0, C.destaque);
    var faltam = (s && s.total != null && s.totalizadas != null) ? s.total - s.totalizadas : null;
    o += t(73, 527, faltam == null ? "Faltam —" : (faltam === 0 ? "Todas as urnas totalizadas" : "Faltam " + inteiro(faltam) + " urnas"), { s: 28 });
    o += t(73, 690, "Fonte: TSE — Divulgação de Resultados", { s: 14, c: C.apagado2 });
    return svg(W, H, o);
  };

  G["estados-h"] = function () {
    var W = 1280, H = 720, n = estadosComBoletim();
    var o = cabecalhoH(W, "COMO CADA ESTADO VOTOU", n + " de 27 estados com boletim publicado");
    o += mapa(28, 112, 0.868, { fonte: 14, semPequenos: true });
    var M = window.MAPA_BRASIL, ufs = Object.keys(M.estados).sort();
    for (var i = 0; i < ufs.length; i++) {
      var k = ufs[i], col = i < 14 ? 0 : 1, lin = i < 14 ? i : i - 14;
      var x = 587 + col * 347, y = 133 + lin * 40, u = uf(k), l = lider(u);
      o += r(x, y - 12, 4, 24, l ? cor(l) : C.semDado, 1) + t(x + 14, y + 7, k.toUpperCase(), { s: 20, b: true });
      if (l) {
        o += t(x + 62, y + 7, corta(l.nome, 16), { s: 17, max: 180 }) + t(x + 322, y + 7, pct(l.pct), { s: 17, b: true, a: "end" });
      } else {
        o += t(x + 62, y + 7, "aguardando", { s: 18, c: C.apagado });
      }
    }
    o += t(73, 690, "Fonte: TSE — Divulgação de Resultados", { s: 14, c: C.apagado2 });
    return svg(W, H, o);
  };

  function listaPartidos(x, y, larg, passo, max) {
    var lista = placarEstados(), o = "";
    if (!lista.length) return t(x, y + 8, "aguardando boletim", { s: 20, c: C.apagado });
    var topo = lista[0].n;
    for (var i = 0; i < Math.min(max, lista.length); i++) {
      var it = lista[i], yy = y + i * passo;
      o += r(x, yy - 10, 16, 16, cor(it.c), 2);
      o += t(x + 26, yy + 4, corta(it.c.partido, 12) + " · " + corta(it.c.nome, 18), { s: 18, b: true });
      o += t(x + larg, yy + 4, it.n + (it.n === 1 ? " estado" : " estados"), { s: 18, a: "end" });
      o += barra(x, yy + 14, larg, 8, it.n / 27, cor(it.c));
    }
    if (lista.length > max) o += t(x, y + max * passo + 4, "+ " + (lista.length - max) + " outro(s)", { s: 15, c: C.apagado2 });
    return o;
  }

  G["lideranca-h"] = function () {
    var W = 1280, H = 720, n = estadosComBoletim();
    var o = cabecalhoH(W, "LIDERANÇA POR ESTADO", n + " de 27 estados com boletim publicado");
    o += mapa(75, 112, 0.81, { fonte: 16, sub: true, chamadas: true });
    o += t(807, 147, "ESTADOS POR PARTIDO", { s: 18, b: true, c: C.apagado, ls: 2 });
    o += listaPartidos(807, 190, 400, 58, 7);
    o += t(73, 690, "Fonte: TSE — Divulgação de Resultados", { s: 14, c: C.apagado2 });
    return svg(W, H, o);
  };

  // ===== verticais 540x960 =============================================
  var RODAPE_V = function () { return t(35, 932, "Fonte: TSE", { s: 12, c: C.apagado2 }); };

  G["urnas-v"] = function () {
    var W = 540, H = 960, b = br(), s = b ? b.secoes : null;
    var o = cabecalhoV(W, "URNAS APURADAS", subtitulo());
    o += t(35, 215, "URNAS TOTALIZADAS", { s: 18, c: C.apagado, ls: 3 });
    o += t(35, 300, s ? inteiro(s.totalizadas) : "0", { s: 96, b: true, max: 470 });
    o += t(35, 331, s ? "de " + inteiro(s.total) : "de 0", { s: 22, c: C.apagado });
    o += barra(35, 370, 470, 26, s ? (s.pct || 0) / 100 : 0, C.destaque);
    o += t(35, 485, s ? pct(s.pct) : "0,00%", { s: 80, b: true, max: 470 });
    o += t(35, 516, "da apuração concluída", { s: 20, c: C.apagado });
    return svg(W, H, o + RODAPE_V());
  };

  G["votos-v"] = function () {
    var W = 540, H = 960, b = br(), v = b ? b.votos : {};
    var o = cabecalhoV(W, "BRANCOS E NULOS", subtitulo());
    o += rosca(270, 400, 129, 58, [{ v: v.validos, c: C.validos }, { v: v.brancos, c: C.brancos }, { v: v.nulos, c: C.nulos }]);
    var bn = (v.pct_brancos != null && v.pct_nulos != null) ? v.pct_brancos + v.pct_nulos : null;
    o += t(270, 403, b ? pct(bn) : "0,00%", { s: 52, b: true, a: "middle" });
    o += t(270, 436, "BRANCOS + NULOS", { s: 14, c: C.apagado, a: "middle", ls: 2 });
    var linhas = [["Brancos", C.brancos, v.pct_brancos, v.brancos], ["Nulos", C.nulos, v.pct_nulos, v.nulos],
                  ["Válidos", C.validos, v.pct_validos, v.validos]];
    for (var i = 0; i < 3; i++) {
      var y = 642 + i * 74, L = linhas[i];
      o += r(35, y - 9, 18, 18, L[1], 2) + t(65, y + 8, L[0], { s: 24, b: true }) +
        t(505, y + 8, b ? inteiro(L[3]) : "0", { s: 22, a: "end" }) + t(505, y + 34, b ? pct(L[2]) : "0,00%", { s: 17, c: C.apagado, a: "end" });
    }
    o += t(35, 882, "sobre os votos apurados", { s: 14, c: C.apagado2 });
    return svg(W, H, o + RODAPE_V());
  };

  G["presidente-v"] = function () {
    var W = 540, H = 960, b = br(), todos = candidatos(b), cs = linhasPresidente(todos, 5);
    var o = cabecalhoV(W, "PRESIDENTE", "% dos votos válidos · " + subtitulo());
    for (var i = 0; i < 5; i++) {
      var c = cs[i], y = 212 + i * 134, url = c && !c.outros ? urlFoto(c) : "", dx = 0;
      o += r(35, y - 18, 5, 34, c ? cor(c) : C.outros, 1);
      if (url) { o += foto(url, 47, y - 24, 45, 60); dx = 55; }
      o += t(51 + dx, y + 6, c ? (c.outros ? c.nome : corta(c.nome, 16)) : "—", { s: 26, b: true, max: 300 - dx });
      o += t(51 + dx, y + 30, c ? corta(c.partido, 22) : "—", { s: 14, c: C.apagado, max: 300 - dx });
      o += t(505, y + 12, c ? pct(c.pct) : "0,00%", { s: 32, b: true, a: "end" });
      o += barra(35, y + 44, 470, 12, c ? c.pct / 100 : 0, c && !c.outros ? cor(c) : C.outros) + marca50(35, y + 44, 470, 12);
      o += t(35, y + 74, c ? inteiro(c.votos) : "0", { s: 15, c: C.apagado });
      if (c && (c.eleito || c.segundo_turno)) o += etiqueta(505 - (c.eleito ? 74 : 86), y + 78, c);
    }
    o += t(35, 862, "▏ 50% dos válidos = vence no 1º turno", { s: 13, c: C.apagado2 });
    var dif = diferenca(todos);
    if (dif) o += t(35, 892, dif, { s: 16, b: true, max: 470 });
    return svg(W, H, o + RODAPE_V());
  };

  G["comparecimento-v"] = function () {
    var W = 540, H = 960, b = br(), e = b ? b.eleitorado : null;
    var o = cabecalhoV(W, "COMPARECIMENTO", subtitulo());
    o += t(35, 215, "FORAM VOTAR", { s: 18, c: C.apagado, ls: 3 });
    o += t(35, 300, e ? inteiro(e.comparecimento) : "0", { s: 96, b: true, max: 470 });
    o += t(35, 331, e ? "de " + inteiro(e.aptos) + " eleitores aptos" : "de 0 eleitores aptos", { s: 20, c: C.apagado });
    o += t(35, 412, e ? pct(e.pct_comparec) : "0,00%", { s: 80, b: true, max: 470 });
    var fr = e && e.pct_comparec != null ? e.pct_comparec / 100 : 0;
    o += r(35, 450, 470, 26, C.abstencao, 4) + (fr > 0 ? r(35, 450, Math.max(8, 470 * fr - 2), 26, C.comparec, 4) : "");
    o += r(35, 541, 18, 18, C.comparec, 2) + t(65, 558, "Compareceram", { s: 24, b: true }) +
      t(505, 558, e ? inteiro(e.comparecimento) : "0", { s: 22, a: "end" }) + t(505, 584, e ? pct(e.pct_comparec) : "0,00%", { s: 17, c: C.apagado, a: "end" });
    o += r(35, 615, 18, 18, C.abstencao, 2) + t(65, 632, "Abstenção", { s: 24, b: true }) +
      t(505, 632, e ? inteiro(e.abstencao) : "0", { s: 22, a: "end" }) + t(505, 658, e ? pct(e.pct_abstencao) : "0,00%", { s: 17, c: C.apagado, a: "end" });
    return svg(W, H, o + RODAPE_V());
  };

  G["lideranca-v"] = function () {
    var W = 540, H = 960, n = estadosComBoletim();
    var o = cabecalhoV(W, "LIDERANÇA POR ESTADO", n + " de 27 estados com boletim");
    o += mapa(35, 175, 0.767, { fonte: 13, semPequenos: true });
    o += t(35, 722, "ESTADOS POR PARTIDO", { s: 16, c: C.apagado, ls: 2 });
    o += listaPartidos(35, 762, 470, 48, 3);
    return svg(W, H, o + RODAPE_V());
  };

  // O selo cresce com o texto: mede depois de desenhado e ajusta a caixa.
  function ajustarSelos(raiz) {
    // Numero grande e titulo encolhem para caber (ex.: 124.800.000 eleitores
    // no vertical de 540 px). Mede depois de desenhado.
    var ms = raiz.querySelectorAll("text[data-max]");
    for (var j = 0; j < ms.length; j++) {
      var max = parseFloat(ms[j].getAttribute("data-max")), lg = ms[j].getComputedTextLength();
      if (lg > max) {
        var fs = parseFloat(ms[j].getAttribute("font-size"));
        ms[j].setAttribute("font-size", Math.floor(fs * max / lg));
      }
    }
    var gs = raiz.querySelectorAll("g[data-selo]");
    for (var i = 0; i < gs.length; i++) {
      var tx = gs[i].querySelector("text"), rc = gs[i].querySelector("rect");
      var w = tx.getComputedTextLength() + 16, xd = parseFloat(gs[i].getAttribute("data-x"));
      rc.setAttribute("x", (xd - w).toFixed(1)); rc.setAttribute("width", w.toFixed(1));
      tx.setAttribute("x", (xd - 8).toFixed(1));
    }
  }

  // ABSTENCAO, BRANCOS E NULOS: tres numeros grandes, do boletim do Brasil.
  function linhasABN() {
    var b = br(), v = b ? b.votos : null, e = b ? b.eleitorado : null;
    return [
      { cor: C.abstencao, antes: "ABSTENÇÃO", valor: e ? pct(e.pct_abstencao) : "0,00%", depois: "",
        sub: e && e.abstencao != null ? inteiro(e.abstencao) + " eleitores não foram votar" : "" },
      { cor: C.brancos, antes: "BRANCOS SOMAM", valor: v ? pct(v.pct_brancos) : "0,00%", depois: "DOS VOTOS",
        sub: v && v.brancos != null ? inteiro(v.brancos) + " votos em branco" : "" },
      { cor: C.nulos, antes: "NULOS REPRESENTAM", valor: v ? pct(v.pct_nulos) : "0,00%", depois: "DOS VOTOS",
        sub: v && v.nulos != null ? inteiro(v.nulos) + " votos nulos" : "" }
    ];
  }
  G["abstencao-h"] = function () {
    var W = 1280, H = 720, o = cabecalhoH(W, "ABSTENÇÃO, BRANCOS E NULOS", subtitulo());
    linhasABN().forEach(function (L, i) {
      var y = 150 + i * 172;
      o += r(73, y, W - 146, 150, C.linha, 8) + r(73, y, 10, 150, L.cor, 3);
      o += t(113, y + 62, L.antes, { s: 40, b: true, ls: 1, max: 560 });
      if (L.depois) o += t(113, y + 108, L.depois, { s: 30, b: true, c: C.apagado, ls: 1 });
      else if (L.sub) o += t(113, y + 108, L.sub, { s: 22, c: C.apagado, max: 560 });
      o += t(W - 103, y + 104, L.valor, { s: 104, b: true, a: "end" });
      if (L.depois && L.sub) o += t(W - 103, y + 138, L.sub, { s: 18, c: C.apagado, a: "end" });
    });
    o += t(73, 700, "Fonte: TSE — Divulgação de Resultados", { s: 14, c: C.apagado2 });
    return svg(W, H, o);
  };
  G["abstencao-v"] = function () {
    var W = 540, H = 960, o = cabecalhoV(W, "ABSTENÇÃO, BRANCOS E NULOS", subtitulo());
    linhasABN().forEach(function (L, i) {
      var y = 172 + i * 250;
      o += r(35, y, W - 70, 230, C.linha, 8) + r(35, y, 8, 230, L.cor, 3);
      o += t(65, y + 50, L.antes, { s: 30, b: true, ls: 1, max: W - 110 });
      o += t(65, y + 140, L.valor, { s: 88, b: true, max: W - 110 });
      if (L.depois) o += t(65, y + 180, L.depois, { s: 24, b: true, c: C.apagado, ls: 1 });
      if (L.sub) o += t(65, y + (L.depois ? 212 : 184), L.sub, { s: 16, c: C.apagado, max: W - 110 });
    });
    return svg(W, H, o + RODAPE_V());
  };

  // MAPA DA ABSTENCAO: cada estado pela % de eleitores que nao votaram.
  // Faixas FIXAS (a cor de um estado so muda se o numero dele mudar de
  // faixa); um so tom. No fundo escuro, mais abstencao = mais claro e
  // forte (o tom mais escuro ainda aparece contra o azul do fundo).
  var FAIXAS_ABST = [
    { ate: 15, cor: "#8a5516", rot: "até 15%" }, { ate: 18, cor: "#b8741c", rot: "15 a 18%" },
    { ate: 21, cor: "#d9922a", rot: "18 a 21%" }, { ate: 24, cor: "#f0b44e", rot: "21 a 24%" },
    { ate: 999, cor: "#ffd98c", rot: "acima de 24%" }
  ];
  function corAbst(p) {
    if (p == null || !(p > 0)) return C.semDado;
    for (var i = 0; i < FAIXAS_ABST.length; i++) if (p <= FAIXAS_ABST[i].ate) return FAIXAS_ABST[i].cor;
    return FAIXAS_ABST[FAIXAS_ABST.length - 1].cor;
  }
  function abstUf(k) { var x = uf(k); return x && x.eleitorado && x.eleitorado.pct_abstencao > 0 ? x.eleitorado.pct_abstencao : null; }
  function mapaAbst(x, y, escala, fonte) {
    var M = window.MAPA_BRASIL, out = '<g transform="translate(' + x + " " + y + ") scale(" + escala + ')">', k, e;
    for (k in M.estados) {
      e = M.estados[k];
      out += '<path d="' + e.path + '" fill="' + corAbst(abstUf(k)) + '" stroke="' + C.fundo +
        '" stroke-width="' + (1.2 / escala).toFixed(2) + '" stroke-linejoin="round"/>';
    }
    var contorno = ' stroke="' + C.fundo + '" stroke-width="' + (3 / escala).toFixed(2) + '" paint-order="stroke" stroke-linejoin="round"';
    for (k in M.estados) {
      if (PEQUENOS.indexOf(k) >= 0) continue;
      e = M.estados[k];
      out += '<text x="' + e.cx + '" y="' + (e.cy + 5) + '" font-size="' + (fonte / escala).toFixed(1) +
        '" font-weight="700" fill="#fff" text-anchor="middle"' + contorno + ">" + k.toUpperCase() + "</text>";
    }
    return out + "</g>";
  }
  function rankingAbst() {
    var L = [];
    for (var k in (window.MAPA_BRASIL || {}).estados) { var p = abstUf(k); if (p != null) L.push({ u: k.toUpperCase(), p: p }); }
    return L.sort(function (a, b) { return b.p - a.p; });
  }
  function legendaAbst(x, y, passo, s) {
    var o = "";
    FAIXAS_ABST.forEach(function (f, i) {
      o += r(x, y + i * passo - s, s + 4, s + 4, f.cor, 3) + t(x + s + 16, y + i * passo, f.rot, { s: s, c: C.apagado });
    });
    return o;
  }
  G["abstencao-mapa-h"] = function () {
    var W = 1280, H = 720, b = br(), e = b ? b.eleitorado : null, L = rankingAbst();
    var o = cabecalhoH(W, "MAPA DA ABSTENÇÃO", "% de eleitores que não foram votar, por estado");
    o += mapaAbst(60, 118, 0.86, 15);
    var px = 700;
    o += t(px, 160, "BRASIL", { s: 20, b: true, c: C.apagado, ls: 2 });
    o += t(px, 228, e ? pct(e.pct_abstencao) : "0,00%", { s: 72, b: true });
    if (L.length) {
      o += t(px, 290, "MAIOR ABSTENÇÃO", { s: 16, b: true, c: C.apagado, ls: 2 });
      L.slice(0, 3).forEach(function (it, i) { o += t(px, 322 + i * 30, it.u + "  " + pct(it.p), { s: 22, b: true }); });
      o += t(px + 260, 290, "MENOR ABSTENÇÃO", { s: 16, b: true, c: C.apagado, ls: 2 });
      L.slice(-3).reverse().forEach(function (it, i) { o += t(px + 260, 322 + i * 30, it.u + "  " + pct(it.p), { s: 22, b: true }); });
    } else {
      o += t(px, 300, "aguardando os boletins dos estados", { s: 20, c: C.apagado });
    }
    o += legendaAbst(px, 470, 34, 18);
    o += t(73, 690, "Fonte: TSE — Divulgação de Resultados · urnas já apuradas", { s: 14, c: C.apagado2 });
    return svg(W, H, o);
  };
  G["abstencao-mapa-v"] = function () {
    var W = 540, H = 960, b = br(), e = b ? b.eleitorado : null, L = rankingAbst();
    var o = cabecalhoV(W, "MAPA DA ABSTENÇÃO", "% de eleitores que não foram votar");
    o += mapaAbst(35, 170, 0.767, 13);
    o += t(35, 700, "BRASIL", { s: 16, b: true, c: C.apagado, ls: 2 }) + t(35, 752, e ? pct(e.pct_abstencao) : "0,00%", { s: 52, b: true });
    if (L.length) {
      o += t(280, 700, "MAIOR", { s: 14, b: true, c: C.apagado, ls: 2 });
      L.slice(0, 2).forEach(function (it, i) { o += t(280, 726 + i * 26, it.u + "  " + pct(it.p), { s: 18, b: true }); });
      o += t(410, 700, "MENOR", { s: 14, b: true, c: C.apagado, ls: 2 });
      L.slice(-2).reverse().forEach(function (it, i) { o += t(410, 726 + i * 26, it.u + "  " + pct(it.p), { s: 18, b: true }); });
    }
    FAIXAS_ABST.forEach(function (f, i) {
      var cx = 35 + (i % 3) * 160, cy = 812 + Math.floor(i / 3) * 34;
      o += r(cx, cy - 15, 20, 20, f.cor, 3) + t(cx + 30, cy, f.rot, { s: 15, c: C.apagado });
    });
    return svg(W, H, o + RODAPE_V());
  };

  // =========================================================== RESULTADO FINAL
  // ---- Presidente: so os dois do 2o turno ----------------------------------
  // "Vao ao 2o turno" com a palavra do TSE (2o turno no st) ou com a
  // totalizacao final sem ninguem acima de 50%; antes disso, a tela diz
  // "1o e 2o colocados" e o selo fica PARCIAL.
  function doisDoSegundoTurno() {
    var b = br(), cs = candidatos(b);
    // Boletim do 2o turno: o TSE manda so os dois candidatos.
    if (cs.length === 2) return { cs: cs, definido: true, turno2: true, fim: !!(b && b.andamento === "f") };
    var marcados = cs.filter(function (c) { return c.segundo_turno; });
    if (marcados.length >= 2) return { cs: marcados.slice(0, 2), definido: true };
    var top = cs.slice(0, 2);
    var fim = !!(b && b.andamento === "f" && top.length === 2 && !(top[0].pct > 50));
    return { cs: top, definido: fim };
  }
  function cartaoPres(x, y, w, h, c, pos, k) {
    var o = r(x, y, w, h, "rgba(8,14,32,0.78)", 10);
    if (!c) return o + t(x + 32 * k, y + 80 * k, "aguardando o TSE", { s: Math.round(24 * k), c: C.apagado });
    o += r(x, y, w, 8, cor(c), 4);
    var url = urlFoto(c), px = x + 32 * k, dx = 0;
    if (url) { var fw = 165 * k, fh = fw * 4 / 3; o += foto(url, px, y + 44 * k, fw, fh); dx = fw + 28 * k; }
    o += t(px + dx, y + 74 * k, pos + "º COLOCADO", { s: Math.round(16 * k), b: true, c: C.apagado, ls: 2 });
    o += t(px + dx, y + 118 * k, c.nome, { s: Math.round(40 * k), b: true, max: w - 64 * k - dx, nome: true });
    o += t(px + dx, y + 152 * k, c.partido, { s: Math.round(22 * k), c: C.apagado, max: w - 64 * k - dx });
    o += t(x + w - 32 * k, y + h - 110 * k, pct(c.pct), { s: Math.round(92 * k), b: true, a: "end" });
    o += t(x + w - 32 * k, y + h - 74 * k, "dos votos válidos", { s: Math.round(18 * k), c: C.apagado, a: "end" });
    o += t(x + w - 32 * k, y + h - 38 * k, inteiro(c.votos) + " votos", { s: Math.round(22 * k), c: C.apagado, a: "end" });
    if (c.eleito) o += r(px + dx, y + 172 * k, 112 * k, 32 * k, C.verde, 4) + t(px + dx + 56 * k, y + 195 * k, "ELEITO", { s: Math.round(20 * k), b: true, a: "middle" });
    return o;
  }
  function titulos2t(d) {
    if (d.turno2) return { tit: "PRESIDENTE — 2º TURNO", sub: "% dos votos válidos" + (d.fim ? "" : "  ·  parcial") };
    return { tit: d.definido ? "PRESIDENTE — 2º TURNO" : "PRESIDENTE — 1º E 2º COLOCADOS",
             sub: (d.definido ? "vão ao 2º turno" : "parcial") + "  ·  % dos votos válidos no 1º turno" };
  }
  G["pres2t-h"] = function () {
    var W = 1280, H = 720, d = doisDoSegundoTurno(), b = br();
    var tt = titulos2t(d), o = cabecalhoH(W, tt.tit, tt.sub + "  ·  " + subtitulo());
    o += cartaoPres(73, 130, 544, 510, d.cs[0], 1, 1) + cartaoPres(663, 130, 544, 510, d.cs[1], 2, 1);
    var s = b ? b.secoes : null;
    o += t(73, 690, (s ? "urnas apuradas " + pct(s.pct) + "  ·  " : "") + "Fonte: TSE", { s: 14, c: C.apagado2 });
    var dif = diferenca(d.cs);
    if (dif) o += t(1207, 690, dif, { s: 18, b: true, a: "end", max: 760 });
    return svg(W, H, o);
  };
  G["pres2t-v"] = function () {
    var W = 540, H = 960, d = doisDoSegundoTurno();
    var o = cabecalhoV(W, d.definido ? "PRESIDENTE — 2º TURNO" : "PRESIDENTE",
      (d.turno2 ? "% dos votos válidos" : (d.definido ? "vão ao 2º turno" : "1º e 2º colocados")) + " · " + subtitulo());
    o += cartaoPres(35, 170, 470, 360, d.cs[0], 1, 0.74) + cartaoPres(35, 545, 470, 360, d.cs[1], 2, 0.74);
    var dif = diferenca(d.cs);
    if (dif) o += t(35, 925, dif, { s: 14, b: true, max: 470 });
    return svg(W, H, o + t(35, 950, "Fonte: TSE", { s: 12, c: C.apagado2 }));
  };

  // ---- Senado: hemiciclo (81 cadeiras), atual x 2027 ------------------------
  // Numeros por partido em web\senado-config.js (nao saem do boletim do TSE).
  function senado() {
    var cfg = window.GCTSE_SENADO || { partidos: [] }, ps = (cfg.partidos || []).filter(function (p) { return p && p.sigla; });
    var sa = 0, sn = 0;
    ps.forEach(function (p) { sa += +p.atual || 0; sn += +p.em2027 || 0; });
    return { ps: ps, totalAtual: sa, total2027: sn, fonte: cfg.fonte || "" };
  }
  // Cadeiras em fileiras concentricas; partidos em fatias, da esquerda para
  // a direita na ordem do senado-config.js.
  function hemiciclo(cx, cy, R, r0, ps, campo) {
    var n = 0; ps.forEach(function (p) { n += Math.max(0, +p[campo] || 0); });
    if (!n) return "";
    var filas = n <= 40 ? 3 : (n <= 100 ? 5 : Math.round(Math.sqrt(n / 3))), raios = [], soma = 0, i, j;
    for (i = 0; i < filas; i++) { raios.push(r0 + (R - r0) * i / (filas - 1)); soma += raios[i]; }
    var porFila = raios.map(function (rr) { return Math.max(1, Math.round(n * rr / soma)); });
    var dif = n - porFila.reduce(function (a, b) { return a + b; }, 0);
    porFila[filas - 1] += dif;
    var pos = [];
    for (i = 0; i < filas; i++) for (j = 0; j < porFila[i]; j++) {
      var ang = porFila[i] > 1 ? Math.PI - Math.PI * j / (porFila[i] - 1) : Math.PI / 2;
      pos.push({ a: ang, r: raios[i] });
    }
    pos.sort(function (p, q) { return (q.a - p.a) || (p.r - q.r); });
    var passoR = (R - r0) / (filas - 1), passoA = Math.PI * R / Math.max(1, porFila[filas - 1] - 1);
    var raio = Math.min(passoR, passoA) * 0.42, cores = [], o = "";
    ps.forEach(function (p) { for (var k = 0; k < (+p[campo] || 0); k++) cores.push(p.cor || C.outros); });
    pos.forEach(function (p, k) {
      o += '<circle cx="' + (cx + p.r * Math.cos(p.a)).toFixed(1) + '" cy="' + (cy - p.r * Math.sin(p.a)).toFixed(1) +
        '" r="' + raio.toFixed(1) + '" fill="' + (cores[k] || C.trilho) + '"/>';
    });
    return o;
  }
  function saldo(p) {
    var d = (+p.em2027 || 0) - (+p.atual || 0);
    if (d > 0) return { txt: "+" + d, c: "#69db7c" };
    if (d < 0) return { txt: "−" + (-d), c: "#ff8787" };
    return { txt: "0", c: C.apagado };
  }
  function tabelaSenado(x0, x1, y, passo, ps, s, colunas) {
    var o = t(x0 + 20, y, "PARTIDO", { s: s - 4, b: true, c: C.apagado, ls: 1 });
    colunas.forEach(function (cl) { o += t(cl.x, y, cl.rot, { s: s - 4, b: true, c: C.apagado, a: "end", ls: 1 }); });
    o += r(x0, y + 10, x1 - x0, 1, C.linha);
    var lin = ps.slice().sort(function (a, b) { return (b.em2027 - a.em2027) || (b.atual - a.atual) || String(a.sigla).localeCompare(b.sigla); });
    lin.forEach(function (p, i) {
      var yy = y + 10 + passo * (i + 1) - passo * 0.3;
      o += '<circle cx="' + (x0 + 7) + '" cy="' + (yy - s * 0.35).toFixed(1) + '" r="' + (s * 0.33).toFixed(1) + '" fill="' + (p.cor || C.outros) + '"/>';
      o += t(x0 + 20, yy, p.sigla, { s: s, b: true });
      colunas.forEach(function (cl) {
        if (cl.campo === "saldo") { var sd = saldo(p); o += t(cl.x, yy, sd.txt, { s: s, b: true, c: sd.c, a: "end" }); }
        else o += t(cl.x, yy, String(+p[cl.campo] || 0), { s: s, b: cl.campo === "em2027", c: cl.campo === "em2027" ? C.texto : C.apagado, a: "end" });
      });
    });
    return o;
  }
  function rotuloHemi(cx, cy, txt, n, k) {
    return t(cx, cy - 44 * k, txt, { s: Math.round(16 * k), b: true, c: C.apagado, a: "middle", ls: 2 }) +
      t(cx, cy - 4 * k, String(n), { s: Math.round(42 * k), b: true, a: "middle" });
  }
  G["senado-h"] = function () {
    var W = 1280, H = 720, sd = senado();
    var o = t(73, 57, "SENADO FEDERAL", { s: 36, b: true, ls: 1 }) +
      t(73, 85, sd.total2027 + " cadeiras  ·  composição atual e a partir de 2027", { s: 19, c: C.apagado });
    o += hemiciclo(300, 345, 200, 92, sd.ps, "atual") + rotuloHemi(300, 345, "ATUAL", sd.totalAtual, 1);
    o += hemiciclo(300, 640, 200, 92, sd.ps, "em2027") + rotuloHemi(300, 640, "2027", sd.total2027, 1);
    o += tabelaSenado(620, 1207, 150, 31.5, sd.ps, 20,
      [{ x: 960, rot: "ATUAL", campo: "atual" }, { x: 1085, rot: "2027", campo: "em2027" }, { x: 1207, rot: "SALDO", campo: "saldo" }]);
    if (sd.fonte) o += t(73, 700, sd.fonte, { s: 13, c: C.apagado2 });
    return svg(W, H, o);
  };
  G["senado-v"] = function () {
    var W = 540, H = 960, sd = senado();
    var o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "SENADO FEDERAL", { s: 32, b: true, ls: 1 }) +
      t(53, 106, sd.total2027 + " cadeiras a partir de 2027", { s: 16, c: C.apagado });
    o += hemiciclo(270, 405, 225, 100, sd.ps, "em2027") + rotuloHemi(270, 405, "2027", sd.total2027, 1);
    o += tabelaSenado(40, 505, 452, 28, sd.ps, 19,
      [{ x: 330, rot: "ATUAL", campo: "atual" }, { x: 420, rot: "2027", campo: "em2027" }, { x: 505, rot: "SALDO", campo: "saldo" }]);
    if (sd.fonte) o += t(35, 950, sd.fonte, { s: 12, c: C.apagado2 });
    return svg(W, H, o);
  };

  // ---- Camara dos Deputados: bancadas eleitas (TSE) -------------------------
  function corPartidoCamara(sg, i) {
    var cfg = window.GCTSE_CAMARA || {}, k = String(sg || "").toUpperCase().trim();
    if (cfg.cores && cfg.cores[k]) return cfg.cores[k];
    var sen = ((window.GCTSE_SENADO || {}).partidos || []).filter(function (p) { return String(p.sigla).toUpperCase() === k; })[0];
    if (sen && sen.cor) return sen.cor;
    var reserva = ["#7f8ca3", "#9aa7bd", "#6b7688", "#b0bccf"];
    return reserva[i % reserva.length];
  }
  function camara() {
    var e = window.GCTSE_ESTADOS || {}, cm = e.camara || {}, soma = {}, vagas = 0, eleitos = 0, ufs = 0, finais = 0;
    Object.keys(cm).forEach(function (u) {
      var x = cm[u]; if (!x) return;
      ufs++; vagas += +x.vagas || 0; eleitos += +x.eleitos || 0; if (x.andamento === "f") finais++;
      var ps = x.partidos || {};
      Object.keys(ps).forEach(function (sg) { soma[sg] = (soma[sg] || 0) + (+ps[sg] || 0); });
    });
    var cfg = window.GCTSE_CAMARA || {}, atual = cfg.atual || {}, temAtual = Object.keys(atual).length > 0;
    var lista = Object.keys(soma).map(function (sg) { return { sigla: sg, em2027: soma[sg], atual: +atual[sg] || 0 }; });
    if (temAtual) Object.keys(atual).forEach(function (sg) { if (!(sg in soma)) lista.push({ sigla: sg, em2027: 0, atual: +atual[sg] || 0 }); });
    lista.sort(function (a, b) { return (b.em2027 - a.em2027) || (b.atual - a.atual) || a.sigla.localeCompare(b.sigla); });
    lista.forEach(function (p, i) { p.cor = corPartidoCamara(p.sigla, i); });
    // 513 = total fixo da Camara (LC 78/1993); a soma das vagas so vale com os 27 estados lidos.
    return { ps: lista, vagas: ufs >= 27 && vagas ? vagas : 513, eleitos: eleitos, ufs: ufs, finais: finais, temAtual: temAtual, fonteAtual: cfg.fonte_atual || "" };
  }
  // Tabela com no maximo n linhas: o resto vira "OUTROS (k partidos)".
  function linhasCamara(ps, n) {
    if (ps.length <= n) return ps;
    var resto = ps.slice(n - 1), o = { sigla: "OUTROS (" + resto.length + ")", em2027: 0, atual: 0, cor: "#5c6b82" };
    resto.forEach(function (p) { o.em2027 += p.em2027; o.atual += p.atual; });
    return ps.slice(0, n - 1).concat([o]);
  }
  function tabelaCamara(x0, x1, y, passo, cm, s, n, colX) {
    var lin = linhasCamara(cm.ps, n), cols = cm.temAtual ?
      [{ x: colX[0], rot: "ATUAL", f: function (p) { return String(p.atual); }, c: C.apagado },
       { x: colX[1], rot: "2027", f: function (p) { return String(p.em2027); }, c: C.texto, b: true },
       { x: colX[2], rot: "SALDO", saldo: true }] :
      [{ x: colX[1], rot: "CADEIRAS", f: function (p) { return String(p.em2027); }, c: C.texto, b: true },
       { x: colX[2], rot: "%", f: function (p) { return cm.eleitos ? (p.em2027 / cm.eleitos * 100).toFixed(1).replace(".", ",") + "%" : "—"; }, c: C.apagado }];
    var o = t(x0 + 20, y, "PARTIDO", { s: s - 4, b: true, c: C.apagado, ls: 1 });
    cols.forEach(function (cl) { o += t(cl.x, y, cl.rot, { s: s - 4, b: true, c: C.apagado, a: "end", ls: 1 }); });
    o += r(x0, y + 10, x1 - x0, 1, C.linha);
    lin.forEach(function (p, i) {
      var yy = y + 10 + passo * (i + 1) - passo * 0.3;
      o += '<circle cx="' + (x0 + 7) + '" cy="' + (yy - s * 0.35).toFixed(1) + '" r="' + (s * 0.33).toFixed(1) + '" fill="' + p.cor + '"/>';
      o += t(x0 + 20, yy, p.sigla, { s: s, b: true, max: (cm.temAtual ? colX[0] : colX[1]) - x0 - 85 });
      cols.forEach(function (cl) {
        if (cl.saldo) { var sd = saldo(p); o += t(cl.x, yy, sd.txt, { s: s, b: true, c: sd.c, a: "end" }); }
        else o += t(cl.x, yy, cl.f(p), { s: s, b: !!cl.b, c: cl.c, a: "end" });
      });
    });
    return o;
  }
  // Enquanto o TSE nao define todas as vagas, as cadeiras que faltam aparecem
  // vazias (cor do trilho) no fim do hemiciclo.
  function hemiCamara(cm) {
    var l = linhasCamara(cm.ps, 15), falta = cm.vagas - cm.eleitos;
    return falta > 0 ? l.concat([{ sigla: "", em2027: falta, cor: C.trilho }]) : l;
  }
  function subCamara(cm) {
    if (!cm.ufs) return "aguardando os deputados eleitos (ESTADOS.bat)";
    if (cm.eleitos >= cm.vagas) return cm.vagas + " cadeiras  ·  bancadas eleitas em 2026";
    return cm.eleitos + " de " + cm.vagas + " cadeiras definidas pelo TSE";
  }
  function rodapeCamara(cm) {
    return "Fonte: TSE — deputados federais eleitos" + (cm.temAtual && cm.fonteAtual ? "  ·  composição atual: " + cm.fonteAtual : "");
  }
  G["camara-h"] = function () {
    var W = 1280, H = 720, cm = camara();
    var o = t(73, 57, "CÂMARA DOS DEPUTADOS", { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, subCamara(cm), { s: 19, c: C.apagado });
    // O hemiciclo usa as mesmas linhas da tabela (o "OUTROS" fica cinza nos dois).
    o += hemiciclo(385, 640, 320, 120, hemiCamara(cm), "em2027") + rotuloHemi(385, 640, "2027", cm.eleitos, 1.1);
    o += tabelaCamara(745, 1207, 150, 32, cm, 20, 15, [1010, 1110, 1207]);
    o += t(73, 700, rodapeCamara(cm), { s: 13, c: C.apagado2, max: 1134 });
    return svg(W, H, o);
  };
  G["camara-v"] = function () {
    var W = 540, H = 960, cm = camara();
    var o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "CÂMARA DOS DEPUTADOS", { s: 30, b: true, ls: 1, max: W - 53 - 35 }) +
      t(53, 106, subCamara(cm), { s: 15, c: C.apagado, max: W - 53 - 35 });
    o += hemiciclo(270, 400, 232, 88, hemiCamara(cm), "em2027") + rotuloHemi(270, 400, "2027", cm.eleitos, 1);
    o += tabelaCamara(40, 505, 448, 29, cm, 19, 15, [330, 420, 505]);
    return svg(W, H, o + t(35, 950, rodapeCamara(cm), { s: 11, c: C.apagado2, max: 470 }));
  };

  // ---- Comparativo 2018 x 2022 x 2026: abstencao, brancos e nulos -----------
  // 2026 ao vivo (dados.js); 2022 do arquivo do TSE (estados.js), senao do
  // comparativo-config.js; 2018 do comparativo-config.js.
  var CORES_ANO = ["#5b7db8", "#2b84ff", "#38d9e8"];
  function anosComparativo() {
    var cfg = (window.GCTSE_COMPARATIVO || {}).anos || [], porAno = {};
    cfg.forEach(function (a) { porAno[a.ano] = { ano: a.ano, abstencao: a.abstencao, brancos: a.brancos, nulos: a.nulos }; });
    var ref = (window.GCTSE_ESTADOS || {}).ref2022;
    if (ref && ref.pct_abstencao > 0) porAno[2022] = { ano: 2022, abstencao: ref.pct_abstencao, brancos: ref.pct_brancos, nulos: ref.pct_nulos };
    var b = br(), e = b && b.eleitorado, v = b && b.votos;
    porAno[2026] = { ano: 2026, abstencao: e && e.pct_abstencao > 0 ? e.pct_abstencao : null,
      brancos: v && v.pct_brancos != null && b.secoes && b.secoes.pct > 0 ? v.pct_brancos : null,
      nulos: v && v.pct_nulos != null && b.secoes && b.secoes.pct > 0 ? v.pct_nulos : null };
    return Object.keys(porAno).map(Number).sort().slice(-3).map(function (k) { return porAno[k]; });
  }
  function escalaComp(anos) {
    var m = 0;
    anos.forEach(function (a) { ["abstencao", "brancos", "nulos"].forEach(function (q) { if (a[q] > m) m = a[q]; }); });
    return Math.max(30, Math.ceil((m + 3) / 10) * 10);
  }
  var GRUPOS_COMP = [["abstencao", "ABSTENÇÃO"], ["brancos", "BRANCOS"], ["nulos", "NULOS"]];
  G["comparativo-h"] = function () {
    var W = 1280, H = 720, anos = anosComparativo(), max = escalaComp(anos);
    var o = cabecalhoH(W, "ABSTENÇÃO, BRANCOS E NULOS", "1º turno  ·  " + anos.map(function (a) { return a.ano; }).join(", "));
    var topo = 230, base = 610, alt = base - topo;
    for (var g = 0; g < 10 && g * 10 <= max; g++) {
      var yg = base - alt * (g * 10) / max;
      o += r(73, yg, 1134, 1, C.linha) + t(68, yg + 5, (g * 10) + "%", { s: 13, c: C.apagado2, a: "end" });
    }
    GRUPOS_COMP.forEach(function (gr, gi) {
      var x0 = 95 + gi * 378, cxp = x0 + 175;
      o += t(cxp, 168, gr[1], { s: 28, b: true, a: "middle", ls: 2 });
      anos.forEach(function (a, ai) {
        var x = x0 + 30 + ai * 110, w = 70, val = a[gr[0]];
        o += r(x, topo, w, alt, "rgba(255,255,255,0.08)", 12);
        if (val > 0) { var h = Math.max(6, alt * val / max); o += r(x, base - h, w, h, CORES_ANO[ai] || C.destaque, 12); }
        o += t(x + w / 2, topo - 14, val > 0 ? pct(val) : "—", { s: 21, b: true, a: "middle", c: ai === anos.length - 1 ? C.texto : "#c9d6e6" });
        o += t(x + w / 2, base + 34, String(a.ano), { s: 22, b: true, a: "middle", c: ai === anos.length - 1 ? C.texto : C.apagado });
      });
    });
    o += t(73, 698, "Fonte: TSE  ·  abstenção sobre o eleitorado; brancos e nulos sobre os votos  ·  " +
      (anos.length ? anos[anos.length - 1].ano : "") + " " + subtitulo(), { s: 13, c: C.apagado2, max: 1134 });
    return svg(W, H, o);
  };
  G["comparativo-v"] = function () {
    var W = 540, H = 960, anos = anosComparativo(), max = escalaComp(anos);
    var o = cabecalhoV(W, "ABSTENÇÃO, BRANCOS E NULOS", "1º turno · " + anos.map(function (a) { return a.ano; }).join(", "));
    GRUPOS_COMP.forEach(function (gr, gi) {
      var y0 = 200 + gi * 235;
      o += t(35, y0, gr[1], { s: 26, b: true, ls: 2 });
      anos.forEach(function (a, ai) {
        var y = y0 + 30 + ai * 58, x = 110, w = 280, val = a[gr[0]];
        o += t(35, y + 26, String(a.ano), { s: 20, b: true, c: ai === anos.length - 1 ? C.texto : C.apagado });
        o += r(x, y, w, 36, "rgba(255,255,255,0.08)", 8);
        if (val > 0) o += r(x, y, Math.max(8, w * val / max), 36, CORES_ANO[ai] || C.destaque, 8);
        o += t(505, y + 27, val > 0 ? pct(val) : "—", { s: 24, b: true, a: "end", c: ai === anos.length - 1 ? C.texto : "#c9d6e6" });
      });
    });
    return svg(W, H, o + t(35, 945, "Fonte: TSE · abstenção sobre o eleitorado; brancos e nulos sobre os votos", { s: 11, c: C.apagado2 }));
  };

  // ---- Evolucao minuto a minuto: os 2 primeiros do Brasil -------------------
  // Cada ponto e um boletim do TSE gravado pelo GRAFICOS.bat (hora do TSE,
  // % de urnas, % dos validos). Linha reta entre boletins; nada inventado.
  function evolucao() {
    var d = D(), ev = d.evolucao || {}, pts = comoLista(ev.pontos), cs = candidatos(br()).filter(function (c) { return c.votos > 0; }).slice(0, 2);
    var nomes = ev.nomes || {};
    var lista = pts.map(function (p) {
      var m = /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)/.exec(p.t || "");
      return m ? { ms: new Date(+m[1], m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime(), u: +p.u, c: p.c || {} } : null;
    }).filter(Boolean).sort(function (a, b) { return a.ms - b.ms; });
    var series = cs.map(function (c) {
      return { c: c, cor: cor(c), nome: c.nome || (nomes[c.numero] || {}).nome || c.numero,
        pts: lista.filter(function (p) { return p.c[c.numero] != null; }).map(function (p) { return { ms: p.ms, v: +p.c[c.numero], u: p.u }; }) };
    });
    // Serie com 1 ponto so (log do exibidor guardou so o 1o colocado): avisa na legenda.
    var maxPts = Math.max.apply(null, series.map(function (s) { return s.pts.length; }).concat([0]));
    series.forEach(function (s) { s.soFinal = maxPts >= 2 && s.pts.length === 1; });
    return { series: series, pontos: lista, origem: ev.origem || "" };
  }
  function hhmm(ms) { var x = new Date(ms); return ("0" + x.getHours()).slice(-2) + ":" + ("0" + x.getMinutes()).slice(-2); }
  function pctCurto(v, casas) { return Number(v).toFixed(casas).replace(".", ",") + "%"; }
  var HALO = ' stroke="#0b1220" stroke-width="6" stroke-linejoin="round" paint-order="stroke"';
  // Area do grafico: x0..x1, y0..y1. k = escala das letras.
  function plotEvolucao(ev, x0, x1, y0, y1, k, maxTicks) {
    var ss = ev.series.filter(function (s) { return s.pts.length; }), o = "";
    if (!ss.length) return t((x0 + x1) / 2, (y0 + y1) / 2, br() ? "nenhum boletim gravado ainda" : "aguardando o primeiro boletim do TSE", { s: Math.round(22 * k), c: C.apagado, a: "middle" }) +
      t((x0 + x1) / 2, (y0 + y1) / 2 + 30 * k, "o GRAFICOS.bat grava cada boletim novo do TSE", { s: Math.round(16 * k), c: C.apagado2, a: "middle" });
    var tA = Infinity, tB = -Infinity, vA = Infinity, vB = -Infinity;
    ss.forEach(function (s) { s.pts.forEach(function (p) { tA = Math.min(tA, p.ms); tB = Math.max(tB, p.ms); vA = Math.min(vA, p.v); vB = Math.max(vB, p.v); }); });
    var unico = tB - tA < 1000;
    if (unico) { tA -= 30000; tB += 30000; }
    var span = Math.max(4, vB - vA + 2), passo = span <= 6 ? 1 : span <= 14 ? 2 : span <= 30 ? 5 : 10;
    var lo = Math.floor((vA - 1) / passo) * passo, hi = Math.ceil((vB + 1) / passo) * passo;
    lo = Math.max(0, lo); hi = Math.min(100, hi); if (hi - lo < passo * 2) hi = lo + passo * 2;
    var X = function (ms) { return x0 + (x1 - x0) * (ms - tA) / (tB - tA); };
    var Y = function (v) { return y1 - (y1 - y0) * (v - lo) / (hi - lo); };
    // grade horizontal + 50% em destaque (maioria no 2o turno)
    for (var g = lo; g <= hi + 1e-9; g += passo) {
      var gy = Y(g).toFixed(1), meio = Math.abs(g - 50) < 1e-9;
      o += '<line x1="' + x0 + '" x2="' + x1 + '" y1="' + gy + '" y2="' + gy + '" stroke="' + (meio ? "rgba(255,255,255,0.45)" : "rgba(255,255,255,0.10)") +
        '" stroke-width="' + (meio ? 2 : 1) + '"' + (meio ? ' stroke-dasharray="8 6"' : "") + "/>";
      o += t(x0 - 12 * k, +gy + 6 * k, g + "%", { s: Math.round(16 * k), c: meio ? C.texto : C.apagado, a: "end", b: meio });
    }
    // eixo de horas: intervalo "redondo" que de ate maxTicks marcas
    var min = (tB - tA) / 60000, opc = [1, 2, 5, 10, 15, 20, 30, 60, 120, 180, 240], iv = opc[opc.length - 1];
    for (var i = 0; i < opc.length; i++) if (min / opc[i] <= maxTicks - 1) { iv = opc[i]; break; }
    var ivMs = iv * 60000, primeiro = Math.ceil(tA / ivMs) * ivMs, ultimoX = -1e9;
    var tz = new Date(tA).getTimezoneOffset() * 60000;   // marcas na hora cheia LOCAL
    primeiro = Math.ceil((tA - tz) / ivMs) * ivMs + tz;
    var todos = ev.pontos, marcas = [tA];
    for (var mm = primeiro; mm <= tB; mm += ivMs) if (X(mm) - X(tA) >= 70 * k) marcas.push(mm);
    if (unico) { marcas = [(tA + tB) / 2]; o += t((x0 + x1) / 2, y1 - 24 * k, "1 boletim gravado: a linha começa no próximo boletim do TSE", { s: Math.round(16 * k), c: C.apagado, a: "middle" }); }
    marcas.forEach(function (m) {
      var mx = X(m); if (mx - ultimoX < 70 * k) return; ultimoX = mx;
      o += '<line x1="' + mx.toFixed(1) + '" x2="' + mx.toFixed(1) + '" y1="' + y0 + '" y2="' + y1 + '" stroke="rgba(255,255,255,0.06)"/>';
      o += t(mx, y1 + 26 * k, hhmm(m), { s: Math.round(16 * k), b: true, c: C.apagado, a: "middle" });
      var ant = null; todos.forEach(function (p) { if (p.ms <= m) ant = p; });
      if (ant && ant.u >= 0) o += t(mx, y1 + 46 * k, "urnas " + pctCurto(ant.u, ant.u < 10 ? 1 : 0), { s: Math.round(13 * k), c: C.apagado2, a: "middle" });
    });
    o += '<line x1="' + x0 + '" x2="' + x1 + '" y1="' + y1 + '" y2="' + y1 + '" stroke="rgba(255,255,255,0.25)"/>';
    // virada: ultimo boletim em que o 1o e o 2o trocaram de posicao
    if (ss.length === 2) {
      var a = ss[0], b = ss[1], mapa = {}, virada = null, antes = null;
      b.pts.forEach(function (p) { mapa[p.ms] = p.v; });
      a.pts.forEach(function (p) {
        if (mapa[p.ms] == null) return;
        var sinal = p.v > mapa[p.ms] ? 1 : (p.v < mapa[p.ms] ? -1 : 0);
        if (sinal && antes && sinal !== antes) virada = p.ms;
        if (sinal) antes = sinal;
      });
      if (virada != null) {
        var vx = X(virada).toFixed(1);
        o += '<line x1="' + vx + '" x2="' + vx + '" y1="' + y0 + '" y2="' + y1 + '" stroke="rgba(255,255,255,0.55)" stroke-width="2" stroke-dasharray="4 5"/>';
        o += t(+vx + 8 * k, y0 + 24 * k, "VIRADA · " + hhmm(virada), { s: Math.round(15 * k), b: true, ls: 1, extra: HALO });
      }
    }
    // linhas, pontos inicial/final e rotulos
    var fins = [];
    ss.forEach(function (s) {
      var d = s.pts.map(function (p, j) { return (j ? "L" : "M") + X(p.ms).toFixed(1) + " " + Y(p.v).toFixed(1); }).join(" ");
      o += '<path d="' + d + '" fill="none" stroke="' + s.cor + '" stroke-width="' + (4 * k).toFixed(1) + '" stroke-linejoin="round" stroke-linecap="round"/>';
      var p0 = s.pts[0], pf = s.pts[s.pts.length - 1];
      o += '<circle cx="' + X(p0.ms).toFixed(1) + '" cy="' + Y(p0.v).toFixed(1) + '" r="' + (5 * k).toFixed(1) + '" fill="' + s.cor + '" stroke="#0b1220" stroke-width="2"/>';
      o += '<circle cx="' + X(pf.ms).toFixed(1) + '" cy="' + Y(pf.v).toFixed(1) + '" r="' + (8 * k).toFixed(1) + '" fill="' + s.cor + '" stroke="#ffffff" stroke-width="' + (2.5 * k).toFixed(1) + '"/>';
      fins.push({ s: s, y: Y(pf.v), y0: Y(p0.v), p0: p0, pf: pf });
    });
    // inicio: acima de quem comeca na frente, abaixo de quem comeca atras
    if (fins.length === 2 && fins[0].p0.ms === fins[1].p0.ms && (fins[0].p0.ms !== fins[0].pf.ms)) {
      var cima = fins[0].y0 <= fins[1].y0 ? fins[0] : fins[1], baixo = cima === fins[0] ? fins[1] : fins[0];
      o += t(x0 + 4 * k, cima.y0 - 14 * k, pctCurto(cima.p0.v, 2), { s: Math.round(20 * k), b: true, c: cima.s.cor, extra: HALO });
      o += t(x0 + 4 * k, baixo.y0 + 30 * k, pctCurto(baixo.p0.v, 2), { s: Math.round(20 * k), b: true, c: baixo.s.cor, extra: HALO });
    } else {
      // so uma serie tem linha (a outra so o final): rotulo no inicio dela
      fins.forEach(function (f) {
        // linha que sobe: rotulo embaixo do inicio; que desce: em cima
        if (f.s.pts.length > 1) o += t(X(f.p0.ms) + 4 * k, f.pf.v > f.p0.v ? f.y0 + 30 * k : f.y0 - 14 * k, pctCurto(f.p0.v, 2), { s: Math.round(20 * k), b: true, c: f.s.cor, extra: HALO });
      });
    }
    // fim: valores a direita, afastados se ficarem colados
    fins.sort(function (p, q) { return p.y - q.y; });
    var dist = 40 * k;
    if (fins.length === 2 && fins[1].y - fins[0].y < dist) { var meioY = (fins[0].y + fins[1].y) / 2; fins[0].y = meioY - dist / 2; fins[1].y = meioY + dist / 2; }
    fins.forEach(function (f) { o += t(x1 + 16 * k, f.y + 10 * k, pctCurto(f.pf.v, 2), { s: Math.round(30 * k), b: true, c: C.texto }); });
    return o;
  }
  function legendaEvolucao(ev, x, y, k, maxW) {
    var o = "";
    ev.series.forEach(function (s, i) {
      var xx = x + i * maxW / 2, txt = s.nome + (s.c.partido ? " (" + s.c.partido + ")" : "") + (s.soFinal ? " · só o resultado final" : "");
      o += r(xx, y - 11 * k, 30 * k, 6 * k, s.cor, 3) + t(xx + 40 * k, y, txt, { s: Math.round(19 * k), b: true, max: maxW / 2 - 60 * k });
    });
    return o;
  }
  function rodapeEvolucao(ev) {
    var b = br(), n = ev.pontos.length, exib = ev.origem === "log do exibidor", log = !!ev.origem;
    return "Fonte: TSE · % dos votos válidos a cada atualização (" + n + (n === 1 ? " registro" : " registros") +
      (exib ? ", gravados pelo exibidor: só o 1º colocado a cada ciclo" : (log ? ", gravados pelo sistema de tarjas no ar" : ", horário do TSE")) + ")" +
      (b && b.secoes && b.secoes.pct != null ? " · urnas apuradas " + pct(b.secoes.pct) : "");
  }
  G["evolucao-h"] = function () {
    var W = 1280, H = 720, ev = evolucao();
    var nomes = ev.series.map(function (s) { return s.nome; }).join(" × ");
    var o = cabecalhoH(W, "EVOLUÇÃO DA APURAÇÃO", (nomes ? nomes + "  ·  " : "") + "presidente  ·  " + subtitulo());
    o += legendaEvolucao(ev, 73, 135, 1, 900);
    o += plotEvolucao(ev, 125, 1085, 175, 600, 1, 9);
    o += t(73, 700, rodapeEvolucao(ev), { s: 13, c: C.apagado2, max: 1134 });
    return svg(W, H, o);
  };
  G["evolucao-v"] = function () {
    var W = 540, H = 960, ev = evolucao();
    var o = cabecalhoV(W, "EVOLUÇÃO DA APURAÇÃO", "presidente · " + subtitulo());
    var yy = 200;
    ev.series.forEach(function (s, i) {
      o += r(35, yy + i * 34 - 11, 30, 6, s.cor, 3) + t(75, yy + i * 34, s.nome + (s.c.partido ? " (" + s.c.partido + ")" : "") + (s.soFinal ? " · só o final" : ""), { s: 19, b: true, max: 430 });
    });
    o += plotEvolucao(ev, 85, 410, 290, 820, 0.85, 5);
    return svg(W, H, o + t(35, 945, rodapeEvolucao(ev), { s: 11, c: C.apagado2, max: 470 }));
  };

  // ---- Deputados federais eleitos: N por tela, trocando sozinha -------------
  // Lista do TSE (cargo 6, so quem o TSE marcou eleito), lida pelo
  // ESTADOS.bat. Estados e tempo em web\deputados-config.js. Ordem: regiao
  // (N, NE, CO, SE, S), nome do estado, e no estado do mais votado ao menos.
  var DEP_UF = { ac: "ACRE", al: "ALAGOAS", ap: "AMAPÁ", am: "AMAZONAS", ba: "BAHIA", ce: "CEARÁ", df: "DISTRITO FEDERAL",
    es: "ESPÍRITO SANTO", go: "GOIÁS", ma: "MARANHÃO", mt: "MATO GROSSO", ms: "MATO GROSSO DO SUL", mg: "MINAS GERAIS",
    pa: "PARÁ", pb: "PARAÍBA", pr: "PARANÁ", pe: "PERNAMBUCO", pi: "PIAUÍ", rj: "RIO DE JANEIRO", rn: "RIO GRANDE DO NORTE",
    rs: "RIO GRANDE DO SUL", ro: "RONDÔNIA", rr: "RORAIMA", sc: "SANTA CATARINA", sp: "SÃO PAULO", se: "SERGIPE", to: "TOCANTINS" };
  var DEP_REGIOES = [["Norte", ["ac", "am", "ap", "pa", "ro", "rr", "to"]], ["Nordeste", ["al", "ba", "ce", "ma", "pb", "pe", "pi", "rn", "se"]],
    ["Centro-Oeste", ["df", "go", "ms", "mt"]], ["Sudeste", ["es", "mg", "rj", "sp"]], ["Sul", ["pr", "rs", "sc"]]];
  var T0_DEP = Date.now();   // a troca comeca na 1a tela quando a pagina abre
  // todos = navegacao manual (gerenciador): os 27 estados, mesma ordem.
  function paginasDeputados(todos) {
    var cfg = window.GCTSE_DEPUTADOS || {}, porTela = Math.max(1, Math.min(5, +cfg.por_tela || 5));
    var pedidos = todos ? Object.keys(DEP_UF) : (cfg.estados || []).map(function (u) { return String(u).toLowerCase().trim(); });
    var cm = (window.GCTSE_ESTADOS || {}).camara || {}, pags = [];
    DEP_REGIOES.forEach(function (rg) {
      rg[1].filter(function (u) { return pedidos.indexOf(u) >= 0; })
        .sort(function (a, b) { return DEP_UF[a].localeCompare(DEP_UF[b], "pt-BR"); })
        .forEach(function (u) {
          var x = cm[u], lista = x ? comoLista(x.lista).slice() : [];
          if (!lista.length) return;   // estado ainda sem eleito do TSE: fica fora
          lista.sort(function (a, b) { return ((+b.votos || 0) - (+a.votos || 0)) || String(a.nome).localeCompare(String(b.nome), "pt-BR"); });
          // so os N mais votados de cada estado (deputados-config.js)
          var n = cfg.apenas_mais_votados === false ? Math.ceil(lista.length / porTela) : 1;
          for (var k = 0; k < n; k++) {
            pags.push({ uf: u, regiao: rg[0], x: x, cs: lista.slice(k * porTela, (k + 1) * porTela), ini: k * porTela, k: k, n: n,
              total: lista.length, vagas: +x.vagas || 0 });
          }
        });
    });
    return pags;
  }
  // Navegacao manual: "sp:2" = Sao Paulo, 3a tela do estado (vem do
  // gerenciador pela URL ?dep= ou por comando na saida).
  //   "sp:0" = estado fixo   |   "r-norte" = estados da regiao, trocando sozinho
  function depManual() {
    var v = String(window.__gctseDep || "");
    if (!v) { try { v = new URLSearchParams(location.search).get("dep") || ""; } catch (e) { v = ""; } }
    return /^([a-z]{2}:\d+|r-[a-z-]+)$/.test(v) ? v : "";
  }
  var REG_DEP = { "r-norte": "Norte", "r-nordeste": "Nordeste", "r-centro-oeste": "Centro-Oeste", "r-sudeste": "Sudeste", "r-sul": "Sul" };
  // Telas e tela da vez conforme o modo (automatico, estado fixo, regiao).
  function selecaoDep() {
    var man = depManual(), reg = REG_DEP[man];
    if (reg) {
      var ufsR = ufsDaRegiao(reg), pr = paginasDeputados(true).filter(function (p) { return ufsR.indexOf(p.uf) >= 0; });
      return { pags: pr, ip: indiceDeputados(pr), regiao: reg };
    }
    var ps = paginasDeputados(!!man);
    if (man) {   // estado escolhido sem eleitos ainda: avisa DELE (nunca mostra outro estado)
      var ufM = man.split(":")[0];
      if (!ps.some(function (p) { return p.uf === ufM; })) return { pags: [], ip: 0, regiao: "", faltaUf: ufM };
    }
    return { pags: ps, ip: man ? indiceManual(ps, man) : indiceDeputados(ps), regiao: "" };
  }
  function indiceManual(pags, v) {
    var uf = v.split(":")[0], k = +v.split(":")[1], ult = -1;
    for (var i = 0; i < pags.length; i++) if (pags[i].uf === uf) { ult = i; if (pags[i].k === k) return i; }
    return ult >= 0 ? ult : 0;
  }
  function indiceDeputados(pags) {
    var seg = Math.max(3, +(window.GCTSE_DEPUTADOS || {}).segundos || 8);
    return pags.length ? Math.floor((Date.now() - T0_DEP) / (seg * 1000)) % pags.length : 0;
  }
  function seloDep(x) {
    if (!x) return { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho };
    if (x.andamento === "f") return { texto: "TOTALIZAÇÃO FINAL", cor: C.verde };
    if (x.urnas_pct >= 100) return { texto: "100% DAS URNAS", cor: C.verde };
    return { texto: "PARCIAL", cor: C.vermelho };
  }
  // Foto oficial do TSE: {base}/{ciclo}/{eleicao da Camara}/fotos/{uf}/{sqcand}.jpeg.
  // Embaixo ficam as iniciais: se a foto nao vier, elas aparecem.
  var FOTO_DEP = { falhou: {} };
  window.__gctseFotoD = function (img, ok) {
    if (ok) return;
    FOTO_DEP.falhou[img.getAttribute("href")] = true;
    if (img.parentNode) img.parentNode.removeChild(img);
  };
  function fotoDep(u, c, x, y, w, h) {
    var ini = String(c.nome || "").split(" ").filter(function (p) { return p.length > 2; }).slice(0, 2).map(function (p) { return p.charAt(0); }).join("");
    var o = r(x, y, w, h, "#1c2a40", 4) + t(x + w / 2, y + h / 2 + w * 0.12, ini, { s: Math.round(w * 0.34), b: true, c: C.apagado2, a: "middle" });
    var tse = (window.GCTSE_ESTADOS || {}).tse;
    if (window.GCTSE_FOTOS_DO_TSE !== true || window.__gctseSemFotos || !tse || !tse.base || !c.sqcand) return o;
    var url = tse.base + "/" + tse.ciclo + "/" + (tse.eleicao_camara || tse.eleicao) + "/fotos/" + u + "/" + c.sqcand + ".jpeg";
    if (FOTO_DEP.falhou[url]) return o;
    return o + '<image href="' + esc(url) + '" x="' + x + '" y="' + y + '" width="' + w + '" height="' + h +
      '" preserveAspectRatio="xMidYMin slice" onload="__gctseFotoD(this,true)" onerror="__gctseFotoD(this,false)"/>';
  }
  // Nome em ate 2 linhas, quebrando no espaco que deixa as partes parecidas.
  function linhasNome(nome, n) {
    nome = String(nome || "");
    if (nome.length <= n) return [nome];
    var ps = nome.split(" "), melhor = null;
    for (var i = 1; i < ps.length; i++) {
      var l1 = ps.slice(0, i).join(" "), l2 = ps.slice(i).join(" "), d = Math.max(l1.length, l2.length);
      if (!melhor || d < melhor.d) melhor = { d: d, l: [l1, l2] };
    }
    return melhor ? melhor.l : [nome];
  }
  function situacaoDep(c) {
    var st = String(c.situacao || "").toUpperCase();
    if (/M[ÉE]DIA/.test(st)) return "ELEITO POR MÉDIA";
    if (/QP/.test(st)) return "ELEITO POR QP";
    return st ? "ELEITO" : "";
  }
  function subDep(pg) {
    if (pg.n === 1 && pg.total > pg.cs.length) return "DEPUTADOS FEDERAIS ELEITOS  ·  OS " + pg.cs.length + " MAIS VOTADOS  ·  " + pg.total + " eleitos no estado";
    return "DEPUTADOS FEDERAIS ELEITOS  ·  " + (pg.ini + 1) + "º" + (pg.cs.length > 1 ? " a " + (pg.ini + pg.cs.length) + "º" : "") +
      " mais votados  ·  " + pg.total + (pg.vagas && pg.vagas !== pg.total ? " de " + pg.vagas + " vagas" : " eleitos");
  }
  function semDeputados(W, H, v, uf) {
    var tit = uf ? (DEP_UF[uf] || uf.toUpperCase()) : "DEPUTADOS FEDERAIS ELEITOS";
    var o = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, uf ? tit : "DEPUTADOS FEDERAIS", { s: 32, b: true, ls: 1, max: 450 }) :
      t(73, 57, tit, { s: 36, b: true, ls: 1 }) + (uf ? t(73, 85, "DEPUTADOS FEDERAIS ELEITOS", { s: 18, b: true, c: "#c9d6e6" }) : "");
    return svg(W, H, o + t(W / 2, H / 2, "aguardando os eleitos do TSE" + (uf ? "" : " (ESTADOS.bat)"), { s: v ? 18 : 24, c: C.apagado, a: "middle" }));
  }
  G["deputados-h"] = function () {
    var W = 1280, H = 720, sel = selecaoDep(), pags = sel.pags;
    if (!pags.length) return semDeputados(W, H, false, sel.faltaUf);
    var ip = sel.ip, pg = pags[ip];
    var o = t(73, 57, DEP_UF[pg.uf], { s: 36, b: true, ls: 1, max: W - 73 - 540 }) +
      t(73, 85, subDep(pg), { s: 18, b: true, c: "#c9d6e6", max: W - 146 }) + seloH(W, seloDep(pg.x));
    var gap = 18, w = (1134 - gap * 4) / 5, y = 118, h = 530;
    var x0 = 73 + (5 - pg.cs.length) * (w + gap) / 2;   // ultima tela do estado com menos: centraliza
    pg.cs.forEach(function (c, i) {
      var x = x0 + i * (w + gap), cor = corPartidoCamara(c.partido, 0);
      o += r(x, y, w, h, "rgba(8,14,32,0.80)", 10) + r(x, y, w, 6, cor, 3);
      o += t(x + 16, y + 38, (pg.ini + i + 1) + "º", { s: 20, b: true, c: C.apagado });
      var pw = 174, ph = 232;
      o += fotoDep(pg.uf, c, x + (w - pw) / 2, y + 50, pw, ph);
      var ln = linhasNome(c.nome, 14), yn = y + 318;
      ln.forEach(function (l, j) { o += t(x + w / 2, yn + j * 26, l, { s: 22, b: true, a: "middle", max: w - 20 }); });
      var yp = yn + ln.length * 26 + 2;
      o += t(x + w / 2, yp, c.partido + (c.numero ? "  ·  " + c.numero : ""), { s: 16, c: C.apagado, a: "middle", max: w - 20 });
      o += t(x + w / 2, y + h - 74, inteiro(c.votos), { s: 32, b: true, a: "middle", max: w - 16 });
      o += t(x + w / 2, y + h - 52, "votos", { s: 15, c: C.apagado, a: "middle" });
      var sit = situacaoDep(c);
      if (sit) o += t(x + w / 2, y + h - 20, sit, { s: 13, b: true, c: "#69db7c", a: "middle", ls: 1, max: w - 16 });
    });
    o += t(73, 700, "Fonte: TSE — deputados federais eleitos (situação e votos do TSE)  ·  " + pg.regiao, { s: 13, c: C.apagado2, max: 760 });
    o += t(1207, 700, (sel.regiao ? REG_NOME[sel.regiao] + " · estado " + (ip + 1) + " de " + pags.length : DEP_UF[pg.uf] + (pg.n > 1 ? " " + (pg.k + 1) + "/" + pg.n : "") + "   ·   " + (pg.n > 1 ? "tela " : "estado ") + (ip + 1) + " de " + pags.length), { s: 13, c: C.apagado2, a: "end" });
    return svg(W, H, o);
  };
  G["deputados-v"] = function () {
    var W = 540, H = 960, sel = selecaoDep(), pags = sel.pags;
    if (!pags.length) return semDeputados(W, H, true, sel.faltaUf);
    var ip = sel.ip, pg = pags[ip];
    var o = r(35, 48, 6, 38, C.destaque) + t(53, 80, DEP_UF[pg.uf], { s: 32, b: true, ls: 1, max: W - 53 - 35 }) +
      t(53, 106, "DEPUTADOS FEDERAIS ELEITOS · " + (pg.ini + 1) + "º a " + (pg.ini + pg.cs.length) + "º de " + pg.total,
        { s: 15, b: true, c: "#c9d6e6", max: W - 53 - 35 }) + seloV(W, seloDep(pg.x));
    var y0 = 168, hh = 142, gap = 7;
    pg.cs.forEach(function (c, i) {
      var y = y0 + i * (hh + gap), cor = corPartidoCamara(c.partido, 0);
      o += r(35, y, 470, hh, "rgba(8,14,32,0.80)", 8) + r(35, y, 6, hh, cor, 3);
      o += fotoDep(pg.uf, c, 51, y + 9, 93, 124);
      o += t(160, y + 30, (pg.ini + i + 1) + "º", { s: 16, b: true, c: C.apagado });
      var ln = linhasNome(c.nome, 20);
      ln.forEach(function (l, j) { o += t(160, y + 58 + j * 25, l, { s: 22, b: true, max: 330 }); });
      o += t(160, y + 124, c.partido + (c.numero ? " · " + c.numero : ""), { s: 15, c: C.apagado, max: 170 });
      o += t(493, y + 124, inteiro(c.votos) + " votos", { s: 22, b: true, a: "end", max: 200 });
      var sit = situacaoDep(c);
      if (sit) o += t(493, y + 30, sit, { s: 11, b: true, c: "#69db7c", a: "end", ls: 1 });
    });
    o += t(35, 945, "Fonte: TSE · " + (sel.regiao ? REG_NOME[sel.regiao] + " · estado " + (ip + 1) + " de " + pags.length : DEP_UF[pg.uf] + (pg.n > 1 ? " " + (pg.k + 1) + "/" + pg.n : "") + " · " + (pg.n > 1 ? "tela " : "estado ") + (ip + 1) + " de " + pags.length), { s: 11, c: C.apagado2, max: 470 });
    return svg(W, H, o);
  };

  // =====================================================================
  // 2o TURNO / ESTILO TELAO: apuracao por regiao, presidente com mapa, por
  // regiao e por estado, governadores, 1o x 2o turno. Tudo do TSE: dados.js
  // (presidente; no 2o turno tambem "turno1", o 1o turno guardado) e
  // estados.js (governador, senador).
  // =====================================================================
  var REG_NOME = { "Norte": "NORTE", "Nordeste": "NORDESTE", "Centro-Oeste": "CENTRO-OESTE", "Sudeste": "SUDESTE", "Sul": "SUL" };
  function E() { return window.GCTSE_ESTADOS || {}; }
  // Fonte do presidente: o boletim atual, ou o 1o turno guardado (t1).
  function fontePres(t1) {
    var d = D(), x = d.turno1;
    if (t1 && x && x.br && x.br.tem) {
      var nb = x.br; nb.candidatos = comoLista(nb.candidatos);
      return { br: nb, eleicao: x.eleicao, turno: 1, guardado: true,
        uf: function (k) { var y = (x.ufs || {})[k]; if (!y || !y.tem) return null; y.candidatos = comoLista(y.candidatos); return y; } };
    }
    var b = br();
    return { br: b, eleicao: (d.tse || {}).eleicao, turno: b && candidatos(b).length === 2 ? 2 : 1, guardado: false, uf: uf };
  }
  function temTurno1() { var x = D().turno1; return !!(x && x.br && x.br.tem); }
  function eleitoDe(f, numero) {
    var cs = f.br ? candidatos(f.br) : [];
    for (var i = 0; i < cs.length; i++) if (String(cs[i].numero) === String(numero)) return !!cs[i].eleito;
    return false;
  }
  function urlFotoPres(c, ele) {
    if (!ele || ele === (D().tse || {}).eleicao) return urlFoto(c);
    var tse = D().tse;
    if (window.GCTSE_FOTOS_DO_TSE !== true || window.__gctseSemFotos || !tse || !tse.base || !c || !c.sqcand) return "";
    var url = tse.base + "/" + tse.ciclo + "/" + ele + "/fotos/br/" + c.sqcand + ".jpeg";
    return FOTO.falhou[url] ? "" : url;
  }
  // Silhueta (sem foto) - desenho, nao imagem.
  function silhueta(x, y, w, h, cf) {
    return r(x, y, w, h, cf || "#22324a", 4) +
      '<circle cx="' + (x + w / 2).toFixed(1) + '" cy="' + (y + h * 0.36).toFixed(1) + '" r="' + (w * 0.2).toFixed(1) + '" fill="#5b6c86"/>' +
      '<path d="M' + (x + w * 0.16).toFixed(1) + " " + (y + h).toFixed(1) + " Q" + (x + w * 0.16).toFixed(1) + " " + (y + h * 0.62).toFixed(1) + " " +
      (x + w / 2).toFixed(1) + " " + (y + h * 0.62).toFixed(1) + " Q" + (x + w * 0.84).toFixed(1) + " " + (y + h * 0.62).toFixed(1) + " " +
      (x + w * 0.84).toFixed(1) + " " + (y + h).toFixed(1) + ' Z" fill="#5b6c86"/>';
  }
  // Foto com a silhueta por baixo (se a foto do TSE nao vier, fica a silhueta).
  function fotoOuSilhueta(url, x, y, w, h) {
    var o = silhueta(x, y, w, h);
    if (!url) return o;
    return o + '<image href="' + esc(url) + '" x="' + x + '" y="' + y + '" width="' + w + '" height="' + h +
      '" preserveAspectRatio="xMidYMin slice" onerror="__gctseFotoD(this,false)"/>';
  }
  function etiquetaEleito(x, y, k) {
    k = k || 1;
    return r(x, y, 78 * k, 22 * k, C.verde, 3) + t(x + 39 * k, y + 16 * k, "ELEITO", { s: Math.round(14 * k), b: true, a: "middle", ls: 1 });
  }
  // Mapa com cor por estado (fn devolve a cor, ou null = apagado).
  function mapaCor(x, y, escala, fn, opc) {
    opc = opc || {};
    var M = window.MAPA_BRASIL, out = '<g transform="translate(' + x + " " + y + ") scale(" + escala + ')">', k, e, cc;
    for (k in M.estados) {
      e = M.estados[k]; cc = fn(k);
      out += '<path d="' + e.path + '" fill="' + (cc || opc.apagado || "#1a2840") + '" stroke="' + (opc.borda || C.fundo) +
        '" stroke-width="' + ((opc.esp || 1.2) / escala).toFixed(2) + '" stroke-linejoin="round"/>';
      if (opc.hachura && opc.hachura(k)) out += '<path d="' + e.path + '" fill="url(#hach)" stroke="none"/>';
    }
    if (opc.rotulos) {
      var contorno = ' stroke="' + C.fundo + '" stroke-width="' + (3 / escala).toFixed(2) + '" paint-order="stroke" stroke-linejoin="round"';
      for (k in M.estados) {
        if (opc.rotulos !== "todos" && PEQUENOS.indexOf(k) >= 0) continue;
        if (opc.soRotulo && !opc.soRotulo(k)) continue;
        e = M.estados[k];
        out += '<text x="' + e.cx + '" y="' + (e.cy + 5) + '" font-size="' + ((opc.fonte || 13) / escala).toFixed(1) +
          '" font-weight="700" fill="#fff" text-anchor="middle"' + contorno + ">" + k.toUpperCase() + "</text>";
      }
    }
    return out + "</g>";
  }
  var HACH = '<defs><pattern id="hach" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">' +
    '<rect width="3" height="7" fill="rgba(255,255,255,0.45)"/></pattern></defs>';
  // Soma de varios estados (regiao): votos por candidato e secoes.
  function agregar(f, lista) {
    var soma = {}, ref = {}, tot = 0, sec = 0, secT = 0, n = 0, fim = true;
    lista.forEach(function (k) {
      var x = f.uf(k);
      if (!x) { fim = false; return; }
      n++;
      if (x.secoes) { sec += +x.secoes.totalizadas || 0; secT += +x.secoes.total || 0; }
      if (x.andamento !== "f") fim = false;
      candidatos(x).forEach(function (c) {
        soma[c.numero] = (soma[c.numero] || 0) + (+c.votos || 0); if (!ref[c.numero]) ref[c.numero] = c; tot += +c.votos || 0;
      });
    });
    var cs = Object.keys(soma).map(function (k) {
      var c = ref[k];
      return { numero: k, nome: c.nome, partido: c.partido, sqcand: c.sqcand, votos: soma[k], pct: tot ? 100 * soma[k] / tot : 0 };
    }).sort(function (a, b) { return b.votos - a.votos; });
    return { cs: cs, pctUrnas: secT ? 100 * sec / secT : null, n: n, fim: fim && n === lista.length };
  }
  function ufsDaRegiao(nome) { for (var i = 0; i < DEP_REGIOES.length; i++) if (DEP_REGIOES[i][0] === nome) return DEP_REGIOES[i][1]; return []; }
  function regiaoDaUf(k) { for (var i = 0; i < DEP_REGIOES.length; i++) if (DEP_REGIOES[i][1].indexOf(k) >= 0) return DEP_REGIOES[i][0]; return ""; }
  function barraFina(x, y, w, frac, c) { return r(x, y, w, 8, "rgba(255,255,255,0.14)", 4) + (frac > 0 ? r(x, y, Math.max(6, w * Math.min(1, frac)), 8, c, 4) : ""); }
  function corApuracao(p) {
    if (p == null || !(p > 0)) return null;
    if (p >= 100) return "#16b216";
    if (p >= 75) return "#2f9e5c";
    if (p >= 50) return "#3a8a63";
    if (p >= 25) return "#3d7562";
    return "#3b5f5c";
  }
  function seloDe(f) {
    var b = f.br;
    if (D().modo === "SIMULADO") return { texto: "SIMULADO — NÃO OFICIAL", cor: C.vermelho };
    if (b && b.andamento === "f") return { texto: "TOTALIZAÇÃO FINAL", cor: C.verde };
    var p = b && b.secoes ? b.secoes.pct : null;
    if (!b || !(p > 0)) return { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho };
    if (p >= 100) return { texto: "100% DAS URNAS", cor: C.verde };
    return { texto: "PARCIAL", cor: C.vermelho };
  }
  function turnoTxt(f) { return f.turno === 2 ? "2º TURNO" : "1º TURNO"; }

  // ---- APURACAO por regiao e estado (% de secoes totalizadas) -------------
  function blocoRegiao(f, nome, x, y, w, passo) {
    var ufs = ufsDaRegiao(nome), ag = agregar(f, ufs), p = ag.pctUrnas, o = "";
    o += r(x, y, w, 40, "rgba(255,255,255,0.06)", 6);
    o += rosca(x + 22, y + 20, 13, 6, [{ v: p || 0, c: "#2fd17a" }, { v: 100 - (p || 0), c: "rgba(255,255,255,0.10)" }]);
    o += t(x + 46, y + 26, REG_NOME[nome], { s: 17, b: true, ls: 1, max: w - 150 }) + t(x + w - 10, y + 27, p == null ? "—" : pct(p), { s: 18, b: true, a: "end" });
    ufs.slice().sort(function (a, b) { return DEP_UF[a].localeCompare(DEP_UF[b], "pt-BR"); }).forEach(function (k, i) {
      var x2 = f.uf(k), pu = x2 && x2.secoes ? x2.secoes.pct : null, yy = y + 40 + passo * (i + 1) - 6;
      o += t(x + 12, yy, DEP_UF[k], { s: 13, b: true, c: "#c9d6e6", max: w * 0.5 });
      o += barraFina(x + w * 0.55, yy - 8, w * 0.24, (pu || 0) / 100, pu >= 100 ? C.verde : "#2fd17a");
      o += t(x + w - 10, yy, pu == null ? "—" : Math.floor(pu) + "%", { s: 13, b: true, a: "end" });
    });
    return o;
  }
  G["apuracao-h"] = function () {
    var W = 1280, H = 720, f = fontePres(false), b = f.br, s = b ? b.secoes : null;
    var o = t(73, 57, "APURAÇÃO", { s: 36, b: true, ls: 1 }) + t(73, 85, "seções totalizadas por região e estado  ·  " + turnoTxt(f) + "  ·  " + subtitulo(), { s: 18, c: C.apagado, max: 640 }) + seloH(W, seloDe(f));
    o += blocoRegiao(f, "Norte", 40, 112, 260, 22) + blocoRegiao(f, "Centro-Oeste", 40, 330, 260, 22) + blocoRegiao(f, "Sul", 40, 480, 260, 22);
    o += blocoRegiao(f, "Nordeste", 312, 112, 260, 22) + blocoRegiao(f, "Sudeste", 312, 380, 260, 22);
    o += mapaCor(578, 132, 0.69, function (k) { var x = f.uf(k); return corApuracao(x && x.secoes ? x.secoes.pct : null); }, { rotulos: true, fonte: 12, apagado: "#22324a" });
    var p = s ? s.pct : null;
    o += rosca(1100, 300, 82, 18, [{ v: p || 0, c: "#2fd17a" }, { v: 100 - (p || 0), c: "rgba(255,255,255,0.10)" }]);
    o += t(1100, 305, p == null ? "—" : pct(p), { s: 30, b: true, a: "middle" }) + t(1100, 330, "URNAS APURADAS", { s: 12, b: true, c: C.apagado, a: "middle", ls: 1 });
    o += t(1100, 418, "BRASIL", { s: 22, b: true, a: "middle", ls: 2 });
    if (s && s.total) o += t(1100, 446, inteiro(s.totalizadas) + " de " + inteiro(s.total), { s: 15, c: C.apagado, a: "middle" }) + t(1100, 466, "seções", { s: 13, c: C.apagado2, a: "middle" });
    [["até 25%", "#3b5f5c"], ["25 a 50%", "#3d7562"], ["50 a 75%", "#3a8a63"], ["75 a 99%", "#2f9e5c"], ["100%", "#16b216"]].forEach(function (lg, i) {
      o += r(1010, 520 + i * 24, 14, 14, lg[1], 2) + t(1032, 532 + i * 24, lg[0], { s: 13, c: C.apagado });
    });
    o += t(73, 700, "Fonte: TSE — seções totalizadas do boletim de Presidente de cada estado (sem o exterior nas regiões)", { s: 13, c: C.apagado2, max: 1134 });
    return svg(W, H, o);
  };
  G["apuracao-v"] = function () {
    var W = 540, H = 960, f = fontePres(false), b = f.br, s = b ? b.secoes : null, p = s ? s.pct : null;
    var o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "APURAÇÃO", { s: 32, b: true, ls: 1 }) + t(53, 106, turnoTxt(f) + " · " + subtitulo(), { s: 15, c: C.apagado, max: 450 }) + seloV(W, seloDe(f));
    o += mapaCor(40, 172, 0.5, function (k) { var x = f.uf(k); return corApuracao(x && x.secoes ? x.secoes.pct : null); }, { rotulos: true, fonte: 10, apagado: "#22324a" });
    o += rosca(430, 260, 62, 14, [{ v: p || 0, c: "#2fd17a" }, { v: 100 - (p || 0), c: "rgba(255,255,255,0.10)" }]);
    o += t(430, 266, p == null ? "—" : pct(p), { s: 22, b: true, a: "middle" }) + t(430, 350, "BRASIL", { s: 16, b: true, a: "middle", ls: 2 });
    ["Norte", "Nordeste", "Centro-Oeste", "Sudeste", "Sul"].forEach(function (nome, i) {
      var ag = agregar(f, ufsDaRegiao(nome)), pp = ag.pctUrnas, y = 520 + i * 82;
      o += r(35, y, 470, 70, "rgba(8,14,32,0.78)", 8) + t(55, y + 30, REG_NOME[nome], { s: 20, b: true, ls: 1 });
      o += t(485, y + 31, pp == null ? "—" : pct(pp), { s: 22, b: true, a: "end" }) + barraFina(55, y + 46, 430, (pp || 0) / 100, "#2fd17a");
    });
    return svg(W, H, o + t(35, 945, "Fonte: TSE — seções totalizadas de Presidente", { s: 11, c: C.apagado2 }));
  };

  // ---- PRESIDENTE com MAPA (quem lidera cada estado) ----------------------
  function liderF(f, k) { var x = f.uf(k), cs = x ? candidatos(x) : []; return cs.length && cs[0].votos > 0 ? cs[0] : null; }
  function placarF(f) { var n = {}; Object.keys(DEP_UF).forEach(function (k) { var l = liderF(f, k); if (l) n[l.numero] = (n[l.numero] || 0) + 1; }); return n; }
  function cartaoMapa(f, c, x, y, w, h, nEst, k) {
    var cc = cor(c), o = r(x, y, w, h, "rgba(8,14,32,0.82)", 8) + r(x, y, 8, h, cc, 4);
    var url = urlFotoPres(c, f.eleicao), fw = (h - 20) * 0.75;
    o += fotoOuSilhueta(url, x + 20, y + 10, fw, h - 20);
    var tx = x + 36 + fw;
    o += t(tx, y + 32 * k, c.nome, { s: Math.round(22 * k), b: true, max: w - (tx - x) - (eleitoDe(f, c.numero) ? 112 * k : 20) });
    o += t(tx, y + 54 * k, c.partido, { s: Math.round(15 * k), c: C.apagado });
    o += t(tx, y + h - 18 * k, pct(c.pct), { s: Math.round(38 * k), b: true });
    o += t(x + w - 16, y + h - 34 * k, "NA FRENTE EM", { s: Math.round(12 * k), b: true, c: C.apagado, a: "end", ls: 1 });
    o += t(x + w - 16, y + h - 14 * k, (nEst || 0) + (nEst === 1 ? " ESTADO" : " ESTADOS"), { s: Math.round(17 * k), b: true, a: "end" });
    if (eleitoDe(f, c.numero)) o += etiquetaEleito(x + w - 16 - 78 * k, y + 14 * k, k);
    return o;
  }
  function telaPresMapa(t1, v) {
    var f = fontePres(t1), cs = f.br ? candidatos(f.br).filter(function (c) { return c.votos > 0 || f.turno === 2; }) : [];
    var nCards = f.turno === 2 ? 2 : 3, pl = placarF(f), o;
    var tit = "PRESIDENTE — " + turnoTxt(f), sub = (f.guardado ? "resultado final do 1º turno" : subtitulo()) + "  ·  cor = quem lidera no estado";
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, tit, { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, sub, { s: 18, c: C.apagado, max: 640 }) + seloH(W, seloDe(f));
      var hc = nCards === 2 ? 190 : 150, gap = 18;
      for (var i = 0; i < nCards; i++) o += cs[i] ? cartaoMapa(f, cs[i], 73, 130 + i * (hc + gap), 560, hc, pl[cs[i].numero], nCards === 2 ? 1.15 : 1) : "";
      o += mapaCor(690, 112, 0.86, function (k) { var l = liderF(f, k); return l ? cor(l) : null; }, { rotulos: true, fonte: 13 });
      var b = f.br, s = b ? b.secoes : null;
      o += t(73, 700, "Fonte: TSE" + (s ? "  ·  urnas apuradas " + pct(s.pct) : ""), { s: 13, c: C.apagado2 });
      return svg(W, H, o);
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 30, b: true, ls: 1, max: 450 }) + t(53, 106, sub, { s: 13, c: C.apagado, max: 450 }) + seloV(W2, seloDe(f));
    var hv = nCards === 2 ? 150 : 118;
    for (var j = 0; j < nCards; j++) o += cs[j] ? cartaoMapa(f, cs[j], 35, 170 + j * (hv + 12), 470, hv, pl[cs[j].numero], 0.82) : "";
    o += mapaCor(85, 170 + nCards * (hv + 12) + 10, 0.6, function (k) { var l = liderF(f, k); return l ? cor(l) : null; }, { rotulos: true, fonte: 10 });
    return svg(W2, H2, o + t(35, 945, "Fonte: TSE", { s: 11, c: C.apagado2 }));
  }
  G["presmapa-h"] = function () { return telaPresMapa(false, false); };
  G["presmapa-v"] = function () { return telaPresMapa(false, true); };
  G["presmapa1t-h"] = function () { return telaPresMapa(true, false); };
  G["presmapa1t-v"] = function () { return telaPresMapa(true, true); };

  // ---- PRESIDENTE | REGIOES (5 colunas com mini-mapa) ----------------------
  function cartaoMini(f, c, x, y, w, h) {
    var cc = cor(c), o = r(x, y, w, h, "rgba(8,14,32,0.82)", 6) + r(x, y, 5, h, cc, 2);
    o += fotoOuSilhueta(urlFotoPres(c, f.eleicao), x + 10, y + 7, (h - 14) * 0.75, h - 14);
    var tx = x + 18 + (h - 14) * 0.75;
    o += t(tx, y + 20, c.nome, { s: 13, b: true, max: w - (tx - x) - 8 });
    o += t(tx, y + 35, c.partido + " · " + inteiro(c.votos) + " votos", { s: 10, c: C.apagado, max: w - (tx - x) - 8 });
    o += t(x + w - 8, y + h - 9, pct(c.pct), { s: 24, b: true, a: "end", max: w - (tx - x) - 8 });
    if (eleitoDe(f, c.numero)) o += r(x + w - 58, y + 6, 50, 15, C.verde, 2) + t(x + w - 33, y + 17, "ELEITO", { s: 10, b: true, a: "middle" });
    return o;
  }
  function telaRegioes(t1, v) {
    var f = fontePres(t1), nomes = ["Norte", "Nordeste", "Centro-Oeste", "Sudeste", "Sul"], nC = f.turno === 2 ? 2 : 3, o;
    var tit = "PRESIDENTE  |  REGIÕES", sub = turnoTxt(f) + "  ·  " + (f.guardado ? "resultado final do 1º turno" : subtitulo()) + "  ·  soma dos estados (sem o exterior)";
    if (!v) {
      var W = 1280, H = 720, w = (1134 - 4 * 14) / 5;
      o = t(73, 57, tit, { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, sub, { s: 16, c: C.apagado, max: 660 }) + seloH(W, seloDe(f));
      nomes.forEach(function (nome, i) {
        var x = 73 + i * (w + 14), ufs = ufsDaRegiao(nome), ag = agregar(f, ufs);
        o += t(x, 134, REG_NOME[nome], { s: 22, b: true, ls: 1, max: w });
        o += barraFina(x, 146, w - 86, (ag.pctUrnas || 0) / 100, "#2fd17a") + t(x + w, 155, ag.pctUrnas == null ? "—" : pct(ag.pctUrnas), { s: 15, b: true, a: "end" });
        o += mapaCor(x + 12, 170, 0.3, function (k) { if (ufs.indexOf(k) < 0) return null; var l = liderF(f, k); return l ? cor(l) : "#3a4c66"; }, { apagado: "#1f2d45", esp: 0.8 });
        var hC = nC === 2 ? 120 : 88;
        for (var j = 0; j < nC; j++) if (ag.cs[j]) o += cartaoMini(f, ag.cs[j], x, 380 + j * (hC + 8), w, hC);
      });
      return svg(W, H, o + t(73, 700, "Fonte: TSE — boletins de Presidente dos estados", { s: 13, c: C.apagado2 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "PRESIDENTE | REGIÕES", { s: 28, b: true, ls: 1, max: 450 }) + t(53, 106, turnoTxt(f) + " · soma dos estados", { s: 14, c: C.apagado }) + seloV(W2, seloDe(f));
    nomes.forEach(function (nome, i) {
      var y = 168 + i * 154, ufs = ufsDaRegiao(nome), ag = agregar(f, ufs);
      o += r(35, y, 470, 144, "rgba(8,14,32,0.82)", 8);
      o += mapaCor(42, y + 10, 0.2, function (k) { if (ufs.indexOf(k) < 0) return null; var l = liderF(f, k); return l ? cor(l) : "#3a4c66"; }, { apagado: "#1f2d45", esp: 0.6 });
      o += t(175, y + 30, REG_NOME[nome], { s: 20, b: true, ls: 1 }) + t(493, y + 30, ag.pctUrnas == null ? "—" : "urnas " + pct(ag.pctUrnas), { s: 13, c: C.apagado, a: "end" });
      for (var j = 0; j < 2; j++) {
        var c = ag.cs[j]; if (!c) continue;
        var yy = y + 66 + j * 40;
        o += r(175, yy - 15, 6, 22, cor(c), 2) + t(189, yy, c.nome, { s: 16, b: true, max: 200 }) + t(493, yy, pct(c.pct), { s: 22, b: true, a: "end" });
        o += barraFina(189, yy + 9, 300, c.pct / 100, cor(c));
      }
    });
    return svg(W2, H2, o + t(35, 945, "Fonte: TSE", { s: 11, c: C.apagado2 }));
  }
  G["regioes-h"] = function () { return telaRegioes(false, false); };
  G["regioes-v"] = function () { return telaRegioes(false, true); };

  // ---- PRESIDENTE | ESTADO ou REGIAO (escolhido no gerenciador) ------------
  // alvo: sigla do estado ("sp") ou regiao ("norte"); vem da URL (?a=) ou do
  // rodizio ("presloc:sp").
  var ALVOS_REG = { norte: "Norte", nordeste: "Nordeste", "centro-oeste": "Centro-Oeste", centrooeste: "Centro-Oeste", sudeste: "Sudeste", sul: "Sul" };
  function alvoAtual() {
    var a = String(window.__gctseAlvo || "").toLowerCase();
    if (!a) { try { a = (new URLSearchParams(location.search).get("a") || "").toLowerCase(); } catch (e) { a = ""; } }
    return a || "sp";
  }
  function telaPresLoc(v) {
    var f = fontePres(false), a = alvoAtual(), reg = ALVOS_REG[a], ufs, nomeA, cs, pu, fim;
    if (reg) { ufs = ufsDaRegiao(reg); nomeA = REG_NOME[reg]; var ag = agregar(f, ufs); cs = ag.cs; pu = ag.pctUrnas; fim = ag.fim; }
    else { ufs = [a]; nomeA = DEP_UF[a] || a.toUpperCase(); var x = f.uf(a); cs = x ? candidatos(x) : []; pu = x && x.secoes ? x.secoes.pct : null; fim = x && x.andamento === "f"; }
    cs = cs.filter(function (c) { return c.votos > 0 || f.turno === 2; });
    var corMapa = function (k) { if (ufs.indexOf(k) < 0) return null; var l = liderF(f, k); return l ? cor(l) : "#3a4c66"; };
    var o, n = f.turno === 2 ? 2 : 6, tit = "PRESIDENTE  |  " + nomeA;
    var sl = fim ? { texto: "TOTALIZAÇÃO FINAL", cor: C.verde } : (pu >= 100 ? { texto: "100% DAS URNAS", cor: C.verde } : (pu > 0 ? { texto: "PARCIAL", cor: C.vermelho } : { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho }));
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, tit, { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, turnoTxt(f) + "  ·  urnas apuradas " + (pu == null ? "—" : pct(pu)) + "  ·  " + subtitulo(), { s: 18, c: C.apagado, max: 640 }) + seloH(W, sl);
      o += barraFina(73, 112, 360, (pu || 0) / 100, "#2fd17a");
      o += mapaCor(60, 150, 0.68, corMapa, { rotulos: true, fonte: 12, soRotulo: function (k) { return ufs.indexOf(k) >= 0; }, apagado: "#1c2a40" });
      var hr = n === 2 ? 150 : 86, gap = n === 2 ? 24 : 8;
      for (var i = 0; i < n; i++) {
        var c = cs[i]; if (!c) continue;
        var y = 130 + i * (hr + gap), x0 = 520, w = 687, cc = cor(c);
        o += r(x0, y, w, hr, "rgba(8,14,32,0.82)", 8) + r(x0, y, 8, hr, cc, 4);
        var fh = hr - 14, fw = fh * 0.75;
        o += fotoOuSilhueta(urlFotoPres(c, f.eleicao), x0 + 18, y + 7, fw, fh);
        var tx = x0 + 32 + fw, k = n === 2 ? 1.3 : 1;
        o += t(tx, y + 26 * k, c.nome + "  |  " + c.partido, { s: Math.round(19 * k), b: true, max: w - (tx - x0) - 200 });
        o += barraFina(tx, y + hr / 2 + 2, w - (tx - x0) - (n === 2 ? 290 : 210), c.pct / 100, cc);
        o += t(tx, y + hr - 14, inteiro(c.votos) + " votos", { s: Math.round(15 * k), c: C.apagado });
        o += t(x0 + w - 20, y + hr / 2 + 16 * k, pct(c.pct), { s: Math.round(36 * k), b: true, a: "end" });
        if (eleitoDe(f, c.numero)) o += etiquetaEleito(x0 + w - 20 - 78, y + 8, 1);
      }
      if (!cs.length) o += t(860, 360, "aguardando o boletim do TSE", { s: 22, c: C.apagado, a: "middle" });
      return svg(W, H, o + t(73, 700, "Fonte: TSE" + (reg ? " — soma dos estados da região" : ""), { s: 13, c: C.apagado2 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 28, b: true, ls: 1, max: 450 }) + t(53, 106, turnoTxt(f) + " · urnas " + (pu == null ? "—" : pct(pu)), { s: 15, c: C.apagado }) + seloV(W2, sl);
    o += mapaCor(140, 168, 0.42, corMapa, { apagado: "#1c2a40", esp: 0.8 });
    var nv = Math.min(n, 4), hv = nv === 2 ? 170 : 108;
    for (var j = 0; j < nv; j++) {
      var cv = cs[j]; if (!cv) continue;
      var yv = 452 + j * (hv + 10), ccv = cor(cv);
      o += r(35, yv, 470, hv, "rgba(8,14,32,0.82)", 8) + r(35, yv, 7, hv, ccv, 3);
      o += fotoOuSilhueta(urlFotoPres(cv, f.eleicao), 50, yv + 8, (hv - 16) * 0.75, hv - 16);
      var txv = 62 + (hv - 16) * 0.75;
      o += t(txv, yv + 30, cv.nome, { s: 19, b: true, max: 493 - txv }) + t(txv, yv + 50, cv.partido, { s: 13, c: C.apagado });
      o += t(493, yv + hv - 16, pct(cv.pct), { s: nv === 2 ? 40 : 30, b: true, a: "end" }) + t(txv, yv + hv - 16, inteiro(cv.votos) + " votos", { s: 13, c: C.apagado });
      if (eleitoDe(f, cv.numero)) o += etiquetaEleito(493 - 78, yv + 8, 1);
    }
    return svg(W2, H2, o + t(35, 945, "Fonte: TSE", { s: 11, c: C.apagado2 }));
  }
  G["presloc-h"] = function () { return telaPresLoc(false); };
  G["presloc-v"] = function () { return telaPresLoc(true); };

  // ---- GOVERNADORES: foto por estado + mapa --------------------------------
  // Situacao de cada estado (estados.js; no 2o turno o coletor junta 1o e 2o).
  //  eleito1 (verde): eleito no 1o turno - foto com borda verde
  //  eleito2 (azul): eleito no 2o turno - foto com borda azul
  //  segundo (azul, hachurado): aguardando o 2o turno - sem foto
  //  apurando / vazio (cinza)
  var COR_T1 = "#16b216", COR_T2 = "#2b84ff";
  function govEstado(k) {
    var u = (E().ufs || {})[k], g = u && u.gov && u.gov.tem ? u.gov : null;
    if (!g) return { tipo: "vazio" };
    var cs = comoLista(g.candidatos), el = cs.filter(function (c) { return c.eleito; })[0];
    var turno = +g.turno || (E().turno === 2 ? 2 : 1);
    if (el) return { tipo: turno === 2 ? "eleito2" : "eleito1", c: el, g: g };
    if (turno === 2 || cs.some(function (c) { return c.segundo_turno; })) return { tipo: "segundo", g: g, cs: cs.slice(0, 2) };
    return { tipo: (g.urnas_pct > 0 ? "apurando" : "vazio"), g: g, c: cs[0] };
  }
  function urlFotoGov(k, st) {
    var tse = E().tse;
    if (window.GCTSE_FOTOS_DO_TSE !== true || window.__gctseSemFotos || !tse || !tse.base || !st.c || !st.c.sqcand) return "";
    var url = tse.base + "/" + tse.ciclo + "/" + (st.g.eleicao || tse.eleicao) + "/fotos/" + k + "/" + st.c.sqcand + ".jpeg";
    return FOTO_DEP.falhou[url] ? "" : url;
  }
  function corGov(k, modoPartido) {
    var st = govEstado(k);
    if (modoPartido) return (st.tipo === "eleito1" || st.tipo === "eleito2") ? corPartidoCamara(st.c.partido, 0) : (st.tipo === "segundo" ? "#3a4c66" : null);
    return st.tipo === "eleito1" ? COR_T1 : (st.tipo === "eleito2" || st.tipo === "segundo") ? COR_T2 : null;
  }
  // Cartao: sigla em cima, foto, e a barrinha com o nome do eleito embaixo
  // (aguardando: "2º TURNO"). fn = tamanho da letra do nome.
  function cartaoGov(k, x, y, w, h, modoPartido, fn) {
    var st = govEstado(k), borda = corGov(k, modoPartido) || "#3a4c66", o = "", eleito = st.tipo === "eleito1" || st.tipo === "eleito2";
    fn = fn || 10;
    var hl = Math.round(fn * 1.6), hb = Math.round(fn * 2.6);   // sigla e barra do nome
    o += r(x, y, w, hl, borda, 3) + t(x + w / 2, y + hl * 0.74, k.toUpperCase(), { s: Math.round(fn * 1.15), b: true, a: "middle", ls: 1 });
    var fy = y + hl + 2, fh = h - hl - 2 - hb;
    o += r(x - 2, fy - 2, w + 4, fh + hb + 4, borda, 4);
    if (eleito) o += fotoOuSilhueta(urlFotoGov(k, st), x, fy, w, fh);
    else o += silhueta(x, fy, w, fh);
    if (st.tipo === "segundo") o += '<rect x="' + x + '" y="' + fy + '" width="' + w + '" height="' + fh + '" fill="url(#hach)" opacity="0.35"/>';
    o += r(x, fy + fh, w, hb, "#0b1220", 0);
    if (eleito && st.c) {
      var ln = linhasNome(st.c.nome, Math.max(8, Math.round(w / (fn * 0.62))));
      if (ln.length === 1) o += t(x + w / 2, fy + fh + hb * 0.62, ln[0], { s: fn, b: true, a: "middle", max: w - 4 });
      else ln.forEach(function (l, j) { o += t(x + w / 2, fy + fh + hb * (j ? 0.86 : 0.43), l, { s: Math.round(fn * 0.92), b: true, a: "middle", max: w - 4 }); });
    } else {
      var tx = st.tipo === "segundo" ? "2º TURNO" : (st.tipo === "apurando" ? "APURANDO" : "—");
      o += t(x + w / 2, fy + fh + hb * 0.62, tx, { s: Math.round(fn * 0.9), b: true, c: st.tipo === "segundo" ? "#7fb8ff" : C.apagado, a: "middle", max: w - 4 });
    }
    return o;
  }
  function contaGov() {
    var n = { eleito1: 0, eleito2: 0, segundo: 0, apurando: 0, vazio: 0 };
    Object.keys(DEP_UF).forEach(function (k) { n[govEstado(k).tipo]++; });
    return n;
  }
  function legendaGov(x, y, modoPartido, vertical) {
    var o = "", n = contaGov();
    if (!modoPartido) {
      var itens = [[COR_T1, "ELEITOS NO 1º TURNO", n.eleito1, false], [COR_T2, "ELEITOS NO 2º TURNO", n.eleito2, false], [COR_T2, "AGUARDANDO 2º TURNO", n.segundo, true]];
      if (n.apurando + n.vazio > 0) itens.push(["#3a4c66", "EM APURAÇÃO / SEM DADO", n.apurando + n.vazio, false]);
      itens.forEach(function (it, i) {
        var cw = vertical ? 235 : 255, xx = x + (i % 2) * cw, yy = y + Math.floor(i / 2) * 32;
        o += r(xx, yy - 14, 18, 18, it[0], 3) + (it[3] ? '<rect x="' + xx + '" y="' + (yy - 14) + '" width="18" height="18" fill="url(#hach)"/>' : "");
        o += t(xx + 26, yy, it[1], { s: 12, b: true, c: "#c9d6e6", ls: 1, max: cw - 70 }) + t(xx + cw - 14, yy, String(it[2]), { s: 18, b: true, a: "end" });
      });
      return o;
    }
    var pp = {};
    Object.keys(DEP_UF).forEach(function (k) { var st = govEstado(k); if (st.c && (st.tipo === "eleito1" || st.tipo === "eleito2")) pp[st.c.partido] = (pp[st.c.partido] || 0) + 1; });
    var ls = Object.keys(pp).sort(function (a, b) { return pp[b] - pp[a] || a.localeCompare(b); });
    // partidos + "2o turno" na mesma grade (4 por linha)
    var itensP = ls.map(function (sg, i) { return [corPartidoCamara(sg, i), sg + " " + pp[sg], false]; });
    if (n.segundo) itensP.push(["#3a4c66", "2º TURNO " + n.segundo, true]);
    var porLinha = 4, cwp = vertical ? 117 : 128;
    itensP.forEach(function (it, i) {
      var xx = x + (i % porLinha) * cwp, yy = y + Math.floor(i / porLinha) * 28;
      o += r(xx, yy - 13, 16, 16, it[0], 3) + (it[2] ? '<rect x="' + xx + '" y="' + (yy - 13) + '" width="16" height="16" fill="url(#hach)"/>' : "");
      o += t(xx + 22, yy, it[1], { s: 13, b: true, max: cwp - 28 });
    });
    return o;
  }
  var GRADE_GOV = [["ac", "al", "am", "ap", "ba", "ce", "df"], ["es", "go", "ma", "mg", "ms", "mt", "pa"], ["pb", "pe", "pi", "pr", "rj", "rn", "ro"], ["rr", "rs", "sc", "se", "sp", "to"]];
  function telaGov(v, modoPartido) {
    var n = contaGov(), o;
    var ne = n.eleito1 + n.eleito2, sub = ne + (ne === 1 ? " eleito" : " eleitos") + "  ·  " + (modoPartido ? "cor = partido do eleito; hachurado = 2º turno" : "verde = 1º turno · azul = 2º turno");
    var hachTem = function (k) { return govEstado(k).tipo === "segundo"; };
    var sl = n.segundo + n.apurando + n.vazio === 0 ? { texto: "TODOS DEFINIDOS", cor: C.verde } : { texto: n.segundo ? n.segundo + " NO 2º TURNO" : "PARCIAL", cor: n.segundo ? C.destaque : C.vermelho };
    if (!v) {
      var W = 1280, H = 720;
      o = HACH + t(73, 57, "GOVERNADORES", { s: 36, b: true, ls: 1 }) + t(73, 85, sub, { s: 18, c: C.apagado, max: 640 }) + seloH(W, sl);
      var cw = 74, ch = 126, gx = 10, gy = 8;
      GRADE_GOV.forEach(function (lin, li) {
        var x0 = 70 + (li === 3 ? (cw + gx) / 2 : 0);
        lin.forEach(function (k, ci) { o += cartaoGov(k, x0 + ci * (cw + gx), 110 + li * (ch + gy), cw, ch, modoPartido, 10); });
      });
      o += mapaCor(700, 112, 0.74, function (k) { return corGov(k, modoPartido); }, { rotulos: true, fonte: 12, apagado: "#22324a", hachura: hachTem });
      o += legendaGov(700, 626, modoPartido, false);
      return svg(W, H, o + t(73, 700, "Fonte: TSE — situação de cada candidato a Governador" + (E().turno === 2 ? " (1º e 2º turno)" : ""), { s: 13, c: C.apagado2 }));
    }
    var W2 = 540, H2 = 960;
    o = HACH + r(35, 48, 6, 38, C.destaque) + t(53, 80, "GOVERNADORES", { s: 32, b: true, ls: 1 }) + t(53, 106, sub, { s: 13, c: C.apagado, max: 450 }) + seloV(W2, sl);
    o += mapaCor(126, 158, 0.47, function (k) { return corGov(k, modoPartido); }, { rotulos: true, fonte: 9, apagado: "#22324a", hachura: hachTem });
    var cw2 = 60, ch2 = 92, gx2 = 7, todos = [].concat.apply([], GRADE_GOV);
    todos.forEach(function (k, i) {
      var li = Math.floor(i / 7), ci = i % 7, x0 = 36 + (li === 3 ? (cw2 + gx2) / 2 : 0);
      o += cartaoGov(k, x0 + ci * (cw2 + gx2), 470 + li * (ch2 + 6), cw2, ch2, modoPartido, 8);
    });
    return svg(W2, H2, o + legendaGov(36, 888, modoPartido, true));
  }
  G["governadores-h"] = function () { return telaGov(false, false); };
  G["governadores-v"] = function () { return telaGov(true, false); };
  G["govpartido-h"] = function () { return telaGov(false, true); };
  G["govpartido-v"] = function () { return telaGov(true, true); };

  // ---- 1o x 2o TURNO: abstencao, brancos, nulos, comparecimento ------------
  function numsTurno(b) {
    if (!b || !b.tem) return null;
    var e = b.eleitorado || {}, v = b.votos || {};
    return { abst: e.pct_abstencao, comp: e.pct_comparec, brancos: v.pct_brancos, nulos: v.pct_nulos,
      nAbst: e.abstencao, nComp: e.comparecimento, nBr: v.brancos, nNu: v.nulos, urnas: b.secoes ? b.secoes.pct : null };
  }
  function telaTurnos(v) {
    var d = D(), t1 = d.turno1 && d.turno1.br && d.turno1.br.tem ? numsTurno(d.turno1.br) : null, f = fontePres(false);
    var t2 = f.turno === 2 ? numsTurno(f.br) : null, o;
    var itens = [["COMPARECIMENTO", "comp", "nComp", "eleitores votaram"], ["ABSTENÇÃO", "abst", "nAbst", "eleitores não votaram"],
      ["BRANCOS", "brancos", "nBr", "votos em branco"], ["NULOS", "nulos", "nNu", "votos nulos"]];
    var tit = "1º × 2º TURNO", sub = "Presidente · Brasil · " + (t2 ? "2º turno: " + (t2.urnas != null ? "urnas " + pct(t2.urnas) : "aguardando") : "o 2º turno ainda não começou");
    var cor1 = "#7398cf", cor2 = "#2fd17a";
    function dif(a, b) { if (a == null || b == null) return ""; var dd = b - a; return (dd > 0 ? "+" : dd < 0 ? "−" : "") + Math.abs(dd).toFixed(2).replace(".", ",") + " p.p."; }
    if (!t1) {
      var Wx = v ? 540 : 1280, Hx = v ? 960 : 720;
      return svg(Wx, Hx, t(v ? 53 : 73, v ? 80 : 57, tit, { s: v ? 32 : 36, b: true, ls: 1 }) +
        t(Wx / 2, Hx / 2, "disponível no 2º turno (o 1º turno é guardado pelo GRAFICOS.bat)", { s: v ? 15 : 22, c: C.apagado, a: "middle", max: Wx - 60 }));
    }
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, tit, { s: 36, b: true, ls: 1 }) + t(73, 85, sub, { s: 18, c: C.apagado, max: 640 }) + seloH(W, seloDe(f));
      o += r(760, 108, 14, 14, cor1, 2) + t(780, 120, "1º TURNO (final)", { s: 14, b: true, c: "#c9d6e6" }) + r(960, 108, 14, 14, cor2, 2) + t(980, 120, "2º TURNO", { s: 14, b: true, c: "#c9d6e6" });
      itens.forEach(function (it, i) {
        var y = 150 + i * 132, a = t1[it[1]], b2 = t2 ? t2[it[1]] : null, max = it[1] === "comp" ? 100 : Math.max(10, (a || 0) * 1.3, (b2 || 0) * 1.3);
        o += r(73, y, 1134, 116, "rgba(8,14,32,0.78)", 10) + t(100, y + 40, it[0], { s: 24, b: true, ls: 1 });
        var dd = dif(a, b2); if (dd) o += t(100, y + 76, dd, { s: 22, b: true, c: "#ffd43b" }) + t(100, y + 98, "do 1º para o 2º turno", { s: 12, c: C.apagado });
        [[a, cor1, "1º", t1[it[2]]], [b2, cor2, "2º", t2 ? t2[it[2]] : null]].forEach(function (z, j) {
          var yy = y + 26 + j * 46;
          o += t(400, yy + 20, z[2], { s: 16, b: true, c: C.apagado });
          o += r(430, yy, 560, 28, "rgba(255,255,255,0.08)", 6) + (z[0] > 0 ? r(430, yy, Math.max(8, 560 * z[0] / max), 28, z[1], 6) : "");
          o += t(1180, yy + 22, z[0] == null ? "—" : pct(z[0]), { s: 24, b: true, a: "end" });
          if (z[3] != null) o += t(1180, yy + 40, inteiro(z[3]) + " " + it[3], { s: 11, c: C.apagado, a: "end" });
        });
      });
      return svg(W, H, o + t(73, 700, "Fonte: TSE · comparecimento e abstenção sobre o eleitorado; brancos e nulos sobre os votos · 2º turno parcial até o fim", { s: 13, c: C.apagado2, max: 1134 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 32, b: true, ls: 1 }) + t(53, 106, sub, { s: 13, c: C.apagado, max: 450 }) + seloV(W2, seloDe(f));
    itens.forEach(function (it, i) {
      var y = 172 + i * 190, a = t1[it[1]], b2 = t2 ? t2[it[1]] : null, max = it[1] === "comp" ? 100 : Math.max(10, (a || 0) * 1.3, (b2 || 0) * 1.3);
      o += r(35, y, 470, 176, "rgba(8,14,32,0.78)", 10) + t(55, y + 36, it[0], { s: 22, b: true, ls: 1 });
      var dd = dif(a, b2); if (dd) o += t(485, y + 36, dd, { s: 18, b: true, c: "#ffd43b", a: "end" });
      [[a, cor1, "1º TURNO"], [b2, cor2, "2º TURNO"]].forEach(function (z, j) {
        var yy = y + 62 + j * 56;
        o += t(55, yy + 14, z[2], { s: 12, b: true, c: C.apagado, ls: 1 });
        o += r(55, yy + 22, 300, 22, "rgba(255,255,255,0.08)", 5) + (z[0] > 0 ? r(55, yy + 22, Math.max(6, 300 * z[0] / max), 22, z[1], 5) : "");
        o += t(485, yy + 40, z[0] == null ? "—" : pct(z[0]), { s: 24, b: true, a: "end" });
      });
    });
    return svg(W2, H2, o + t(35, 945, "Fonte: TSE · Presidente, Brasil", { s: 11, c: C.apagado2 }));
  }
  G["turnos-h"] = function () { return telaTurnos(false); };
  G["turnos-v"] = function () { return telaTurnos(true); };

  // ---- CAMARA: BANCADA FEMININA ---------------------------------------------
  // Genero: arquivo "Candidatos" do TSE (Dados Abertos), importado pelo
  // IMPORTAR-CANDIDATOS.bat (web\candidatos-genero.js). Eleitas de 2026 =
  // eleitos do boletim do TSE (estados.js) cujo sqcand e de mulher; sem o
  // boletim, a situacao do proprio arquivo de candidatos.
  var COR_MULHER = "#a678f0";
  function bancadaFem() {
    var gen = window.GCTSE_GENERO, cm = (E().camara || {});
    if (!gen || !gen.anos) return null;
    var a26 = gen.anos["2026"], a22 = gen.anos["2022"], r = { a22: a22, a26: a26, fonte: gen.fonte, quando: gen.gerado_em };
    if (!a26) return r;
    var fem = {}; comoLista(a26.mulheres).forEach(function (q) { fem[q] = 1; });
    var tot = 0, el = 0, pp = {}, ufs = 0;
    Object.keys(cm).forEach(function (u) {
      var l = comoLista(cm[u].lista); if (!l.length) return; ufs++;
      l.forEach(function (c) { tot++; if (fem[c.sqcand]) { el++; pp[c.partido] = (pp[c.partido] || 0) + 1; } });
    });
    if (tot > 0) { r.eleitas = el; r.eleitos = tot; r.partidos = pp; r.aoVivo = true; r.ufs = ufs; }
    else { r.eleitas = +a26.eleitas || 0; r.eleitos = +a26.eleitos || 513; r.partidos = a26.eleitas_por_partido || {}; r.aoVivo = false; }
    return r;
  }
  function meiaLua(cx, cy, raio, esp, frac, cor) {
    var L = Math.PI * raio, d = "M" + (cx - raio) + " " + cy + " A" + raio + " " + raio + " 0 0 1 " + (cx + raio) + " " + cy;
    return '<path d="' + d + '" fill="none" stroke="rgba(255,255,255,0.12)" stroke-width="' + esp + '"/>' +
      (frac > 0 ? '<path d="' + d + '" fill="none" stroke="' + cor + '" stroke-width="' + esp + '" stroke-dasharray="' + (L * Math.min(1, frac)).toFixed(1) + " " + L.toFixed(1) + '"/>' : "");
  }
  function pct1(v) { return Number(v).toFixed(1).replace(".", ",") + "%"; }
  function sinal(v, txt) { return (v > 0 ? "▲ +" : v < 0 ? "▼ −" : "") + txt; }
  function blocoAno(x, y, ano, n, total, destaque, k) {
    var o = t(x, y, ano, { s: Math.round(20 * k), b: true, c: destaque ? C.texto : C.apagado, a: "middle", ls: 2 });
    o += meiaLua(x, y + 150 * k, 96 * k, 26 * k, total ? n / total : 0, destaque ? COR_MULHER : "#7f6aa8");
    o += t(x, y + 128 * k, String(n), { s: Math.round(54 * k), b: true, a: "middle" });
    o += t(x, y + 152 * k, "deputadas", { s: Math.round(15 * k), c: C.apagado, a: "middle" });
    o += t(x, y + 196 * k, total ? pct1(100 * n / total) : "—", { s: Math.round(30 * k), b: true, c: destaque ? COR_MULHER : "#b9a8d8", a: "middle" });
    o += t(x, y + 218 * k, "das " + total + " cadeiras", { s: Math.round(13 * k), c: C.apagado, a: "middle" });
    return o;
  }
  function barrasPartidosFem(x, y, w, passo, pp, n, k) {
    var ls = Object.keys(pp || {}).sort(function (a, b) { return pp[b] - pp[a] || a.localeCompare(b); }).slice(0, n), o = "";
    if (!ls.length) return t(x, y + 20, "sem eleitas ainda", { s: 16, c: C.apagado });
    var max = pp[ls[0]];
    ls.forEach(function (sg, i) {
      var yy = y + i * passo;
      o += t(x, yy + 20 * k, sg, { s: Math.round(18 * k), b: true, max: 140 * k });
      o += r(x + 150 * k, yy + 2 * k, w - 150 * k - 50 * k, 24 * k, "rgba(255,255,255,0.10)", 4) +
        r(x + 150 * k, yy + 2 * k, Math.max(6, (w - 200 * k) * pp[sg] / max), 24 * k, corPartidoCamara(sg, i), 4);
      o += t(x + w, yy + 21 * k, String(pp[sg]), { s: Math.round(20 * k), b: true, a: "end" });
    });
    return o;
  }
  function telaFem(v) {
    var bf = bancadaFem(), W = v ? 540 : 1280, H = v ? 960 : 720, o;
    var semDado = !bf || !bf.a26;
    var tit = "CÂMARA: BANCADA FEMININA";
    if (semDado) {
      o = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 26, b: true, ls: 1, max: 450 }) : t(73, 57, tit, { s: 36, b: true, ls: 1 });
      return svg(W, H, o + t(W / 2, H / 2 - 10, "falta o arquivo de candidatos do TSE", { s: v ? 18 : 24, c: C.apagado, a: "middle" }) +
        t(W / 2, H / 2 + 22, "rode o IMPORTAR-CANDIDATOS.bat (consulta_cand_2026.zip, Dados Abertos)", { s: v ? 12 : 16, c: C.apagado2, a: "middle", max: W - 60 }));
    }
    var a22 = bf.a22, n26 = bf.eleitas, tot = bf.eleitos || 513, n22 = a22 ? +a22.eleitas : null;
    var sub = n26 + " deputadas eleitas  ·  " + pct1(100 * n26 / tot) + " das " + tot + " cadeiras" + (n22 != null ? "  ·  em 2022 foram " + n22 : "");
    var cand26 = +bf.a26.aptas_mulheres || +bf.a26.candidaturas_mulheres, tot26 = +bf.a26.aptas || +bf.a26.candidaturas;
    var cand22 = a22 ? (+a22.aptas_mulheres || +a22.candidaturas_mulheres) : null;
    var rod = "Fonte: TSE — gênero: Dados Abertos (Candidatos); eleitas: " + (bf.aoVivo ? "boletim de resultados" + (bf.ufs < 27 ? " (" + bf.ufs + " de 27 estados)" : "") : "arquivo de candidatos") + "; candidaturas aptas a Deputado Federal";
    if (!v) {
      o = t(73, 57, tit, { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, sub, { s: 18, c: C.apagado, max: 640 });
      o += r(73, 110, 560, 410, "rgba(8,14,32,0.80)", 10) + t(93, 142, "BANCADA FEMININA NA CÂMARA", { s: 16, b: true, c: "#c9d6e6", ls: 1 });
      if (n22 != null) o += blocoAno(213, 186, "2022", n22, 513, false, 1);
      o += blocoAno(n22 != null ? 493 : 353, 186, "2026", n26, tot, true, 1);
      if (n22 != null) {
        var dC = n26 - n22, dP = n22 ? 100 * (n26 - n22) / n22 : 0;
        o += r(93, 440, 250, 60, "rgba(255,255,255,0.06)", 8) + r(363, 440, 250, 60, "rgba(255,255,255,0.06)", 8);
        o += t(218, 470, sinal(dC, Math.abs(dC) + (Math.abs(dC) === 1 ? " cadeira" : " cadeiras")), { s: 20, b: true, c: dC >= 0 ? "#69db7c" : "#ff8787", a: "middle" }) + t(218, 490, "em relação a 2022", { s: 12, c: C.apagado, a: "middle" });
        o += t(488, 470, sinal(dP, pct1(Math.abs(dP))), { s: 20, b: true, c: dP >= 0 ? "#69db7c" : "#ff8787", a: "middle" }) + t(488, 490, "de deputadas a mais que em 2022".replace("a mais", dP >= 0 ? "a mais" : "a menos"), { s: 12, c: C.apagado, a: "middle" });
      }
      o += r(653, 110, 554, 410, "rgba(8,14,32,0.80)", 10) + t(673, 142, "PARTIDOS COM MAIS MULHERES ELEITAS", { s: 16, b: true, c: "#c9d6e6", ls: 1 });
      o += barrasPartidosFem(673, 170, 514, 56, bf.partidos, 6, 1);
      o += r(73, 536, 1134, 136, "rgba(8,14,32,0.80)", 10);
      o += t(100, 600, inteiro(cand26), { s: 48, b: true }) + t(100, 630, "mulheres candidatas a Deputado Federal em 2026", { s: 15, c: C.apagado }) + t(100, 650, "(candidaturas aptas)", { s: 12, c: C.apagado2 });
      if (cand22) {
        var dCand = 100 * (cand26 - cand22) / cand22;
        o += t(560, 600, sinal(dCand, pct1(Math.abs(dCand))), { s: 36, b: true, c: dCand >= 0 ? "#69db7c" : "#ff8787" }) + t(560, 630, "em relação a 2022 (" + inteiro(cand22) + " candidatas)", { s: 15, c: C.apagado });
      }
      var fc = tot26 ? cand26 / tot26 : 0;
      o += rosca(1125, 604, 46, 14, [{ v: fc, c: COR_MULHER }, { v: 1 - fc, c: "rgba(255,255,255,0.12)" }]) + t(1125, 611, pct1(100 * fc).replace(",0%", "%"), { s: 18, b: true, a: "middle" });
      o += t(1060, 600, "das candidaturas", { s: 14, c: C.apagado, a: "end" }) + t(1060, 620, "a deputado federal", { s: 14, c: C.apagado, a: "end" }) + t(1060, 640, "eram de mulheres", { s: 14, c: C.apagado, a: "end" });
      return svg(W, H, o + t(73, 700, rod, { s: 12, c: C.apagado2, max: 1134 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "BANCADA FEMININA", { s: 30, b: true, ls: 1, max: 450 }) + t(53, 106, "Câmara dos Deputados · " + n26 + " eleitas", { s: 15, c: C.apagado, max: 450 });
    o += r(35, 130, 470, 300, "rgba(8,14,32,0.80)", 10);
    if (n22 != null) o += blocoAno(150, 160, "2022", n22, 513, false, 0.95);
    o += blocoAno(n22 != null ? 390 : 270, 160, "2026", n26, tot, true, 0.95);
    if (n22 != null) {
      var dC2 = n26 - n22, dP2 = n22 ? 100 * (n26 - n22) / n22 : 0;
      o += t(150, 412, sinal(dC2, Math.abs(dC2) + " cadeiras"), { s: 18, b: true, c: dC2 >= 0 ? "#69db7c" : "#ff8787", a: "middle" });
      o += t(390, 412, sinal(dP2, pct1(Math.abs(dP2))) + " vs 2022", { s: 18, b: true, c: dP2 >= 0 ? "#69db7c" : "#ff8787", a: "middle" });
    }
    o += r(35, 446, 470, 330, "rgba(8,14,32,0.80)", 10) + t(55, 476, "PARTIDOS COM MAIS ELEITAS", { s: 15, b: true, c: "#c9d6e6", ls: 1 });
    o += barrasPartidosFem(55, 494, 430, 46, bf.partidos, 6, 0.9);
    o += r(35, 792, 470, 132, "rgba(8,14,32,0.80)", 10);
    o += t(55, 842, inteiro(cand26), { s: 38, b: true }) + t(55, 866, "candidatas a Dep. Federal em 2026", { s: 13, c: C.apagado });
    var fc2 = tot26 ? cand26 / tot26 : 0;
    if (cand22) { var dc2 = 100 * (cand26 - cand22) / cand22; o += t(55, 900, sinal(dc2, pct1(Math.abs(dc2))) + " vs 2022 (" + inteiro(cand22) + ")", { s: 15, b: true, c: dc2 >= 0 ? "#69db7c" : "#ff8787" }); }
    o += rosca(440, 852, 40, 12, [{ v: fc2, c: COR_MULHER }, { v: 1 - fc2, c: "rgba(255,255,255,0.12)" }]) + t(440, 859, pct1(100 * fc2).replace(",0%", "%"), { s: 15, b: true, a: "middle" });
    o += t(440, 910, "das candidaturas", { s: 11, c: C.apagado, a: "middle" });
    return svg(W, H, o + t(35, 948, "Fonte: TSE — Dados Abertos (Candidatos) e boletim de resultados", { s: 11, c: C.apagado2, max: 470 }));
  }
  G["mulheres-h"] = function () { return telaFem(false); };
  G["mulheres-v"] = function () { return telaFem(true); };

  // ---- SENADORES ELEITOS: 2 por estado, foto + nome + partido, mapa em blocos
  // Boletim de Senador do TSE (estados.js, cargo 5; no 2o turno, o do 1o).
  // Eleito = situacao do TSE (ou a conta matematica do coletor).
  function senEstado(k) {
    var u = (E().ufs || {})[k], sg = u && u.sen && u.sen.tem ? u.sen : null;
    if (!sg) return { tem: false, el: [] };
    var cs = comoLista(sg.candidatos), el = cs.filter(function (c) { return c.eleito; })
      .sort(function (a, b) { return (+b.votos || 0) - (+a.votos || 0); });
    return { tem: true, el: el, vagas: Math.max(+sg.vagas || 0, 2), urnas: sg.urnas_pct };
  }
  function urlFotoSen(k, c) {
    var tse = E().tse;
    if (window.GCTSE_FOTOS_DO_TSE !== true || window.__gctseSemFotos || !tse || !tse.base || !c || !c.sqcand) return "";
    var url = tse.base + "/" + tse.ciclo + "/" + (tse.eleicao_1turno || tse.eleicao) + "/fotos/" + k + "/" + c.sqcand + ".jpeg";
    return FOTO_DEP.falhou[url] ? "" : url;
  }
  // Mapa em blocos (cada estado um quadrado na posicao aproximada).
  var BLOCOS_UF = { rr: [1, 0], ap: [2, 0], am: [1, 1], pa: [2, 1], ma: [3, 1], ce: [4, 1], rn: [5, 1],
    ac: [0, 2], ro: [1, 2], mt: [2, 2], to: [3, 2], pi: [4, 2], pb: [5, 2], ms: [2, 3], go: [3, 3], ba: [4, 3], pe: [5, 3],
    sp: [2, 4], df: [3, 4], mg: [4, 4], al: [5, 4], pr: [2, 5], rj: [3, 5], es: [4, 5], se: [5, 5], sc: [2, 6], rs: [2, 7] };
  var COR_VAZIO_SEN = "#2a3a55";
  function coresSen(k) {
    var st = senEstado(k), c = st.el.map(function (x, i) { return corPartidoCamara(x.partido, i); });
    if (!c.length) return [COR_VAZIO_SEN, COR_VAZIO_SEN];
    if (c.length === 1 && (st.vagas || 2) > 1) return [c[0], COR_VAZIO_SEN];   // vaga ainda em aberto
    return [c[0], c[1] || c[0]];
  }
  function blocoUF(k, x, y, l) {
    var cc = coresSen(k), o;
    if (cc[0] === cc[1]) o = r(x, y, l, l, cc[0], 3);
    else o = '<polygon points="' + x + "," + y + " " + (x + l) + "," + y + " " + x + "," + (y + l) + '" fill="' + cc[0] + '"/>' +
      '<polygon points="' + (x + l) + "," + y + " " + (x + l) + "," + (y + l) + " " + x + "," + (y + l) + '" fill="' + cc[1] + '"/>';
    return o + r(x + l / 2 - l * 0.22, y + l / 2 - l * 0.15, l * 0.44, l * 0.3, "#0b1220", 2) +
      t(x + l / 2, y + l / 2 + l * 0.09, k.toUpperCase(), { s: Math.round(l * 0.22), b: true, a: "middle" });
  }
  function mapaBlocos(x, y, l, gap) {
    var o = "";
    Object.keys(BLOCOS_UF).forEach(function (k) { var p = BLOCOS_UF[k]; o += blocoUF(k, x + p[0] * (l + gap), y + p[1] * (l + gap), l); });
    return o;
  }
  // Cartao do estado: sigla em faixa (cor dos 2 partidos), 2 fotos com nome e partido.
  function cartaoSen(k, x, y, w, h, fn) {
    var st = senEstado(k), cc = coresSen(k), o = "", n = Math.max(2, Math.min(3, st.vagas || 2));
    o += r(x, y, w, h, "rgba(8,14,32,0.82)", 5);
    var hf = Math.round(fn * 2);
    o += r(x, y, w / 2, hf, cc[0], 0) + r(x + w / 2, y, w / 2, hf, cc[1], 0);
    o += r(x + w / 2 - fn * 1.6, y + 2, fn * 3.2, hf - 4, "#0b1220", 2) + t(x + w / 2, y + hf * 0.72, k.toUpperCase(), { s: Math.round(fn * 1.2), b: true, a: "middle" });
    var pad = 4, gw = (w - pad * (n + 1)) / n, top = y + hf + pad, hb = Math.round(fn * 2.3), hp = Math.round(fn * 1.5);
    var fh = h - hf - pad * 2 - hb - hp;
    for (var i = 0; i < n; i++) {
      var c = st.el[i], gx = x + pad + i * (gw + pad), cor = c ? corPartidoCamara(c.partido, i) : COR_VAZIO_SEN;
      o += r(gx - 1, top - 1, gw + 2, fh + hb + hp + 2, cor, 3);
      o += c ? fotoOuSilhueta(urlFotoSen(k, c), gx, top, gw, fh) : silhueta(gx, top, gw, fh);
      o += r(gx, top + fh, gw, hb, "#0b1220", 0);
      if (c) {
        var ln = linhasNome(c.nome, Math.max(8, Math.round(gw / (fn * 0.62))));
        if (ln.length === 1) o += t(gx + gw / 2, top + fh + hb * 0.62, ln[0], { s: fn, b: true, a: "middle", max: gw - 3 });
        else ln.forEach(function (l, j) { o += t(gx + gw / 2, top + fh + hb * (j ? 0.86 : 0.43), l, { s: Math.round(fn * 0.9), b: true, a: "middle", max: gw - 3 }); });
        o += r(gx, top + fh + hb, gw, hp, cor, 0) + t(gx + gw / 2, top + fh + hb + hp * 0.76, c.partido, { s: Math.round(fn * 0.95), b: true, c: "#0b1220", a: "middle", max: gw - 4 });
      } else {
        o += t(gx + gw / 2, top + fh + hb * 0.62, st.tem && st.urnas > 0 ? "APURANDO" : "AGUARDANDO", { s: Math.round(fn * 0.85), b: true, c: C.apagado, a: "middle", max: gw - 3 });
        o += r(gx, top + fh + hb, gw, hp, COR_VAZIO_SEN, 0);
      }
    }
    return o;
  }
  function contaSen() {
    var pp = {}, n = 0, vagas = 0;
    Object.keys(DEP_UF).forEach(function (k) {
      var st = senEstado(k); vagas += st.tem ? (st.vagas || 2) : 2;
      st.el.forEach(function (c) { pp[c.partido] = (pp[c.partido] || 0) + 1; n++; });
    });
    return { pp: pp, n: n, vagas: vagas };
  }
  function legendaSen(x, y, cols, cw, passo, fs) {
    var cs = contaSen(), ls = Object.keys(cs.pp).sort(function (a, b) { return cs.pp[b] - cs.pp[a] || a.localeCompare(b); }), o = "";
    ls.forEach(function (sg, i) {
      var xx = x + (i % cols) * cw, yy = y + Math.floor(i / cols) * passo;
      o += r(xx, yy - fs + 1, fs, fs, corPartidoCamara(sg, i), 3) + t(xx + fs + 8, yy, sg + " " + cs.pp[sg], { s: fs, b: true, max: cw - fs - 12 });
    });
    var i2 = ls.length, xx2 = x + (i2 % cols) * cw, yy2 = y + Math.floor(i2 / cols) * passo;
    o += '<polygon points="' + xx2 + "," + (yy2 - fs + 1) + " " + (xx2 + fs) + "," + (yy2 - fs + 1) + " " + xx2 + "," + (yy2 + 1) + '" fill="#2f6bff"/>' +
      '<polygon points="' + (xx2 + fs) + "," + (yy2 - fs + 1) + " " + (xx2 + fs) + "," + (yy2 + 1) + " " + xx2 + "," + (yy2 + 1) + '" fill="#e5132d"/>' +
      t(xx2 + fs + 8, yy2, "2 partidos na UF", { s: Math.round(fs * 0.9), c: "#c9d6e6", max: cw - fs - 12 });
    return o;
  }
  var GRADE_SEN = [["ac", "al", "am", "ap", "ba", "ce", "df"], ["es", "go", "ma", "mg", "ms", "mt", "pa"], ["pb", "pe", "pi", "pr", "rj", "rn", "ro"], ["rr", "rs", "sc", "se", "sp", "to"]];
  function seloSen() {
    var cs = contaSen();
    if (cs.n >= cs.vagas && cs.n > 0) return { texto: cs.vagas + " VAGAS", cor: C.destaque };
    return { texto: cs.n + " DE " + cs.vagas + " DEFINIDOS", cor: cs.n ? C.vermelho : C.trilho };
  }
  function telaSen(v) {
    var cs = contaSen(), o, sub = cs.n + (cs.n === 1 ? " eleito" : " eleitos") + " · 2 por estado · cor = partido do eleito";
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, "SENADORES", { s: 36, b: true, ls: 1 }) + t(73, 85, sub, { s: 18, c: C.apagado, max: 640 }) + seloH(W, seloSen());
      var cw = 116, ch = 136, gx = 8, gy = 6;
      GRADE_SEN.forEach(function (lin, li) {
        var x0 = 60 + (li === 3 ? (cw + gx) / 2 : 0);
        lin.forEach(function (k, ci) { o += cartaoSen(k, x0 + ci * (cw + gx), 110 + li * (ch + gy), cw, ch, 7.5); });
      });
      o += mapaBlocos(944, 110, 42, 4);
      o += legendaSen(924, 520, 3, 100, 22, 12);
      return svg(W, H, o + t(60, 700, "Fonte: TSE — senadores eleitos" + (E().turno === 2 ? " no 1º turno" : "") + " · mandato 2027–2035", { s: 13, c: C.apagado2 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "SENADORES", { s: 32, b: true, ls: 1 }) + t(53, 106, sub, { s: 13, c: C.apagado, max: 450 }) + seloV(W2, seloSen());
    var cw2 = 90, ch2 = 110, g2 = 5, todos = [].concat.apply([], GRADE_SEN), nUlt = todos.length % 5 || 5;
    todos.forEach(function (k, i) {
      var li = Math.floor(i / 5), ci = i % 5, ult = li === Math.floor((todos.length - 1) / 5);
      var x0 = 38 + (ult ? (5 - nUlt) * (cw2 + g2) / 2 : 0);
      o += cartaoSen(k, x0 + ci * (cw2 + g2), 162 + li * (ch2 + g2), cw2, ch2, 6.5);
    });
    o += legendaSen(40, 868, 4, 116, 17, 10);
    return svg(W2, H2, o + t(35, 952, "Fonte: TSE — senadores eleitos · mandato 2027–2035", { s: 10, c: C.apagado2 }));
  }
  G["senadores-h"] = function () { return telaSen(false); };
  G["senadores-v"] = function () { return telaSen(true); };

  // Senadores em DUAS telas (cartoes maiores): parte 1 = AC..PA, parte 2 = PB..TO.
  var SEN_PARTES = [["ac", "al", "am", "ap", "ba", "ce", "df", "es", "go", "ma", "mg", "ms", "mt", "pa"],
                    ["pb", "pe", "pi", "pr", "rj", "rn", "ro", "rr", "rs", "sc", "se", "sp", "to"]];
  function gradeSen(ufs, x0, y0, cols, cw, ch, gx, gy, fn, larguraTotal) {
    var o = "", linhas = Math.ceil(ufs.length / cols);
    ufs.forEach(function (k, i) {
      var li = Math.floor(i / cols), ci = i % cols, nLin = li === linhas - 1 ? ufs.length - li * cols : cols;
      var xi = x0 + (larguraTotal - (nLin * cw + (nLin - 1) * gx)) / 2;
      o += cartaoSen(k, xi + ci * (cw + gx), y0 + li * (ch + gy), cw, ch, fn);
    });
    return o;
  }
  function telaSenParte(v, parte) {
    var ufs = SEN_PARTES[parte], cs = contaSen(), o;
    var de = DEP_UF[ufs[0]], ate = DEP_UF[ufs[ufs.length - 1]];
    var sub = cs.n + (cs.n === 1 ? " eleito" : " eleitos") + " no Brasil · parte " + (parte + 1) + " de 2: " + ufs[0].toUpperCase() + " a " + ufs[ufs.length - 1].toUpperCase();
    var tit = "SENADORES  " + (parte + 1) + "/2";
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, tit, { s: 36, b: true, ls: 1 }) + t(73, 85, sub, { s: 18, c: C.apagado, max: 640 }) + seloH(W, seloSen());
      o += gradeSen(ufs, 73, 104, 5, 214, 168, 16, 8, 10, 1134);
      o += r(73, 632, 1134, 1, C.linha) + legendaSen(73, 656, 8, 142, 22, 12);
      return svg(W, H, o + t(73, 708, "Fonte: TSE — senadores eleitos" + (E().turno === 2 ? " no 1º turno" : "") + " · mandato 2027–2035 · contagem por partido = Brasil", { s: 11, c: C.apagado2 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 32, b: true, ls: 1 }) + t(53, 106, sub, { s: 13, c: C.apagado, max: 450 }) + seloV(W2, seloSen());
    o += gradeSen(ufs, 35, 162, 3, 152, 132, 7, 6, 8, 470);
    o += legendaSen(40, 880, 4, 116, 17, 10);
    return svg(W2, H2, o + t(35, 952, "Fonte: TSE — senadores eleitos · contagem por partido = Brasil", { s: 10, c: C.apagado2 }));
  }
  G["senadores1-h"] = function () { return telaSenParte(false, 0); };
  G["senadores2-h"] = function () { return telaSenParte(false, 1); };
  G["senadores1-v"] = function () { return telaSenParte(true, 0); };
  G["senadores2-v"] = function () { return telaSenParte(true, 1); };

  window.GCTSE_GRAFICOS = {
    lista: [
      { id: "presidente-h", nome: "Presidente — Brasil", f: "h" },
      { id: "votos-h", nome: "Como o Brasil votou", f: "h" },
      { id: "urnas-h", nome: "Apuração nacional", f: "h" },
      { id: "estados-h", nome: "Como cada estado votou", f: "h" },
      { id: "lideranca-h", nome: "Liderança por estado", f: "h" },
      { id: "abstencao-h", nome: "Abstenção, brancos e nulos", f: "h" },
      { id: "abstencao-mapa-h", nome: "Mapa da abstenção", f: "h" },
      { id: "pres2t-h", nome: "Presidente — 2º turno", f: "h" },
      { id: "senado-h", nome: "Senado: atual × 2027", f: "h" },
      { id: "comparativo-h", nome: "2018 × 2022 × 2026", f: "h" },
      { id: "camara-h", nome: "Câmara: bancadas 2027", f: "h" },
      { id: "evolucao-h", nome: "Evolução minuto a minuto (1º × 2º)", f: "h" },
      { id: "deputados-h", nome: "Deputados federais eleitos", f: "h" },
      { id: "mulheres-h", nome: "Câmara: bancada feminina", f: "h" },
      { id: "apuracao-h", nome: "Apuração: regiões e estados", f: "h" },
      { id: "presmapa-h", nome: "Presidente + mapa", f: "h" },
      { id: "presmapa1t-h", nome: "Presidente + mapa — 1º turno", f: "h" },
      { id: "regioes-h", nome: "Presidente | Regiões", f: "h" },
      { id: "presloc-h", nome: "Presidente | Estado ou região", f: "h" },
      { id: "governadores-h", nome: "Governadores (1º verde · 2º azul)", f: "h" },
      { id: "govpartido-h", nome: "Governadores por partido", f: "h" },
      { id: "senadores-h", nome: "Senadores eleitos (foto + partido)", f: "h" },
      { id: "senadores1-h", nome: "Senadores 1/2 (AC a PA)", f: "h" },
      { id: "senadores2-h", nome: "Senadores 2/2 (PB a TO)", f: "h" },
      { id: "turnos-h", nome: "1º × 2º turno: abstenção, brancos e nulos", f: "h" },
      { id: "urnas-v", nome: "Urnas apuradas", f: "v" },
      { id: "votos-v", nome: "Brancos e nulos", f: "v" },
      { id: "presidente-v", nome: "Presidente", f: "v" },
      { id: "comparecimento-v", nome: "Comparecimento", f: "v" },
      { id: "lideranca-v", nome: "Liderança por estado", f: "v" },
      { id: "abstencao-v", nome: "Abstenção, brancos e nulos", f: "v" },
      { id: "abstencao-mapa-v", nome: "Mapa da abstenção", f: "v" },
      { id: "pres2t-v", nome: "Presidente — 2º turno", f: "v" },
      { id: "senado-v", nome: "Senado: 2027", f: "v" },
      { id: "comparativo-v", nome: "2018 × 2022 × 2026", f: "v" },
      { id: "camara-v", nome: "Câmara: bancadas 2027", f: "v" },
      { id: "evolucao-v", nome: "Evolução minuto a minuto (1º × 2º)", f: "v" },
      { id: "deputados-v", nome: "Deputados federais eleitos", f: "v" },
      { id: "mulheres-v", nome: "Câmara: bancada feminina", f: "v" },
      { id: "apuracao-v", nome: "Apuração: regiões", f: "v" },
      { id: "presmapa-v", nome: "Presidente + mapa", f: "v" },
      { id: "presmapa1t-v", nome: "Presidente + mapa — 1º turno", f: "v" },
      { id: "regioes-v", nome: "Presidente | Regiões", f: "v" },
      { id: "presloc-v", nome: "Presidente | Estado ou região", f: "v" },
      { id: "governadores-v", nome: "Governadores (1º verde · 2º azul)", f: "v" },
      { id: "govpartido-v", nome: "Governadores por partido", f: "v" },
      { id: "senadores-v", nome: "Senadores eleitos (foto + partido)", f: "v" },
      { id: "senadores1-v", nome: "Senadores 1/2 (AC a PA)", f: "v" },
      { id: "senadores2-v", nome: "Senadores 2/2 (PB a TO)", f: "v" },
      { id: "turnos-v", nome: "1º × 2º turno: abstenção, brancos e nulos", f: "v" }
    ],
    desenhar: function (id) { return G[id] ? G[id]() : null; },
    // Telas que trocam sozinhas (deputados): muda quando a tela da vez muda.
    pagina: function (id) {
      if (String(id).indexOf("deputados") !== 0) return "";
      var man = depManual(), sel = selecaoDep();
      if (man && !REG_DEP[man]) return "m:" + man;           // estado fixo: so troca pelo comando
      return (man || "a") + ":" + sel.pags.length + ":" + sel.ip;
    },
    // Telas dos deputados para a navegacao manual (gerenciador).
    depPaginas: function () { return paginasDeputados(true).map(function (p) { return { uf: p.uf, k: p.k, n: p.n, total: p.total }; }); },
    reiniciarPaginas: function () { T0_DEP = Date.now(); },
    ajustarSelos: ajustarSelos,
    dados: D,
    cor: cor,
    candidatos: function () { var d = D(); return d.br && d.br.tem ? candidatos(d.br) : []; }
  };
})();
