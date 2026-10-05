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
  function paginasDeputados() {
    var cfg = window.GCTSE_DEPUTADOS || {}, porTela = Math.max(1, Math.min(5, +cfg.por_tela || 5));
    var pedidos = (cfg.estados || []).map(function (u) { return String(u).toLowerCase().trim(); });
    var cm = (window.GCTSE_ESTADOS || {}).camara || {}, pags = [];
    DEP_REGIOES.forEach(function (rg) {
      rg[1].filter(function (u) { return pedidos.indexOf(u) >= 0; })
        .sort(function (a, b) { return DEP_UF[a].localeCompare(DEP_UF[b], "pt-BR"); })
        .forEach(function (u) {
          var x = cm[u], lista = x ? comoLista(x.lista).slice() : [];
          if (!lista.length) return;   // estado ainda sem eleito do TSE: fica fora
          lista.sort(function (a, b) { return ((+b.votos || 0) - (+a.votos || 0)) || String(a.nome).localeCompare(String(b.nome), "pt-BR"); });
          var n = Math.ceil(lista.length / porTela);
          for (var k = 0; k < n; k++) {
            pags.push({ uf: u, regiao: rg[0], x: x, cs: lista.slice(k * porTela, (k + 1) * porTela), ini: k * porTela, k: k, n: n,
              total: lista.length, vagas: +x.vagas || 0 });
          }
        });
    });
    return pags;
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
    return "DEPUTADOS FEDERAIS ELEITOS  ·  " + (pg.ini + 1) + "º" + (pg.cs.length > 1 ? " a " + (pg.ini + pg.cs.length) + "º" : "") +
      " mais votados  ·  " + pg.total + (pg.vagas && pg.vagas !== pg.total ? " de " + pg.vagas + " vagas" : " eleitos");
  }
  function semDeputados(W, H, v) {
    var o = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, "DEPUTADOS FEDERAIS", { s: 32, b: true, ls: 1 }) :
      t(73, 57, "DEPUTADOS FEDERAIS ELEITOS", { s: 36, b: true, ls: 1 });
    return svg(W, H, o + t(W / 2, H / 2, "aguardando os eleitos do TSE (ESTADOS.bat)", { s: v ? 18 : 24, c: C.apagado, a: "middle" }));
  }
  G["deputados-h"] = function () {
    var W = 1280, H = 720, pags = paginasDeputados();
    if (!pags.length) return semDeputados(W, H, false);
    var ip = indiceDeputados(pags), pg = pags[ip];
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
    o += t(1207, 700, DEP_UF[pg.uf] + " " + (pg.k + 1) + "/" + pg.n + "   ·   tela " + (ip + 1) + " de " + pags.length, { s: 13, c: C.apagado2, a: "end" });
    return svg(W, H, o);
  };
  G["deputados-v"] = function () {
    var W = 540, H = 960, pags = paginasDeputados();
    if (!pags.length) return semDeputados(W, H, true);
    var ip = indiceDeputados(pags), pg = pags[ip];
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
    o += t(35, 945, "Fonte: TSE · " + DEP_UF[pg.uf] + " " + (pg.k + 1) + "/" + pg.n + " · tela " + (ip + 1) + " de " + pags.length, { s: 11, c: C.apagado2, max: 470 });
    return svg(W, H, o);
  };

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
      { id: "deputados-v", nome: "Deputados federais eleitos", f: "v" }
    ],
    desenhar: function (id) { return G[id] ? G[id]() : null; },
    // Telas que trocam sozinhas (deputados): muda quando a tela da vez muda.
    pagina: function (id) {
      if (String(id).indexOf("deputados") !== 0) return "";
      var pags = paginasDeputados();
      return pags.length + ":" + indiceDeputados(pags);
    },
    reiniciarPaginas: function () { T0_DEP = Date.now(); },
    ajustarSelos: ajustarSelos,
    dados: D,
    cor: cor,
    candidatos: function () { var d = D(); return d.br && d.br.tem ? candidatos(d.br) : []; }
  };
})();
