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
    var slot = (D().cor_slot || {})[c.numero];
    if (slot == null || slot >= PALETA.length) return C.outros;
    return PALETA[slot];
  }

  function selo() {
    var d = D(), b = br();
    if (d.modo === "SIMULADO") return { texto: "SIMULADO — NÃO OFICIAL", cor: C.vermelho };
    if (b && b.andamento === "f") return { texto: "TOTALIZAÇÃO FINAL", cor: C.verde };
    // Antes da 1a urna (arquivo do TSE ja publicado com tudo zerado, ou
    // nenhum arquivo ainda): selo neutro, nada de vermelho.
    var pct = b && b.secoes ? b.secoes.pct : null;
    if (!b || !(pct > 0)) return { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho };
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
  function seloH(W) {
    var s = selo();
    return '<g data-selo="dir" data-x="' + (W - 73) + '">' + r(W - 320, 33, 247, 32, s.cor, 3) +
      t(W - 81, 55, s.texto, { s: 18, b: true, a: "end" }) + "</g>";
  }
  function seloV(W) {
    var s = selo();
    return r(35, 127, W - 70, 26, s.cor, 2) + t(W / 2, 146, s.texto, { s: 16, b: true, a: "middle" });
  }
  function cabecalhoH(W, titulo, sub) {
    return t(73, 57, titulo, { s: 36, b: true, ls: 1, max: W - 73 - 360 }) + t(73, 85, sub, { s: 19, c: C.apagado }) + seloH(W);
  }
  function cabecalhoV(W, titulo, sub) {
    return r(35, 48, 6, 38, C.destaque) + t(53, 80, titulo, { s: 32, b: true, ls: 1, max: W - 53 - 35 }) +
      t(53, 106, sub, { s: 16, c: C.apagado, max: W - 53 - 35 }) + seloV(W);
  }
  function svg(W, H, corpo) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + W + " " + H + '" width="' + W + '" height="' + H +
      '" font-family="' + FONTE + '">' + r(0, 0, W, H, C.fundo) + corpo + "</svg>";
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

  window.GCTSE_GRAFICOS = {
    lista: [
      { id: "presidente-h", nome: "Presidente — Brasil", f: "h" },
      { id: "votos-h", nome: "Como o Brasil votou", f: "h" },
      { id: "urnas-h", nome: "Apuração nacional", f: "h" },
      { id: "estados-h", nome: "Como cada estado votou", f: "h" },
      { id: "lideranca-h", nome: "Liderança por estado", f: "h" },
      { id: "abstencao-h", nome: "Abstenção, brancos e nulos", f: "h" },
      { id: "abstencao-mapa-h", nome: "Mapa da abstenção", f: "h" },
      { id: "urnas-v", nome: "Urnas apuradas", f: "v" },
      { id: "votos-v", nome: "Brancos e nulos", f: "v" },
      { id: "presidente-v", nome: "Presidente", f: "v" },
      { id: "comparecimento-v", nome: "Comparecimento", f: "v" },
      { id: "lideranca-v", nome: "Liderança por estado", f: "v" },
      { id: "abstencao-v", nome: "Abstenção, brancos e nulos", f: "v" },
      { id: "abstencao-mapa-v", nome: "Mapa da abstenção", f: "v" }
    ],
    desenhar: function (id) { return G[id] ? G[id]() : null; },
    ajustarSelos: ajustarSelos,
    dados: D,
    cor: cor,
    candidatos: function () { var d = D(); return d.br && d.br.tem ? candidatos(d.br) : []; }
  };
})();
