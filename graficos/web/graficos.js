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
  // Fotos guardadas pelo GUARDAR-DADOS-TSE.bat (web\fotos-tse): usadas no
  // lugar da do TSE quando existem (o TSE pode ficar lento ou fora no dia).
  function viaLocal(url) {
    var L = window.GCTSE_FOTOS_LOCAIS, m = L ? /\/fotos\/([a-z]{2})\/(\d+)\.jpe?g$/i.exec(url) : null;
    return m && L[m[1].toLowerCase() + "/" + m[2]] ? L[m[1].toLowerCase() + "/" + m[2]] : url;
  }
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
    if (ensaioAtivo()) return { texto: "ENSAIO — NÃO VAI AO AR", cor: C.vermelho };
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
  var SELO_ENSAIO = { texto: "ENSAIO — NÃO VAI AO AR", cor: "#d03b3b" };
  function seloH(W, sl) {
    var s = ensaioAtivo() ? SELO_ENSAIO : sl || selo();
    // a esquerda da logo (canto superior direito)
    return '<g data-selo="dir" data-x="' + (W - 73 - 200) + '">' + r(W - 520, 29, 247, 32, s.cor, 3) +
      t(W - 281, 51, s.texto, { s: 18, b: true, a: "end" }) + "</g>";
  }
  function seloV(W, sl) {
    var s = ensaioAtivo() ? SELO_ENSAIO : sl || selo();
    return r(35, 127, W - 70, 26, s.cor, 2) + t(W / 2, 146, s.texto, { s: 16, b: true, a: "middle" });
  }
  function cabecalhoH(W, titulo, sub) {
    return t(73, 57, titulo, { s: 36, b: true, ls: 1, max: W - 73 - 540 }) + t(73, 85, sub, { s: 19, c: C.apagado, max: W - 146 }) + seloH(W);
  }
  function cabecalhoV(W, titulo, sub) {
    return r(35, 48, 6, 38, C.destaque) + t(53, 80, titulo, { s: 32, b: true, ls: 1, max: W - 53 - 35 }) +
      t(53, 106, sub, { s: 16, c: C.apagado, max: W - 53 - 35 }) + seloV(W);
  }
  // ENSAIO (ENSAIO.bat): toda tela sai riscada - nunca confundir com o ar.
  function ensaioAtivo() { return !!((window.GCTSE_DADOS || {}).ensaio || (window.GCTSE_ESTADOS || {}).ensaio); }
  function marcaEnsaio(W, H) {
    if (!ensaioAtivo()) return "";
    var cx = W / 2, cy = H / 2, s = Math.round(Math.min(W, H) / 7.5);
    return '<g pointer-events="none"><text x="' + cx + '" y="' + cy + '" text-anchor="middle" dominant-baseline="middle" font-size="' + s +
      '" font-weight="800" fill="#ff2a2a" fill-opacity="0.22" transform="rotate(' + (W > H ? -18 : -55) + " " + cx + " " + cy + ')">ENSAIO</text>' +
      '<rect x="0" y="' + (H - 30) + '" width="' + W + '" height="30" fill="#c00000"/>' +
      '<text x="' + cx + '" y="' + (H - 9) + '" text-anchor="middle" font-size="17" font-weight="800" fill="#ffffff">ENSAIO — DADOS FICTÍCIOS — NÃO VAI AO AR</text></g>';
  }
  function svg(W, H, corpo) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + W + " " + H + '" width="' + W + '" height="' + H +
      '" font-family="' + FONTE + '">' + r(0, 0, W, H, C.fundo) + arteFundo(W, H) + corpo + marcaEnsaio(W, H) + arteLogo(W, H, 35 + (W > H ? 38 : 0)) + "</svg>";
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
    if (FOTO.falhas >= 3 && FOTO.acertos === 0 && !window.GCTSE_FOTOS_LOCAIS) return "";
    var url = tse.base + "/" + tse.ciclo + "/" + tse.eleicao + "/fotos/br/" + c.sqcand + ".jpeg"; url = viaLocal(url);
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
    // 2o turno (so 2 candidatos): 2 linhas no meio, sem linhas vazias
    var nl = todos.length >= 2 && todos.length < 6 ? todos.length : 6, passo = nl >= 6 ? 84.4 : Math.min(150, 506 / nl), y0 = 152 + (506 - passo * nl) / 2;
    var o = cabecalhoH(W, "PRESIDENTE — BRASIL", "% dos votos válidos  ·  " + subtitulo());
    o += t(727, 124, "50% DOS VÁLIDOS", { s: 13, b: true, c: C.apagado, a: "middle", ls: 1 });
    for (var i = 0; i < nl; i++) {
      var c = cs[i], cy = y0 + i * passo, url = c && !c.outros ? urlFoto(c) : "", dx = 0;
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
    o += t(727, 666, nl === 2 ? "▏ 50% dos válidos" : "▏ 50% dos válidos = vence no 1º turno", { s: 13, c: C.apagado2, a: "middle" });
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
    var nl = todos.length >= 2 && todos.length < 5 ? todos.length : 5, passo = nl >= 5 ? 134 : 180, y0 = 212 + (nl >= 5 ? 0 : (670 - passo * nl) / 2);
    var o = cabecalhoV(W, "PRESIDENTE", "% dos votos válidos · " + subtitulo());
    for (var i = 0; i < nl; i++) {
      var c = cs[i], y = y0 + i * passo, url = c && !c.outros ? urlFoto(c) : "", dx = 0;
      o += r(35, y - 18, 5, 34, c ? cor(c) : C.outros, 1);
      if (url) { o += foto(url, 47, y - 24, 45, 60); dx = 55; }
      o += t(51 + dx, y + 6, c ? (c.outros ? c.nome : corta(c.nome, 16)) : "—", { s: 26, b: true, max: 300 - dx });
      o += t(51 + dx, y + 30, c ? corta(c.partido, 22) : "—", { s: 14, c: C.apagado, max: 300 - dx });
      o += t(505, y + 12, c ? pct(c.pct) : "0,00%", { s: 32, b: true, a: "end" });
      o += barra(35, y + 44, 470, 12, c ? c.pct / 100 : 0, c && !c.outros ? cor(c) : C.outros) + marca50(35, y + 44, 470, 12);
      o += t(35, y + 74, c ? inteiro(c.votos) : "0", { s: 15, c: C.apagado });
      if (c && (c.eleito || c.segundo_turno)) o += etiqueta(505 - (c.eleito ? 74 : 86), y + 78, c);
    }
    o += t(35, 862, nl === 2 ? "▏ 50% dos válidos" : "▏ 50% dos válidos = vence no 1º turno", { s: 13, c: C.apagado2 });
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
  // ---- ASSEMBLEIA LEGISLATIVA (deputados estaduais; DF: distritais) ---------
  // Por estado, escolhido no gerenciador (?a=pr ou rodizio "assembleia:pr").
  // Bancadas = candidatos que o TSE marcou como eleitos (ESTADOS.bat, cargo
  // 7; no DF, cargo 8). Mesmo desenho da Camara.
  function assembleia(u) {
    var x = ((window.GCTSE_ESTADOS || {}).assembleia || {})[u], soma = (x && x.partidos) || {};
    var lista = Object.keys(soma).map(function (sg) { return { sigla: sg, em2027: +soma[sg] || 0, atual: 0 }; })
      .sort(function (a, b) { return (b.em2027 - a.em2027) || a.sigla.localeCompare(b.sigla); });
    lista.forEach(function (p, i) { p.cor = corPartidoCamara(p.sigla, i); });
    return { ps: lista, vagas: x ? +x.vagas || 0 : 0, eleitos: x ? +x.eleitos || 0 : 0, ufs: x ? 1 : 0, temAtual: false, urnas: x ? x.urnas_pct : null, top: x ? comoLista(x.lista) : [] };
  }
  function nomeCasa(u) { return u === "df" ? "CÂMARA LEGISLATIVA" : "ASSEMBLEIA LEGISLATIVA"; }
  function subAsm(u, cm) {
    var cargo = u === "df" ? "deputados distritais" : "deputados estaduais";
    if (!cm.ufs) return "aguardando os " + cargo + " eleitos (ESTADOS.bat)";
    if (cm.eleitos >= cm.vagas) return cm.vagas + " cadeiras  ·  " + cargo + " eleitos em 2026";
    return cm.eleitos + " de " + cm.vagas + " cadeiras definidas pelo TSE";
  }
  function semAsm(W, H, v, u) {
    var mot = ((window.GCTSE_ESTADOS || {}).assembleia_motivos || {})[u];
    return t(W / 2, H / 2, "aguardando os eleitos de " + (DEP_UF[u] || u.toUpperCase()), { s: v ? 18 : 24, c: C.apagado, a: "middle", max: W - 60 }) +
      (mot ? t(W / 2, H / 2 + 30, mot, { s: v ? 12 : 15, c: C.apagado2, a: "middle", max: W - 60 }) : "");
  }
  function seloAsm(cm) {
    if (!cm.eleitos) return { texto: "AGUARDANDO", cor: C.trilho };
    return cm.eleitos >= cm.vagas ? { texto: "TOTALIZAÇÃO FINAL", cor: C.verde } : { texto: "PARCIAL", cor: C.vermelho };
  }
  function telaAsm(v) {
    var u = alvoAtual(); if (!DEP_UF[u]) u = "sp";
    var cm = assembleia(u), W = v ? 540 : 1280, H = v ? 960 : 720, o, rod = "Fonte: TSE — " + (u === "df" ? "deputados distritais (cargo 8)" : "deputados estaduais (cargo 7)") + " eleitos";
    var n = cm.ps.length > 15 ? 15 : Math.max(cm.ps.length, 1);
    if (!v) {
      o = t(73, 57, DEP_UF[u], { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, nomeCasa(u) + "  ·  " + subAsm(u, cm), { s: 18, c: C.apagado, max: 660 }) + seloH(W, seloAsm(cm));
      if (!cm.eleitos) return svg(W, H, o + semAsm(W, H, false, u));
      o += hemiciclo(385, 640, 320, 120, hemiCamara(cm), "em2027") + rotuloHemi(385, 640, "2027", cm.eleitos, 1.1);
      o += tabelaCamara(745, 1207, 150, Math.min(32, 480 / n), cm, 20, 15, [1010, 1110, 1207]);
      return svg(W, H, o + t(73, 700, rod, { s: 13, c: C.apagado2, max: 1134 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, DEP_UF[u], { s: 30, b: true, ls: 1, max: W - 88 }) + t(53, 106, nomeCasa(u) + " · " + subAsm(u, cm), { s: 13, c: C.apagado, max: W - 88 }) +
      seloV(W, seloAsm(cm));
    if (!cm.eleitos) return svg(W, H, o + semAsm(W, H, true, u));
    o += hemiciclo(270, 400, 232, 88, hemiCamara(cm), "em2027") + rotuloHemi(270, 400, "2027", cm.eleitos, 1);
    o += tabelaCamara(40, 505, 448, Math.min(29, 460 / n), cm, 19, 15, [330, 420, 505]);
    return svg(W, H, o + t(35, 950, rod, { s: 11, c: C.apagado2, max: 470 }));
  }
  G["assembleia-h"] = function () { return telaAsm(false); };
  G["assembleia-v"] = function () { return telaAsm(true); };

  // ---- ASSEMBLEIAS: PANORAMA BRASIL (soma dos 27 estados, por partido) ------
  function assembleiasBr() {
    var a = (window.GCTSE_ESTADOS || {}).assembleia || {}, soma = {}, vagas = 0, eleitos = 0, ufs = 0, comEl = 0;
    Object.keys(a).forEach(function (u) {
      var x = a[u]; if (!x) return;
      ufs++; vagas += +x.vagas || 0; eleitos += +x.eleitos || 0; if (+x.eleitos > 0) comEl++;
      var ps = x.partidos || {};
      Object.keys(ps).forEach(function (sg) { soma[sg] = (soma[sg] || 0) + (+ps[sg] || 0); });
    });
    var lista = Object.keys(soma).map(function (sg) { return { sigla: sg, em2027: soma[sg], atual: 0 }; })
      .sort(function (p, q) { return (q.em2027 - p.em2027) || p.sigla.localeCompare(q.sigla); });
    lista.forEach(function (p, i) { p.cor = corPartidoCamara(p.sigla, i); });
    return { ps: lista, vagas: vagas, eleitos: eleitos, ufs: ufs, comEl: comEl, temAtual: false };
  }
  function subAsmBr(cm) {
    if (!cm.eleitos) return "aguardando os deputados estaduais eleitos (ESTADOS.bat)";
    var n = inteiro(cm.eleitos);
    return n + " deputados estaduais e distritais eleitos" + (cm.comEl < 27 ? " · " + cm.comEl + " de 27 estados" : " · soma dos 27 estados");
  }
  function telaAsmBr(v) {
    var cm = assembleiasBr(), W = v ? 540 : 1280, H = v ? 960 : 720, o, tit = "ASSEMBLEIAS LEGISLATIVAS";
    var sl = !cm.eleitos ? { texto: "AGUARDANDO", cor: C.trilho } : (cm.comEl >= 27 && cm.eleitos >= cm.vagas ? { texto: "TOTALIZAÇÃO FINAL", cor: C.verde } : { texto: "PARCIAL", cor: C.vermelho });
    var rod = "Fonte: TSE — deputados estaduais (cargo 7) e distritais do DF (cargo 8) eleitos, somados por partido";
    // o hemiciclo vira por partido em proporcao (1.059 cadeiras nao cabem uma a uma)
    if (!v) {
      o = t(73, 57, tit + " — BRASIL", { s: 34, b: true, ls: 1, max: 667 }) + t(73, 85, subAsmBr(cm), { s: 18, c: C.apagado, max: 660 }) + seloH(W, sl);
      if (!cm.eleitos) return svg(W, H, o + t(640, 380, "aguardando o ESTADOS.bat ler as Assembleias", { s: 22, c: C.apagado, a: "middle" }));
      o += hemiciclo(385, 640, 320, 120, hemiCamara(cm), "em2027") + rotuloHemi(385, 640, "2027", cm.eleitos, 1.1);
      o += tabelaCamara(745, 1207, 150, 32, cm, 20, 15, [1010, 1110, 1207]);
      return svg(W, H, o + t(73, 700, rod, { s: 12, c: C.apagado2, max: 1134 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "ASSEMBLEIAS — BRASIL", { s: 28, b: true, ls: 1, max: W - 88 }) + t(53, 106, subAsmBr(cm), { s: 13, c: C.apagado, max: W - 88 }) + seloV(W, sl);
    if (!cm.eleitos) return svg(W, H, o + t(270, 480, "aguardando o ESTADOS.bat", { s: 18, c: C.apagado, a: "middle" }));
    o += hemiciclo(270, 400, 232, 88, hemiCamara(cm), "em2027") + rotuloHemi(270, 400, "2027", cm.eleitos, 1);
    o += tabelaCamara(40, 505, 448, 29, cm, 19, 15, [330, 420, 505]);
    return svg(W, H, o + t(35, 950, "Fonte: TSE — deputados estaduais e distritais eleitos", { s: 11, c: C.apagado2, max: 470 }));
  }
  G["assembleias-h"] = function () { return telaAsmBr(false); };
  G["assembleias-v"] = function () { return telaAsmBr(true); };

  // ---- OS 10 DEPUTADOS FEDERAIS MAIS VOTADOS DO BRASIL ----------------------
  // Eleitos marcados pelo TSE em cada estado (ESTADOS.bat), juntos e
  // ordenados pelos votos nominais do proprio boletim.
  function topDep(n) {
    var cm = (window.GCTSE_ESTADOS || {}).camara || {}, todos = [], ufs = 0;
    Object.keys(cm).forEach(function (u) { var l = comoLista((cm[u] || {}).lista); if (l.length) ufs++; l.forEach(function (c) { todos.push({ c: c, u: u }); }); });
    todos.sort(function (a, b) { return ((+b.c.votos || 0) - (+a.c.votos || 0)) || String(a.c.nome).localeCompare(String(b.c.nome), "pt-BR"); });
    return { lista: todos.slice(0, n), ufs: ufs, total: todos.length };
  }
  function telaTopDep(v) {
    var T = topDep(10), W = v ? 540 : 1280, H = v ? 960 : 720, o, l = T.lista, max = l.length ? +l[0].c.votos || 1 : 1;
    var sub = "Câmara dos Deputados · votos nominais" + (T.ufs && T.ufs < 27 ? " · " + T.ufs + " de 27 estados lidos" : "");
    var sl = !T.ufs ? { texto: "AGUARDANDO", cor: C.trilho } : (T.ufs >= 27 ? { texto: "TOTALIZAÇÃO FINAL", cor: C.verde } : { texto: "PARCIAL", cor: C.vermelho });
    if (!v) {
      o = t(73, 57, "OS 10 DEPUTADOS FEDERAIS MAIS VOTADOS", { s: 32, b: true, ls: 1, max: 667 }) + t(73, 85, sub, { s: 17, c: C.apagado, max: 660 }) + seloH(W, sl);
      if (!l.length) return svg(W, H, o + t(640, 380, "aguardando os deputados eleitos (ESTADOS.bat)", { s: 22, c: C.apagado, a: "middle" }));
      l.forEach(function (it, i) {
        var y = 106 + i * 58, c = it.c, cc = corPartidoCamara(c.partido, i);
        o += r(73, y, 1134, 52, i % 2 ? "rgba(8,14,32,0.70)" : "rgba(8,14,32,0.86)", 6);
        o += t(120, y + 36, (i + 1) + "º", { s: 24, b: true, a: "end", c: i < 3 ? "#ffd43b" : C.texto });
        o += fotoDep(it.u, c, 134, y + 4, 33, 44);
        o += r(178, y + 10, 5, 32, cc, 2);
        o += t(193, y + 25, c.nome, { s: 21, b: true, max: 450 }) + t(193, y + 44, (c.partido || "") + "  ·  " + (DEP_UF[it.u] || it.u.toUpperCase()), { s: 13, c: C.apagado, max: 450 });
        o += barraFina(680, y + 22, 330, (+c.votos || 0) / max, cc);
        o += t(1190, y + 33, inteiro(c.votos), { s: 24, b: true, a: "end" }) + t(1190, y + 48, "votos", { s: 10, c: C.apagado, a: "end" });
      });
      return svg(W, H, o + t(73, 704, "Fonte: TSE — boletins de Deputado Federal dos 27 estados (entre os eleitos)", { s: 12, c: C.apagado2, max: 1134 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "10 MAIS VOTADOS", { s: 30, b: true, ls: 1 }) + t(53, 106, "Deputados federais · Brasil", { s: 14, c: C.apagado }) + seloV(W, sl);
    if (!l.length) return svg(W, H, o + t(270, 480, "aguardando os deputados eleitos", { s: 18, c: C.apagado, a: "middle" }));
    l.forEach(function (it, i) {
      var y = 164 + i * 77, c = it.c, cc = corPartidoCamara(c.partido, i);
      o += r(35, y, 470, 71, i % 2 ? "rgba(8,14,32,0.70)" : "rgba(8,14,32,0.86)", 6);
      o += t(72, y + 44, (i + 1) + "º", { s: 22, b: true, a: "end", c: i < 3 ? "#ffd43b" : C.texto });
      o += fotoDep(it.u, c, 82, y + 8, 41, 55);
      o += r(131, y + 12, 4, 46, cc, 2);
      o += t(143, y + 30, c.nome, { s: 18, b: true, max: 350 }) + t(143, y + 50, (c.partido || "") + " · " + it.u.toUpperCase(), { s: 12, c: C.apagado, max: 200 });
      o += t(495, y + 52, inteiro(c.votos) + " votos", { s: 15, b: true, a: "end" });
    });
    return svg(W, H, o + t(35, 950, "Fonte: TSE — entre os deputados federais eleitos", { s: 11, c: C.apagado2 }));
  }
  G["topdep-h"] = function () { return telaTopDep(false); };
  G["topdep-v"] = function () { return telaTopDep(true); };


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
    var url = tse.base + "/" + tse.ciclo + "/" + (tse.eleicao_camara || tse.eleicao) + "/fotos/" + u + "/" + c.sqcand + ".jpeg"; url = viaLocal(url);
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
    var url = tse.base + "/" + tse.ciclo + "/" + ele + "/fotos/br/" + c.sqcand + ".jpeg"; url = viaLocal(url);
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
    if (ensaioAtivo()) return { texto: "ENSAIO — NÃO VAI AO AR", cor: C.vermelho };
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
    var url = tse.base + "/" + tse.ciclo + "/" + (st.g.eleicao || tse.eleicao) + "/fotos/" + k + "/" + st.c.sqcand + ".jpeg"; url = viaLocal(url);
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

  // ---- PERFIL DA NOVA CAMARA: renovacao, idade, escolaridade, cor/raca ------
  // Atributos de cada candidato: arquivo "Candidatos" do TSE (Dados Abertos),
  // importado pelo IMPORTAR-CANDIDATOS.bat (web\candidatos-genero.js, campo
  // perfil = [idade na posse, instrucao, cor/raca, disputava reeleicao]).
  // Eleitos de 2026 = boletim do TSE ao vivo (estados.js), cruzados pelo
  // sqcand. Ano anterior = eleitos daquele arquivo.
  var FAIXAS_IDADE = [[0, 34, "até 34"], [35, 44, "35–44"], [45, 54, "45–54"], [55, 64, "55–64"], [65, 200, "65 ou mais"]];
  var COR_PERFIL = "#2b84ff";
  function somaPerfil(lista) {
    var a = { n: 0, idN: 0, idS: 0, faixa: [0, 0, 0, 0, 0], grau: {}, grauN: 0, cor: {}, corN: 0, re: 0, novo: 0, reN: 0 };
    lista.forEach(function (p) {
      p = comoLista(p); if (p.length < 4) return;
      a.n++;
      var id = +p[0];
      if (id >= 18) { a.idN++; a.idS += id; for (var i = 0; i < FAIXAS_IDADE.length; i++) if (id >= FAIXAS_IDADE[i][0] && id <= FAIXAS_IDADE[i][1]) { a.faixa[i]++; break; } }
      if (+p[1] >= 0) { a.grau[p[1]] = (a.grau[p[1]] || 0) + 1; a.grauN++; }
      if (+p[2] >= 0) { a.cor[p[2]] = (a.cor[p[2]] || 0) + 1; a.corN++; }
      if (+p[3] === 1) { a.re++; a.reN++; } else if (+p[3] === 0) { a.novo++; a.reN++; }
    });
    return a;
  }
  function perfilCamara() {
    var gen = window.GCTSE_GENERO;
    if (!gen || !gen.anos) return null;
    var anos = Object.keys(gen.anos).sort(), aN = anos[anos.length - 1], aA = anos.length > 1 ? anos[anos.length - 2] : null;
    var pN = gen.anos[aN].perfil;
    if (!pN) return { semPerfil: true };
    var cm = E().camara || {}, ps = [], tot = 0, ufs = 0;
    Object.keys(cm).forEach(function (u) {
      var l = comoLista(cm[u].lista); if (!l.length) return; ufs++;
      l.forEach(function (c) { tot++; var p = pN[String(c.sqcand)]; if (p) ps.push(p); });
    });
    var pA = aA && gen.anos[aA].perfil ? gen.anos[aA].perfil : null;
    return { ano: aN, anoA: pA ? aA : null, eleitos: tot, ufs: ufs, achados: ps.length, n: somaPerfil(ps),
      a: pA ? somaPerfil(Object.keys(pA).map(function (k) { return pA[k]; })) : null,
      rg: comoLista(gen.rotulos_grau), rc: comoLista(gen.rotulos_cor) };
  }
  function rotuloPerfil(s) {
    s = String(s || "").toLowerCase().replace(/^ensino /, "").replace("não divulgável", "não divulgada");
    return s.charAt(0).toUpperCase() + s.slice(1);
  }
  // barra 2026 + traco branco na posicao do ano anterior
  function barraPerfil(x, y, w, h, f, fA) {
    var o = r(x, y, w, h, "rgba(255,255,255,0.10)", 3) + (f > 0 ? r(x, y, Math.max(4, w * Math.min(1, f)), h, COR_PERFIL, 3) : "");
    if (fA != null) o += r(x + w * Math.min(1, fA) - 1.5, y - 4, 3, h + 8, "#ffffff", 0);
    return o;
  }
  function pctDe(n, d) { return d ? 100 * n / d : 0; }
  function categorias(cont, tot, contA, totA, rot, max) {
    var ks = Object.keys(cont).sort(function (a, b) { return cont[b] - cont[a]; });
    if (contA) Object.keys(contA).forEach(function (k) { if (ks.indexOf(k) < 0) ks.push(k); });
    return ks.slice(0, max).map(function (k) { return { nome: rotuloPerfil(rot[+k]), f: tot ? (cont[k] || 0) / tot : 0, fA: contA && totA ? (contA[k] || 0) / totA : null }; });
  }
  function painelPerfil(x, y, w, h, titulo) { return r(x, y, w, h, "rgba(8,14,32,0.84)", 10) + t(x + 18, y + 28, titulo, { s: 14, b: true, c: "#c9d6e6", ls: 1 }); }
  function linhasPerfil(x, y, w, passo, itens, fs) {
    var o = "";
    itens.forEach(function (it, i) {
      var yy = y + i * passo;
      o += t(x, yy, it.nome, { s: fs, b: true, max: w * 0.42 }) + t(x + w, yy, pct1(100 * it.f), { s: fs + 2, b: true, a: "end" });
      o += barraPerfil(x + w * 0.44, yy - fs * 0.75, w * 0.40, fs * 0.8, it.f, it.fA);
    });
    return o;
  }
  function telaPerfil(v) {
    var P = perfilCamara(), W = v ? 540 : 1280, H = v ? 960 : 720, o, tit = "PERFIL DA NOVA CÂMARA";
    var cab = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 26, b: true, ls: 1, max: 450 }) : t(73, 57, tit, { s: 36, b: true, ls: 1, max: 660 });
    if (!P || P.semPerfil) return svg(W, H, cab + t(W / 2, H / 2 - 10, "falta o arquivo de candidatos do TSE", { s: v ? 18 : 24, c: C.apagado, a: "middle" }) +
      t(W / 2, H / 2 + 22, "rode o IMPORTAR-CANDIDATOS.bat (consulta_cand_" + (P ? "" : "2026") + "…, Dados Abertos)", { s: v ? 12 : 16, c: C.apagado2, a: "middle", max: W - 60 }));
    if (!P.achados) return svg(W, H, cab + t(W / 2, H / 2, P.eleitos ? "os eleitos do boletim não estão no arquivo de candidatos importado" : "aguardando os deputados eleitos (ESTADOS.bat)", { s: v ? 16 : 22, c: C.apagado, a: "middle", max: W - 60 }));
    var n = P.n, a = P.a, sub = P.eleitos + " deputados federais eleitos" + (P.ufs < 27 ? " (" + P.ufs + " de 27 estados)" : "") + (P.anoA ? " · traço branco = eleitos de " + P.anoA : "");
    var media = n.idN ? n.idS / n.idN : null, mediaA = a && a.idN ? a.idS / a.idN : null;
    var fRe = pctDe(n.re, n.reN), fReA = a ? pctDe(a.re, a.reN) : null;
    var sup = 0, supA = 0;
    P.rg.forEach(function (rot, i) { if (/^SUPERIOR COMPLETO/.test(rot)) { sup += n.grau[i] || 0; if (a) supA += a.grau[i] || 0; } });
    var graus = categorias(n.grau, n.grauN, a ? a.grau : null, a ? a.grauN : 0, P.rg, 4);
    var cores = categorias(n.cor, n.corN, a ? a.cor : null, a ? a.corN : 0, P.rc, 6);
    var faixas = FAIXAS_IDADE.map(function (fx, i) { return { nome: fx[2], f: n.idN ? n.faixa[i] / n.idN : 0, fA: a && a.idN ? a.faixa[i] / a.idN : null }; });
    var rod = "Fonte: TSE — Dados Abertos (Candidatos: idade na posse, grau de instrução, cor/raça, reeleição) e boletim de resultados. Perfil de " + P.achados + " de " + P.eleitos + " eleitos. Reeleito = disputava a reeleição; novo = sem mandato atual (inclui ex-deputados).";
    function comp(atual, ant, suf) { if (ant == null) return ""; var d = atual - ant; return P.anoA + ": " + pct1(ant).replace("%", suf || "%") + (Math.abs(d) >= 0.05 ? "  (" + (d > 0 ? "+" : "−") + Number(Math.abs(d)).toFixed(1).replace(".", ",") + " p.p.)" : ""); }
    if (!v) {
      o = cab + t(73, 85, sub, { s: 16, c: C.apagado, max: 660 }) + seloH(W, { texto: P.ufs >= 27 ? "513 CADEIRAS" : "PARCIAL", cor: P.ufs >= 27 ? C.verde : C.vermelho });
      // renovacao
      o += painelPerfil(73, 106, 556, 262, "RENOVAÇÃO");
      o += t(93, 190, pct1(fRe), { s: 54, b: true }) + t(93, 216, n.re + " reeleitos", { s: 16, c: "#c9d6e6" });
      o += t(609, 190, pct1(100 - fRe), { s: 54, b: true, a: "end", c: COR_PERFIL }) + t(609, 216, n.novo + " novos no mandato", { s: 16, c: "#c9d6e6", a: "end" });
      o += r(93, 238, 516, 26, COR_PERFIL, 4) + r(93, 238, 516 * fRe / 100, 26, "#c9d6e6", 4);
      if (fReA != null) o += r(93 + 516 * fReA / 100 - 1.5, 232, 3, 38, "#ffffff", 0);
      o += t(93, 300, comp(fRe, fReA) ? "reeleitos em " + comp(fRe, fReA) : "", { s: 14, c: C.apagado, max: 516 });
      o += t(93, 346, "reeleito = disputava a reeleição · novo = sem mandato atual", { s: 12, c: C.apagado2, max: 516 });
      // idade
      o += painelPerfil(651, 106, 556, 262, "IDADE NA POSSE");
      o += t(671, 180, media ? Number(media).toFixed(1).replace(".", ",") : "—", { s: 44, b: true }) + t(671, 202, "anos, em média" + (mediaA ? " · " + P.anoA + ": " + Number(mediaA).toFixed(1).replace(".", ",") : ""), { s: 13, c: C.apagado });
      o += linhasPerfil(671, 238, 516, 27, faixas, 14);
      // escolaridade
      o += painelPerfil(73, 384, 556, 288, "ESCOLARIDADE");
      o += t(93, 460, pct1(pctDe(sup, n.grauN)), { s: 44, b: true }) + t(93, 482, "com superior completo" + (a ? " · " + P.anoA + ": " + pct1(pctDe(supA, a.grauN)) : ""), { s: 13, c: C.apagado });
      o += linhasPerfil(93, 524, 516, 38, graus, 15);
      // cor/raca
      o += painelPerfil(651, 384, 556, 288, "COR / RAÇA (autodeclarada)");
      o += linhasPerfil(671, 450, 516, 36, cores, 15);
      return svg(W, H, o + t(73, 696, rod, { s: 10, c: C.apagado2, max: 1134 }) + t(73, 710, "▮ " + P.ano + "  ·  traço branco = " + (P.anoA || "—"), { s: 10, c: C.apagado2 }));
    }
    o = cab + t(53, 106, P.eleitos + " eleitos" + (P.anoA ? " · traço = " + P.anoA : ""), { s: 13, c: C.apagado, max: 450 }) + seloV(W, { texto: P.ufs >= 27 ? "513 CADEIRAS" : "PARCIAL", cor: P.ufs >= 27 ? C.verde : C.vermelho });
    o += painelPerfil(35, 160, 470, 170, "RENOVAÇÃO");
    o += t(55, 232, pct1(fRe), { s: 40, b: true }) + t(55, 254, n.re + " reeleitos", { s: 13, c: "#c9d6e6" });
    o += t(485, 232, pct1(100 - fRe), { s: 40, b: true, a: "end", c: COR_PERFIL }) + t(485, 254, n.novo + " novos", { s: 13, c: "#c9d6e6", a: "end" });
    o += r(55, 272, 430, 20, COR_PERFIL, 4) + r(55, 272, 430 * fRe / 100, 20, "#c9d6e6", 4);
    if (fReA != null) o += r(55 + 430 * fReA / 100 - 1.5, 267, 3, 30, "#ffffff", 0);
    o += t(55, 318, comp(fRe, fReA) ? "reeleitos em " + comp(fRe, fReA) : "", { s: 12, c: C.apagado, max: 430 });
    o += painelPerfil(35, 342, 470, 210, "IDADE NA POSSE");
    o += t(55, 406, media ? Number(media).toFixed(1).replace(".", ",") + " anos" : "—", { s: 30, b: true }) + t(485, 406, mediaA ? P.anoA + ": " + Number(mediaA).toFixed(1).replace(".", ",") : "", { s: 13, c: C.apagado, a: "end" });
    o += linhasPerfil(55, 440, 430, 24, faixas, 13);
    o += painelPerfil(35, 564, 470, 180, "ESCOLARIDADE");
    o += t(55, 628, pct1(pctDe(sup, n.grauN)), { s: 30, b: true }) + t(175, 628, "com superior completo", { s: 13, c: C.apagado });
    o += linhasPerfil(55, 660, 430, 22, graus, 13);
    o += painelPerfil(35, 756, 470, 180, "COR / RAÇA");
    o += linhasPerfil(55, 810, 430, 23, cores, 12);
    return svg(W, H, o + t(35, 950, "Fonte: TSE — Dados Abertos (Candidatos) e boletim", { s: 10, c: C.apagado2 }));
  }
  G["perfilcamara-h"] = function () { return telaPerfil(false); };
  G["perfilcamara-v"] = function () { return telaPerfil(true); };

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
    var url = tse.base + "/" + tse.ciclo + "/" + (tse.eleicao_1turno || tse.eleicao) + "/fotos/" + k + "/" + c.sqcand + ".jpeg"; url = viaLocal(url);
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
    // nome do estado por extenso na faixa (encolhe se nao couber)
    var nomeUf = DEP_UF[k] || k.toUpperCase(), fsU = Math.round(fn * 1.2), wChip = Math.min(w - 8, nomeUf.length * fsU * 0.66 + 14);
    o += r(x + (w - wChip) / 2, y + 2, wChip, hf - 4, "#0b1220", 2) + t(x + w / 2, y + hf * 0.72, nomeUf, { s: fsU, b: true, a: "middle", max: wChip - 8 });
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
    var sub = cs.n + (cs.n === 1 ? " eleito" : " eleitos") + " no Brasil · 2 por estado · cor = partido do eleito";
    var tit = "SENADORES";
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

  // =====================================================================
  // ANALISE DO 2o TURNO: ainda da para virar, placar dos governadores,
  // mapa das viradas, margem mais apertada, ganho de votos e abstencao
  // por estado. So numeros do TSE (dados.js / estados.js); a unica conta e
  // a de "faltam": eleitores em secoes ainda nao totalizadas (TSE: esnt).
  // =====================================================================
  function misturar(hex, fundo, t0) {
    var a = String(hex).replace("#", ""), b = String(fundo).replace("#", "");
    if (a.length !== 6 || b.length !== 6) return hex;
    var o = "#";
    for (var i = 0; i < 3; i++) {
      var x = parseInt(a.substr(i * 2, 2), 16), y = parseInt(b.substr(i * 2, 2), 16);
      o += ("0" + Math.round(x * t0 + y * (1 - t0)).toString(16)).slice(-2);
    }
    return o;
  }
  function faltamDe(x) {
    if (!x) return null;
    var e = x.eleitorado || {}, s0 = x.secoes || {};
    if (e.faltam != null) return +e.faltam;
    if (e.aptos != null && e.em_totalizadas != null) return Math.max(0, e.aptos - e.em_totalizadas);
    if (s0.pct >= 100) return 0;
    return null;
  }
  function nomeCurto(c) { var n = String(c && c.nome || ""); return n.length > 18 ? n.split(" ")[0] : n; }
  // Situacao "ainda da para virar?" de um boletim (Brasil ou estado).
  function contaVirada(x) {
    var cs = x ? candidatos(x).filter(function (c) { return c.votos > 0; }) : [];
    if (cs.length < 2) return null;
    var c1 = cs[0], c2 = cs[1], lead = c1.votos - c2.votos, F = faltamDe(x);
    var r = { c1: c1, c2: c2, lead: lead, faltam: F, urnas: x.secoes ? x.secoes.pct : null, eleito: !!c1.eleito };
    if (F == null) r.tipo = "?";
    else if (lead > F) r.tipo = "decidido";
    else { r.tipo = "aberto"; r.precisa = Math.min(100, 100 * (lead + F) / (2 * F)); }
    if (r.eleito) r.tipo = "decidido";
    return r;
  }
  function chipVirada(rv, x, y, k) {
    k = k || 1;
    if (!rv) return t(x, y, "—", { s: Math.round(14 * k), c: C.apagado, a: "end" });
    if (rv.tipo === "decidido") return r(x - 104 * k, y - 15 * k, 104 * k, 21 * k, C.verde, 3) + t(x - 52 * k, y, rv.eleito ? "ELEITO" : "DECIDIDO", { s: Math.round(13 * k), b: true, a: "middle", ls: 1 });
    if (rv.tipo === "?") return t(x, y, "sem o dado de faltam", { s: Math.round(12 * k), c: C.apagado, a: "end" });
    return t(x, y, "precisa " + pct1(rv.precisa), { s: Math.round(15 * k), b: true, c: rv.precisa >= 60 ? "#ffd43b" : "#ff8787", a: "end" });
  }
  G["virar-h"] = function () {
    var W = 1280, H = 720, f = fontePres(false), rb = contaVirada(f.br), o;
    o = t(73, 57, "AINDA DÁ PARA VIRAR?", { s: 36, b: true, ls: 1 }) + t(73, 85, "Presidente · " + turnoTxt(f) + " · " + subtitulo(), { s: 18, c: C.apagado, max: 640 }) + seloH(W, seloDe(f));
    o += r(73, 106, 1134, 150, "rgba(8,14,32,0.84)", 10);
    if (rb) {
      o += r(73, 106, 8, 150, cor(rb.c1), 4) + t(100, 140, "BRASIL", { s: 16, b: true, c: C.apagado, ls: 2 });
      o += t(100, 182, rb.c1.nome + " à frente por " + inteiro(rb.lead) + " votos", { s: 30, b: true, max: 640 });
      o += t(100, 214, "faltam apurar no máximo " + (rb.faltam == null ? "—" : inteiro(rb.faltam)) + " eleitores (seções não totalizadas)", { s: 16, c: C.apagado, max: 640 });
      o += t(100, 240, "urnas apuradas " + pct(rb.urnas), { s: 14, c: C.apagado2 });
      if (rb.tipo === "decidido") o += r(800, 140, 380, 80, C.verde, 8) + t(990, 176, rb.eleito ? "ELEITO" : "DECIDIDO", { s: 34, b: true, a: "middle", ls: 2 }) + t(990, 204, rb.eleito ? "segundo o TSE" : "pela conta: a vantagem é maior que tudo o que falta", { s: 13, a: "middle" });
      else if (rb.tipo === "aberto") o += t(1180, 166, nomeCurto(rb.c2) + " precisaria de", { s: 18, c: "#c9d6e6", a: "end" }) + t(1180, 212, pct1(rb.precisa), { s: 48, b: true, c: rb.precisa >= 60 ? "#ffd43b" : "#ff8787", a: "end" }) + t(1180, 238, "dos votos que faltam (se todos votarem)", { s: 13, c: C.apagado, a: "end" });
    } else o += t(640, 190, "aguardando o boletim do TSE", { s: 22, c: C.apagado, a: "middle" });
    var lin = Object.keys(DEP_UF).map(function (k) { return { k: k, r: contaVirada(f.uf(k)) }; })
      .sort(function (a, b) {
        var ra = a.r, rb2 = b.r, va = !ra ? 3 : ra.tipo === "aberto" ? 0 : ra.tipo === "?" ? 1 : 2, vb = !rb2 ? 3 : rb2.tipo === "aberto" ? 0 : rb2.tipo === "?" ? 1 : 2;
        return va - vb || (ra && rb2 && ra.tipo === "aberto" ? ra.precisa - rb2.precisa : 0) || DEP_UF[a.k].localeCompare(DEP_UF[b.k], "pt-BR");
      });
    var aberto = lin.filter(function (l) { return l.r && l.r.tipo === "aberto"; }).length;
    o += t(73, 290, "ESTADOS — " + aberto + " em aberto", { s: 15, b: true, c: "#c9d6e6", ls: 1 }) + t(1207, 290, "% que o 2º colocado precisaria dos votos que faltam", { s: 12, c: C.apagado, a: "end" });
    lin.forEach(function (l, i) {
      var col = i < 14 ? 0 : 1, li = i < 14 ? i : i - 14, x = 73 + col * 580, y = 318 + li * 26.5;
      o += r(x, y - 15, 556, 23, i % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)", 3);
      o += t(x + 8, y + 2, DEP_UF[l.k], { s: 13, b: true, max: 170 });
      if (l.r) {
        o += r(x + 190, y - 9, 10, 12, cor(l.r.c1), 2) + t(x + 206, y + 2, nomeCurto(l.r.c1) + " +" + inteiro(l.r.lead), { s: 13, c: "#c9d6e6", max: 220 });
        o += chipVirada(l.r, x + 550, y + 2, 0.85);
      } else o += t(x + 550, y + 2, "aguardando", { s: 12, c: C.apagado, a: "end" });
    });
    return svg(W, H, o + t(73, 708, "Fonte: TSE · conta: vantagem × eleitores em seções ainda não totalizadas (TSE: esnt). \"Decidido\" = nem todos os que faltam virariam.", { s: 11, c: C.apagado2, max: 1134 }));
  };
  G["virar-v"] = function () {
    var W = 540, H = 960, f = fontePres(false), rb = contaVirada(f.br), o;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "DÁ PARA VIRAR?", { s: 30, b: true, ls: 1 }) + t(53, 106, "Presidente · " + turnoTxt(f), { s: 14, c: C.apagado }) + seloV(W, seloDe(f));
    o += r(35, 166, 470, 210, "rgba(8,14,32,0.84)", 10);
    if (rb) {
      o += r(35, 166, 7, 210, cor(rb.c1), 3) + t(55, 196, "BRASIL", { s: 14, b: true, c: C.apagado, ls: 2 });
      o += t(55, 230, rb.c1.nome, { s: 24, b: true, max: 430 }) + t(55, 256, "à frente por " + inteiro(rb.lead) + " votos", { s: 18, c: "#c9d6e6" });
      o += t(55, 282, "faltam até " + (rb.faltam == null ? "—" : inteiro(rb.faltam)) + " eleitores", { s: 14, c: C.apagado });
      if (rb.tipo === "decidido") o += r(55, 300, 430, 56, C.verde, 6) + t(270, 338, rb.eleito ? "ELEITO" : "DECIDIDO", { s: 28, b: true, a: "middle", ls: 2 });
      else if (rb.tipo === "aberto") o += t(55, 316, nomeCurto(rb.c2) + " precisaria de", { s: 14, c: "#c9d6e6" }) + t(485, 356, pct1(rb.precisa), { s: 40, b: true, c: rb.precisa >= 60 ? "#ffd43b" : "#ff8787", a: "end" });
    }
    var lin = Object.keys(DEP_UF).map(function (k) { return { k: k, r: contaVirada(f.uf(k)) }; }).filter(function (l) { return l.r && l.r.tipo === "aberto"; })
      .sort(function (a, b) { return a.r.precisa - b.r.precisa; }).slice(0, 14);
    o += t(35, 410, "ESTADOS EM ABERTO (" + lin.length + ")", { s: 14, b: true, c: "#c9d6e6", ls: 1 });
    lin.forEach(function (l, i) {
      var y = 440 + i * 34;
      o += r(35, y - 18, 470, 28, i % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)", 3);
      o += r(45, y - 10, 8, 14, cor(l.r.c1), 2) + t(60, y + 2, DEP_UF[l.k], { s: 14, b: true, max: 200 }) + chipVirada(l.r, 495, y + 2, 0.9);
    });
    if (!lin.length) o += t(270, 470, "nenhum estado em aberto", { s: 16, c: C.apagado, a: "middle" });
    return svg(W, H, o + t(35, 948, "Fonte: TSE · vantagem × eleitores em seções não totalizadas", { s: 10, c: C.apagado2 }));
  };

  // ---- PLACAR DOS GOVERNADORES NO 2o TURNO ----------------------------------
  function estadosGov2t() {
    return Object.keys(DEP_UF).filter(function (k) {
      var u = (E().ufs || {})[k], g = u && u.gov && u.gov.tem ? u.gov : null;
      if (!g) return false;
      return +g.turno === 2 || comoLista(g.candidatos).some(function (c) { return c.segundo_turno; });
    }).sort(function (a, b) { return DEP_UF[a].localeCompare(DEP_UF[b], "pt-BR"); });
  }
  function cartaoGov2t(k, x, y, w, h, k2) {
    var g = ((E().ufs || {})[k] || {}).gov, cs = comoLista(g.candidatos), do2 = +g.turno === 2;
    var dois = do2 ? cs.slice(0, 2) : cs.filter(function (c) { return c.segundo_turno; }).slice(0, 2);
    if (dois.length < 2) dois = cs.slice(0, 2);
    var o = r(x, y, w, h, "rgba(8,14,32,0.84)", 8);
    o += t(x + 14, y + 22 * k2, DEP_UF[k], { s: Math.round(16 * k2), b: true, ls: 1 });
    o += t(x + w - 12, y + 22 * k2, do2 ? "urnas " + pct(g.urnas_pct) : "1º turno · vão ao 2º turno", { s: Math.round(12 * k2), c: C.apagado, a: "end" });
    var lh = (h - 30 * k2) / 2;
    dois.forEach(function (c, i) {
      var yy = y + 30 * k2 + i * lh, cc = corPartidoCamara(c.partido, i), fh = lh - 6, fw = fh * 0.78;
      o += fotoOuSilhueta(urlFotoGov(k, { c: c, g: g }), x + 12, yy + 2, fw, fh);
      var tx = x + 20 + fw;
      o += t(tx, yy + lh * 0.55, c.nome + "  ·  " + c.partido, { s: Math.round(15 * k2), b: true, max: w - (tx - x) - 120 });
      o += barraFina(tx, yy + lh - 10, w - (tx - x) - 110, (c.pct || 0) / 100, cc);
      o += t(x + w - 12, yy + lh * 0.62, pct(c.pct), { s: Math.round(22 * k2), b: true, a: "end" });
      if (c.eleito) o += r(x + w - 92, yy + 2, 80, 16, C.verde, 2) + t(x + w - 52, yy + 14, "ELEITO", { s: 11, b: true, a: "middle" });
    });
    return o;
  }
  function telaGov2t(v) {
    var ls = estadosGov2t(), o, n = ls.length;
    var nEl = ls.filter(function (k) { return comoLista(((E().ufs || {})[k] || {}).gov.candidatos).some(function (c) { return c.eleito; }); }).length;
    var sub = n + " estados no 2º turno · " + nEl + (nEl === 1 ? " já definido" : " já definidos");
    var sl = { texto: nEl >= n && n ? "TODOS DEFINIDOS" : (n - nEl) + " EM DISPUTA", cor: nEl >= n && n ? C.verde : C.destaque };
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, "GOVERNADORES — 2º TURNO", { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, sub, { s: 18, c: C.apagado }) + seloH(W, sl);
      if (!n) return svg(W, H, o + t(640, 380, "nenhum estado com 2º turno de governador", { s: 22, c: C.apagado, a: "middle" }));
      var rows = Math.ceil(n / 2), ch = Math.min(116, (590 - (rows - 1) * 8) / rows);
      ls.forEach(function (k, i) { o += cartaoGov2t(k, 73 + (i % 2) * 575, 106 + Math.floor(i / 2) * (ch + 8), 559, ch, Math.min(1, ch / 108)); });
      return svg(W, H, o + t(73, 708, "Fonte: TSE — Governador, 2º turno" + (E().turno === 2 ? "" : " (hoje: os dois que vão ao 2º turno, % do 1º turno)"), { s: 11, c: C.apagado2 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "GOVERNADORES", { s: 30, b: true, ls: 1 }) + t(53, 106, "2º turno · " + sub, { s: 13, c: C.apagado, max: 450 }) + seloV(W2, sl);
    if (!n) return svg(W2, H2, o + t(270, 480, "nenhum estado com 2º turno", { s: 18, c: C.apagado, a: "middle" }));
    var ch2 = Math.min(118, (770 - (n - 1) * 6) / n);
    ls.forEach(function (k, i) { o += cartaoGov2t(k, 35, 164 + i * (ch2 + 6), 470, ch2, Math.min(0.95, ch2 / 112)); });
    return svg(W2, H2, o + t(35, 950, "Fonte: TSE — Governador, 2º turno", { s: 10, c: C.apagado2 }));
  }
  G["gov2t-h"] = function () { return telaGov2t(false); };
  G["gov2t-v"] = function () { return telaGov2t(true); };

  // ---- MAPA DAS VIRADAS (Presidente): quem liderava no 1o e quem lidera agora
  function viradas() {
    var f1 = fontePres(true), f2 = fontePres(false), out = [];
    if (!f1.guardado) return null;
    Object.keys(DEP_UF).forEach(function (k) {
      var l1 = liderF(f1, k), l2 = liderF(f2, k);
      if (l1 && l2 && String(l1.numero) !== String(l2.numero)) out.push({ k: k, de: l1, para: l2, x2: f2.uf(k) });
    });
    return { lista: out, f1: f1, f2: f2 };
  }
  function mapaViradas(vr, x, y, esc) {
    var M = window.MAPA_BRASIL, o = '<g transform="translate(' + x + " " + y + ") scale(" + esc + ')">', vir = {};
    vr.lista.forEach(function (v) { vir[v.k] = v; });
    var k, e, l;
    for (k in M.estados) {
      e = M.estados[k]; l = liderF(vr.f2, k);
      var c0 = l ? cor(l) : C.semDado;
      o += '<path d="' + e.path + '" fill="' + (vir[k] ? c0 : misturar(c0, "#0b1220", 0.32)) + '" stroke="' + C.fundo + '" stroke-width="' + (1.2 / esc).toFixed(2) + '"/>';
    }
    for (k in vir) { e = M.estados[k]; o += '<path d="' + e.path + '" fill="none" stroke="#ffffff" stroke-width="' + (3 / esc).toFixed(2) + '" stroke-linejoin="round"/>'; }
    var contorno = ' stroke="' + C.fundo + '" stroke-width="' + (3 / esc).toFixed(2) + '" paint-order="stroke"';
    for (k in vir) { e = M.estados[k]; o += '<text x="' + e.cx + '" y="' + (e.cy + 5) + '" font-size="' + (13 / esc).toFixed(1) + '" font-weight="700" fill="#fff" text-anchor="middle"' + contorno + ">" + k.toUpperCase() + "</text>"; }
    return o + "</g>";
  }
  function telaViradas(v) {
    var vr = viradas(), W = v ? 540 : 1280, H = v ? 960 : 720, o;
    var tit = "ESTADOS QUE VIRARAM";
    if (!vr) {
      o = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 28, b: true, ls: 1 }) : t(73, 57, tit, { s: 36, b: true, ls: 1 });
      return svg(W, H, o + t(W / 2, H / 2, "disponível no 2º turno (compara com o 1º turno guardado)", { s: v ? 15 : 22, c: C.apagado, a: "middle", max: W - 60 }));
    }
    var cont = {}, ref = {};
    vr.lista.forEach(function (x) { cont[x.para.numero] = (cont[x.para.numero] || 0) + 1; ref[x.para.numero] = x.para; });
    var resumo = Object.keys(cont).map(function (n) { return cont[n] + " para " + nomeCurto(ref[n]); }).join(" · ");
    var sub = "Presidente · quem liderava no 1º turno × quem lidera agora · " + vr.lista.length + (vr.lista.length === 1 ? " estado mudou" : " estados mudaram");
    var lst = vr.lista.slice().sort(function (a, b) { return DEP_UF[a.k].localeCompare(DEP_UF[b.k], "pt-BR"); });
    if (!v) {
      o = t(73, 57, tit, { s: 36, b: true, ls: 1 }) + t(73, 85, sub, { s: 16, c: C.apagado, max: 660 }) + seloH(W, seloDe(vr.f2));
      o += mapaViradas(vr, 40, 112, 0.86);
      o += t(650, 132, resumo ? "VIRARAM " + resumo.toUpperCase() : "NENHUM ESTADO VIROU", { s: 16, b: true, c: "#c9d6e6", ls: 1, max: 557 });
      lst.slice(0, 12).forEach(function (x, i) {
        var y = 160 + i * 42;
        o += r(650, y, 557, 36, "rgba(8,14,32,0.84)", 6) + t(664, y + 24, DEP_UF[x.k], { s: 15, b: true, max: 190 });
        o += r(860, y + 10, 12, 16, cor(x.de), 2) + t(878, y + 24, nomeCurto(x.de), { s: 13, c: "#c9d6e6", max: 110 });
        o += t(990, y + 24, "→", { s: 18, b: true, c: C.apagado, a: "middle" });
        o += r(1004, y + 10, 12, 16, cor(x.para), 2) + t(1022, y + 24, nomeCurto(x.para), { s: 13, b: true, max: 110 });
        o += t(1196, y + 24, pct(x.para.pct), { s: 15, b: true, a: "end" });
      });
      if (lst.length > 12) o += t(650, 680, "+ " + (lst.length - 12) + " estados (contorno branco no mapa)", { s: 13, c: C.apagado });
      o += '<rect x="73" y="660" width="14" height="14" fill="#2b3a55" stroke="#fff" stroke-width="2"/>' + t(94, 672, "contorno branco = virou · cor apagada = mesmo líder do 1º turno", { s: 12, c: C.apagado });
      return svg(W, H, o + t(73, 708, "Fonte: TSE — Presidente por estado, 1º turno (final) e 2º turno" + (vr.f2.br && vr.f2.br.andamento === "f" ? "" : " (parcial)"), { s: 11, c: C.apagado2 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 28, b: true, ls: 1, max: 450 }) + t(53, 106, vr.lista.length + " estados mudaram de líder do 1º para o 2º turno", { s: 13, c: C.apagado, max: 450 }) + seloV(W, seloDe(vr.f2));
    o += mapaViradas(vr, 50, 160, 0.72);
    lst.slice(0, 9).forEach(function (x, i) {
      var y = 640 + i * 32;
      o += r(35, y, 470, 28, "rgba(8,14,32,0.84)", 4) + t(47, y + 19, DEP_UF[x.k], { s: 13, b: true, max: 160 });
      o += r(220, y + 7, 10, 14, cor(x.de), 2) + t(236, y + 19, nomeCurto(x.de), { s: 12, c: "#c9d6e6", max: 90 }) + t(340, y + 19, "→", { s: 14, c: C.apagado, a: "middle" });
      o += r(352, y + 7, 10, 14, cor(x.para), 2) + t(368, y + 19, nomeCurto(x.para), { s: 12, b: true, max: 90 }) + t(495, y + 19, pct(x.para.pct), { s: 13, b: true, a: "end" });
    });
    return svg(W, H, o + t(35, 950, "Fonte: TSE — 1º turno × 2º turno", { s: 10, c: C.apagado2 }));
  }
  G["viradas-h"] = function () { return telaViradas(false); };
  G["viradas-v"] = function () { return telaViradas(true); };

  // ---- MARGEM MAIS APERTADA (Presidente, por estado) ------------------------
  function margens() {
    var f = fontePres(false);
    return Object.keys(DEP_UF).map(function (k) {
      var x = f.uf(k), cs = x ? candidatos(x).filter(function (c) { return c.votos > 0; }) : [];
      if (cs.length < 2) return null;
      return { k: k, c1: cs[0], c2: cs[1], dpp: cs[0].pct - cs[1].pct, dv: cs[0].votos - cs[1].votos, urnas: x.secoes ? x.secoes.pct : null };
    }).filter(Boolean).sort(function (a, b) { return a.dpp - b.dpp; });
  }
  function telaMargem(v) {
    var f = fontePres(false), ls = margens(), b = f.br, cs = b ? candidatos(b) : [], o;
    var bra = cs.length > 1 ? (cs[0].pct - cs[1].pct) : null;
    var n = v ? 12 : 10, top = ls.slice(0, n), max = top.length ? Math.max(1, top[top.length - 1].dpp) : 1;
    var sub = "Presidente · diferença entre 1º e 2º colocados por estado · " + turnoTxt(f) + (bra != null ? " · Brasil: " + Number(bra).toFixed(2).replace(".", ",") + " p.p." : "");
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, "DISPUTA MAIS APERTADA", { s: 36, b: true, ls: 1 }) + t(73, 85, sub, { s: 16, c: C.apagado, max: 660 }) + seloH(W, seloDe(f));
      if (!top.length) return svg(W, H, o + t(640, 380, "aguardando os boletins dos estados", { s: 22, c: C.apagado, a: "middle" }));
      top.forEach(function (m, i) {
        var y = 112 + i * 56;
        o += r(73, y, 1134, 50, "rgba(8,14,32,0.84)", 6) + t(100, y + 33, (i + 1) + "º", { s: 18, b: true, c: C.apagado });
        o += t(150, y + 33, DEP_UF[m.k], { s: 20, b: true, max: 260 });
        o += r(430, y + 12, 6, 26, cor(m.c1), 2) + t(446, y + 24, nomeCurto(m.c1) + " " + pct(m.c1.pct), { s: 14, b: true, max: 210 }) + t(446, y + 42, "× " + nomeCurto(m.c2) + " " + pct(m.c2.pct), { s: 12, c: C.apagado, max: 210 });
        o += barraFina(680, y + 21, 300, m.dpp / max, cor(m.c1));
        o += t(1120, y + 31, Number(m.dpp).toFixed(2).replace(".", ",") + " p.p.", { s: 22, b: true, a: "end" });
        o += t(1196, y + 22, inteiro(m.dv), { s: 12, c: "#c9d6e6", a: "end" }) + t(1196, y + 38, "votos", { s: 11, c: C.apagado, a: "end" });
      });
      return svg(W, H, o + t(73, 708, "Fonte: TSE — boletins de Presidente dos estados · urnas apuradas em cada estado podem diferir", { s: 11, c: C.apagado2 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "MAIS APERTADOS", { s: 30, b: true, ls: 1 }) + t(53, 106, "Presidente · diferença por estado", { s: 14, c: C.apagado }) + seloV(W2, seloDe(f));
    top.forEach(function (m, i) {
      var y = 166 + i * 62;
      o += r(35, y, 470, 56, "rgba(8,14,32,0.84)", 6) + r(35, y, 6, 56, cor(m.c1), 3);
      o += t(52, y + 24, DEP_UF[m.k], { s: 17, b: true, max: 260 }) + t(52, y + 45, nomeCurto(m.c1) + " à frente · " + inteiro(m.dv) + " votos", { s: 12, c: C.apagado, max: 300 });
      o += t(493, y + 36, Number(m.dpp).toFixed(2).replace(".", ",") + " p.p.", { s: 22, b: true, a: "end" });
    });
    return svg(W2, H2, o + t(35, 950, "Fonte: TSE — Presidente por estado", { s: 10, c: C.apagado2 }));
  }
  G["margem-h"] = function () { return telaMargem(false); };
  G["margem-v"] = function () { return telaMargem(true); };

  // ---- GANHO DE VOTOS DO 1o PARA O 2o TURNO (Presidente) --------------------
  function ganhos() {
    var f1 = fontePres(true), f2 = fontePres(false);
    if (!f1.guardado || !f2.br) return null;
    var fin = candidatos(f2.br).slice(0, 2); if (fin.length < 2) return null;
    function votosDe(cs, n) { for (var i = 0; i < cs.length; i++) if (String(cs[i].numero) === String(n)) return +cs[i].votos || 0; return 0; }
    var br = fin.map(function (c) { var v1 = votosDe(candidatos(f1.br), c.numero), v2 = +c.votos || 0; return { c: c, v1: v1, v2: v2, g: v2 - v1 }; });
    var regs = ["Norte", "Nordeste", "Centro-Oeste", "Sudeste", "Sul"].map(function (nome) {
      var a1 = agregar(f1, ufsDaRegiao(nome)), a2 = agregar(f2, ufsDaRegiao(nome));
      return { nome: nome, it: fin.map(function (c) { var v1 = votosDe(a1.cs, c.numero), v2 = votosDe(a2.cs, c.numero); return { c: c, v1: v1, v2: v2, g: v2 - v1 }; }) };
    });
    return { br: br, regs: regs, f2: f2 };
  }
  function sinalVotos(g) { return (g > 0 ? "+" : g < 0 ? "−" : "") + inteiro(Math.abs(g)); }
  function telaGanho(v) {
    var gn = ganhos(), W = v ? 540 : 1280, H = v ? 960 : 720, o;
    var tit = "GANHO DE VOTOS: 1º → 2º TURNO";
    if (!gn) {
      o = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, "GANHO DE VOTOS", { s: 28, b: true, ls: 1 }) : t(73, 57, tit, { s: 36, b: true, ls: 1 });
      return svg(W, H, o + t(W / 2, H / 2, "disponível no 2º turno (compara com o 1º turno guardado)", { s: v ? 15 : 22, c: C.apagado, a: "middle", max: W - 60 }));
    }
    var pU = gn.f2.br.secoes ? gn.f2.br.secoes.pct : 0, parcial = !(gn.f2.br.andamento === "f"), maxG = 1;
    if (!(pU >= 100)) {
      o = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, "GANHO DE VOTOS", { s: 28, b: true, ls: 1 }) + seloV(W, seloDe(gn.f2)) : t(73, 57, tit, { s: 34, b: true, ls: 1, max: 667 }) + seloH(W, seloDe(gn.f2));
      return svg(W, H, o + t(W / 2, H / 2 - 12, "aguardando o fim da apuração do 2º turno", { s: v ? 18 : 26, b: true, c: "#c9d6e6", a: "middle" }) +
        t(W / 2, H / 2 + 20, "urnas apuradas: " + pct(pU) + " — antes de 100% a comparação com o 1º turno engana", { s: v ? 12 : 16, c: C.apagado, a: "middle", max: W - 60 }));
    }
    gn.regs.forEach(function (rg) { rg.it.forEach(function (x) { maxG = Math.max(maxG, Math.abs(x.g)); }); });
    var sub = "Presidente · votos no 2º turno menos votos no 1º turno" + (parcial ? " · 2º turno PARCIAL (urnas " + pct(gn.f2.br.secoes.pct) + "): o ganho cresce até o fim" : "");
    if (!v) {
      o = t(73, 57, tit, { s: 34, b: true, ls: 1, max: 667 }) + t(73, 85, sub, { s: 15, c: C.apagado, max: 660 }) + seloH(W, seloDe(gn.f2));
      gn.br.forEach(function (x, i) {
        var X = 73 + i * 575, cc = cor(x.c);
        o += r(X, 106, 559, 196, "rgba(8,14,32,0.84)", 10) + r(X, 106, 559, 7, cc, 4);
        o += fotoOuSilhueta(urlFotoPres(x.c, gn.f2.eleicao), X + 18, 126, 120, 160);
        o += t(X + 156, 150, x.c.nome, { s: 22, b: true, max: 390 }) + t(X + 156, 172, x.c.partido, { s: 14, c: C.apagado });
        o += t(X + 156, 212, "1º turno  " + inteiro(x.v1), { s: 15, c: "#c9d6e6" }) + t(X + 156, 236, "2º turno  " + inteiro(x.v2), { s: 15, c: "#c9d6e6" });
        o += t(X + 545, 282, sinalVotos(x.g), { s: 34, b: true, c: x.g >= 0 ? "#69db7c" : "#ff8787", a: "end" });
        o += t(X + 545, 296, "votos " + (x.v1 ? "(" + (x.g >= 0 ? "+" : "−") + pct1(Math.abs(100 * x.g / x.v1)) + ")" : ""), { s: 11, c: C.apagado, a: "end" });
      });
      o += t(73, 336, "POR REGIÃO", { s: 15, b: true, c: "#c9d6e6", ls: 1 });
      gn.regs.forEach(function (rg, i) {
        var y = 352 + i * 66;
        o += r(73, y, 1134, 58, "rgba(8,14,32,0.84)", 6) + t(92, y + 36, REG_NOME[rg.nome], { s: 18, b: true, ls: 1 });
        rg.it.forEach(function (x, j) {
          var X = 300 + j * 455, w = 260 * Math.abs(x.g) / maxG;
          o += t(X, y + 22, nomeCurto(x.c), { s: 12, c: C.apagado, max: 160 });
          o += r(X, y + 30, 260, 14, "rgba(255,255,255,0.08)", 4) + (w > 0 ? r(X, y + 30, Math.max(4, w), 14, x.g >= 0 ? cor(x.c) : "#ff8787", 4) : "");
          o += t(X + 420, y + 43, sinalVotos(x.g), { s: 18, b: true, c: x.g >= 0 ? C.texto : "#ff8787", a: "end" });
        });
      });
      return svg(W, H, o + t(73, 708, "Fonte: TSE — Presidente, 1º turno (final) e 2º turno · regiões = soma dos estados (sem exterior). Não mostra de quem veio o voto.", { s: 11, c: C.apagado2, max: 1134 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "GANHO DE VOTOS", { s: 30, b: true, ls: 1 }) + t(53, 106, "Presidente · 1º → 2º turno" + (parcial ? " · parcial" : ""), { s: 14, c: C.apagado }) + seloV(W, seloDe(gn.f2));
    gn.br.forEach(function (x, i) {
      var y = 166 + i * 150, cc = cor(x.c);
      o += r(35, y, 470, 140, "rgba(8,14,32,0.84)", 8) + r(35, y, 7, 140, cc, 3);
      o += fotoOuSilhueta(urlFotoPres(x.c, gn.f2.eleicao), 52, y + 12, 87, 116);
      o += t(152, y + 34, x.c.nome, { s: 18, b: true, max: 340 }) + t(152, y + 60, "1º " + inteiro(x.v1) + "  ·  2º " + inteiro(x.v2), { s: 13, c: "#c9d6e6", max: 340 });
      o += t(493, y + 116, sinalVotos(x.g), { s: 30, b: true, c: x.g >= 0 ? "#69db7c" : "#ff8787", a: "end" });
    });
    gn.regs.forEach(function (rg, i) {
      var y = 480 + i * 92;
      o += r(35, y, 470, 84, "rgba(8,14,32,0.84)", 6) + t(52, y + 26, REG_NOME[rg.nome], { s: 16, b: true, ls: 1 });
      rg.it.forEach(function (x, j) { o += r(52, y + 40 + j * 22, 8, 14, cor(x.c), 2) + t(68, y + 52 + j * 22, nomeCurto(x.c), { s: 13, c: "#c9d6e6", max: 200 }) + t(493, y + 52 + j * 22, sinalVotos(x.g), { s: 15, b: true, c: x.g >= 0 ? C.texto : "#ff8787", a: "end" }); });
    });
    return svg(W, H, o + t(35, 950, "Fonte: TSE — 1º turno (final) × 2º turno", { s: 10, c: C.apagado2 }));
  }
  G["ganho-h"] = function () { return telaGanho(false); };
  G["ganho-v"] = function () { return telaGanho(true); };

  // ---- ABSTENCAO 1o x 2o TURNO POR ESTADO ----------------------------------
  var FAIXAS_ABST = [[-99, -2, "#1f9e74", "caiu mais de 2 p.p."], [-2, -0.5, "#63c5a0", "caiu até 2 p.p."], [-0.5, 0.5, "#6b7688", "estável (±0,5)"],
    [0.5, 2, "#f0a35b", "subiu até 2 p.p."], [2, 99, "#e8590c", "subiu mais de 2 p.p."]];
  function difAbst() {
    var f1 = fontePres(true), f2 = fontePres(false);
    if (!f1.guardado) return null;
    var ls = Object.keys(DEP_UF).map(function (k) {
      var a = f1.uf(k), b = f2.uf(k), p1 = a && a.eleitorado ? a.eleitorado.pct_abstencao : null, p2 = b && b.eleitorado ? b.eleitorado.pct_abstencao : null;
      if (p1 == null || p2 == null || !(b.secoes && b.secoes.pct > 0)) return { k: k, d: null };
      return { k: k, p1: +p1, p2: +p2, d: p2 - p1 };
    });
    var b1 = f1.br && f1.br.eleitorado ? f1.br.eleitorado.pct_abstencao : null, b2 = f2.br && f2.br.eleitorado ? f2.br.eleitorado.pct_abstencao : null;
    return { ls: ls, b1: b1, b2: b2, f2: f2 };
  }
  function corDifAbst(d) { if (d == null) return null; for (var i = 0; i < FAIXAS_ABST.length; i++) if (d >= FAIXAS_ABST[i][0] && d < FAIXAS_ABST[i][1]) return FAIXAS_ABST[i][2]; return "#6b7688"; }
  function ppS(d) { return (d > 0 ? "+" : d < 0 ? "−" : "") + Number(Math.abs(d)).toFixed(2).replace(".", ",") + " p.p."; }
  function telaAbstUf(v) {
    var da = difAbst(), W = v ? 540 : 1280, H = v ? 960 : 720, o, tit = "ABSTENÇÃO: 1º × 2º TURNO";
    if (!da) {
      o = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, "ABSTENÇÃO 1º × 2º", { s: 28, b: true, ls: 1 }) : t(73, 57, tit, { s: 36, b: true, ls: 1 });
      return svg(W, H, o + t(W / 2, H / 2, "disponível no 2º turno (compara com o 1º turno guardado)", { s: v ? 15 : 22, c: C.apagado, a: "middle", max: W - 60 }));
    }
    var ok = da.ls.filter(function (x) { return x.d != null; }), sob = ok.slice().sort(function (a, b) { return b.d - a.d; }), des = ok.slice().sort(function (a, b) { return a.d - b.d; });
    var corM = function (k) { var x = da.ls.filter(function (y) { return y.k === k; })[0]; return x ? corDifAbst(x.d) : null; };
    var sub = "variação da abstenção por estado (pontos percentuais)" + (da.b1 != null && da.b2 != null ? " · Brasil: " + pct(da.b1) + " → " + pct(da.b2) : "");
    if (!v) {
      o = t(73, 57, tit, { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, sub, { s: 16, c: C.apagado, max: 660 }) + seloH(W, seloDe(da.f2));
      o += mapaCor(40, 112, 0.84, corM, { rotulos: true, fonte: 12, apagado: "#1c2a40" });
      FAIXAS_ABST.forEach(function (fx, i) { o += r(60, 600 + i * 20, 14, 14, fx[2], 2) + t(82, 612 + i * 20, fx[3], { s: 12, c: C.apagado }); });
      [["MAIS SUBIU", sob.filter(function (x) { return x.d > 0; }).slice(0, 5)], ["MAIS CAIU", des.filter(function (x) { return x.d < 0; }).slice(0, 5)]].forEach(function (bl, j) {
        var y0 = 120 + j * 290;
        o += t(650, y0, bl[0], { s: 16, b: true, c: "#c9d6e6", ls: 1 });
        if (!bl[1].length) o += t(650, y0 + 34, "nenhum estado", { s: 14, c: C.apagado });
        bl[1].forEach(function (x, i) {
          var y = y0 + 14 + i * 48;
          o += r(650, y, 557, 42, "rgba(8,14,32,0.84)", 6) + r(650, y, 7, 42, corDifAbst(x.d), 3);
          o += t(670, y + 27, DEP_UF[x.k], { s: 16, b: true, max: 230 }) + t(1000, y + 27, pct(x.p1) + " → " + pct(x.p2), { s: 13, c: C.apagado, a: "end" });
          o += t(1195, y + 28, ppS(x.d), { s: 19, b: true, a: "end" });
        });
      });
      return svg(W, H, o + t(73, 708, "Fonte: TSE — abstenção sobre o eleitorado; 1º turno final × 2º turno" + (da.f2.br && da.f2.br.andamento === "f" ? "" : " (parcial: só seções já totalizadas)"), { s: 11, c: C.apagado2 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "ABSTENÇÃO 1º × 2º", { s: 28, b: true, ls: 1 }) + t(53, 106, da.b1 != null && da.b2 != null ? "Brasil: " + pct(da.b1) + " → " + pct(da.b2) : "por estado", { s: 14, c: C.apagado }) + seloV(W, seloDe(da.f2));
    o += mapaCor(70, 165, 0.65, corM, { rotulos: true, fonte: 10, apagado: "#1c2a40" });
    FAIXAS_ABST.forEach(function (fx, i) { o += r(40 + (i % 3) * 160, 600 + Math.floor(i / 3) * 20, 12, 12, fx[2], 2) + t(58 + (i % 3) * 160, 610 + Math.floor(i / 3) * 20, fx[3], { s: 10, c: C.apagado }); });
    [["SUBIU", sob.filter(function (x) { return x.d > 0; }).slice(0, 4)], ["CAIU", des.filter(function (x) { return x.d < 0; }).slice(0, 4)]].forEach(function (bl, j) {
      var y0 = 670 + j * 140;
      o += t(35, y0, bl[0], { s: 13, b: true, c: "#c9d6e6", ls: 1 });
      bl[1].forEach(function (x, i) { var y = y0 + 8 + i * 30; o += r(35, y, 470, 26, "rgba(8,14,32,0.84)", 4) + r(35, y, 6, 26, corDifAbst(x.d), 2) + t(50, y + 18, DEP_UF[x.k], { s: 13, b: true, max: 250 }) + t(495, y + 18, ppS(x.d), { s: 14, b: true, a: "end" }); });
    });
    return svg(W, H, o + t(35, 950, "Fonte: TSE — abstenção 1º × 2º turno", { s: 10, c: C.apagado2 }));
  }
  G["abstuf-h"] = function () { return telaAbstUf(false); };
  G["abstuf-v"] = function () { return telaAbstUf(true); };

  // ---- 2o TURNO: 2022 x 2026 (Presidente, % por partido em cada estado) ------
  // 2022: boletim do 2o turno de 2022 que o TSE mantem publicado (ESTADOS.bat,
  // ref2022_2t). 2026: ao vivo. Compara o PARTIDO (os candidatos podem ser
  // outros); partido que nao disputou o 2o turno de 2022 aparece com "—".
  function ref22() { var x = (window.GCTSE_ESTADOS || {}).ref2022_2t; return x && x.br ? x : null; }
  function comp22(x26, r22, sgs) {
    var cs = x26 ? candidatos(x26) : [];
    return sgs.map(function (sg) {
      var c = cs.filter(function (k) { return String(k.partido).toUpperCase() === sg; })[0];
      var a = r22 && r22[sg] != null ? +r22[sg] : null, b = c && c.votos > 0 ? +c.pct : null;
      return { sg: sg, c: c, p22: a, p26: b, d: a != null && b != null ? b - a : null };
    });
  }
  function difPP(d, curto) {
    if (d == null) return "";
    if (Math.abs(d) < 0.05) return "=";
    if (curto) return (d > 0 ? "▲ +" : "▼ −") + Number(Math.abs(d)).toFixed(1).replace(".", ",");
    return (d > 0 ? "▲ +" : d < 0 ? "▼ −" : "") + Number(Math.abs(d)).toFixed(1).replace(".", ",") + " p.p.";
  }
  function telaT22(v) {
    var f = fontePres(false), R = ref22(), W = v ? 540 : 1280, H = v ? 960 : 720, o, tit = "2º TURNO: 2022 × 2026";
    var cab = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, tit, { s: 28, b: true, ls: 1, max: 450 }) + t(53, 106, "Presidente · % por partido", { s: 14, c: C.apagado }) + seloV(W, seloDe(f))
                : t(73, 57, tit, { s: 36, b: true, ls: 1 }) + t(73, 85, "Presidente · % dos votos válidos de cada partido no 2º turno · " + subtitulo(), { s: 16, c: C.apagado, max: 660 }) + seloH(W, seloDe(f));
    if (f.turno !== 2) return svg(W, H, cab + t(W / 2, H / 2, "disponível no 2º turno", { s: v ? 18 : 24, c: C.apagado, a: "middle" }));
    if (!R) return svg(W, H, cab + t(W / 2, H / 2, "aguardando o 2º turno de 2022 do TSE (ESTADOS.bat)", { s: v ? 16 : 22, c: C.apagado, a: "middle", max: W - 60 }));
    var cs = f.br ? candidatos(f.br) : [], sgs = cs.slice(0, 2).map(function (c) { return String(c.partido).toUpperCase(); });
    var brc = comp22(f.br, R.br, sgs), ufs = Object.keys(DEP_UF).sort(function (a, b) { return DEP_UF[a].localeCompare(DEP_UF[b], "pt-BR"); });
    function celula(x, y, it, fs, larg) {
      var cc = it.c ? cor(it.c) : C.outros, oo = r(x, y - fs + 1, 5, fs + 2, cc, 2);
      var n1 = function (v0) { return v0 != null ? Number(v0).toFixed(1).replace(".", ",") : "—"; };
      oo += t(x + 10, y, n1(it.p22) + " → " + n1(it.p26), { s: fs, b: true, max: larg * 0.6 });
      if (it.d != null) oo += t(x + larg, y, difPP(it.d, true), { s: fs - 1, b: true, a: "end", c: Math.abs(it.d) < 0.05 ? C.apagado : it.d > 0 ? "#69db7c" : "#ff8787" });
      return oo;
    }
    if (!v) {
      o = cab + r(73, 100, 1134, 60, "rgba(8,14,32,0.84)", 8) + t(93, 137, "BRASIL", { s: 18, b: true, ls: 2 });
      brc.forEach(function (it, i) {
        var x = 300 + i * 450, nm = it.c ? nomeCurto(it.c) + " (" + it.sg + ")" : it.sg, n22 = R.br["_nome_" + it.sg];
        o += r(x, 112, 6, 36, it.c ? cor(it.c) : C.outros, 2) + t(x + 14, 128, nm, { s: 14, b: true, max: 250 }) + t(x + 14, 148, "2022: " + (n22 || "—"), { s: 11, c: C.apagado, max: 250 });
        o += t(x + 420, 128, (it.p22 != null ? pct1(it.p22) : "—") + " → " + (it.p26 != null ? pct1(it.p26) : "—"), { s: 16, b: true, a: "end" }) +
          t(x + 420, 150, difPP(it.d), { s: 14, b: true, a: "end", c: it.d >= 0 ? "#69db7c" : "#ff8787" });
      });
      [0, 1].forEach(function (col) {
        var x = 73 + col * 575;
        o += t(x + 6, 186, "ESTADO", { s: 10, b: true, c: C.apagado, ls: 1 });
        sgs.forEach(function (sg, i) { o += t(x + 150 + i * 205, 186, sg + "  2022 → 2026 (%)", { s: 10, b: true, c: C.apagado, ls: 1 }); });
      });
      ufs.forEach(function (k, i) {
        var col = i < 14 ? 0 : 1, li = col ? i - 14 : i, x = 73 + col * 575, y = 212 + li * 34;
        o += r(x, y - 20, 559, 30, li % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)", 3) + t(x + 6, y, DEP_UF[k], { s: 12, b: true, max: 136 });
        comp22(f.uf(k), (R.ufs || {})[k], sgs).forEach(function (it, j) { o += celula(x + 150 + j * 205, y, it, 13, 195); });
      });
      return svg(W, H, o + t(73, 706, "Fonte: TSE — 2º turno de 2022 (eleição " + R.eleicao + ") e 2026 ao vivo. Compara o partido, não o candidato.", { s: 11, c: C.apagado2, max: 1134 }));
    }
    o = cab + r(35, 160, 470, 62, "rgba(8,14,32,0.84)", 8) + t(50, 182, "BRASIL", { s: 13, b: true, ls: 2 });
    brc.forEach(function (it, i) { o += celula(50 + i * 230, 210, it, 13, 215); });
    o += t(41, 246, "UF", { s: 10, b: true, c: C.apagado });
    sgs.forEach(function (sg, i) { o += t(80 + i * 215, 246, sg + " 2022 → 2026 (%)", { s: 10, b: true, c: C.apagado }); });
    ufs.forEach(function (k, i) {
      var y = 268 + i * 24.5;
      o += r(35, y - 16, 470, 22, i % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)", 3) + t(41, y, k.toUpperCase(), { s: 11, b: true });
      comp22(f.uf(k), (R.ufs || {})[k], sgs).forEach(function (it, j) { o += celula(78 + j * 215, y, it, 11, 205); });
    });
    return svg(W, H, o + t(35, 950, "Fonte: TSE — 2º turno 2022 e 2026 · compara o partido", { s: 10, c: C.apagado2 }));
  }
  G["turno22-h"] = function () { return telaT22(false); };
  G["turno22-v"] = function () { return telaT22(true); };

  // ---- PRESIDENTE NAS CAPITAIS ----------------------------------------------
  // Boletim de cada capital (municipio do TSE), lido pelo GRAFICOS.bat.
  // No 2o turno, "VIROU" = quem lidera agora nao liderava no 1o turno.
  function capitais() {
    var cp = D().capitais || {}, c1 = D().capitais_1t || {};
    return Object.keys(DEP_UF).filter(function (k) { return cp[k] && cp[k].tem; }).map(function (k) {
      var x = cp[k], cs = candidatos(x).filter(function (c) { return c.votos > 0; }), l1 = c1[k] ? candidatos(c1[k])[0] : null;
      return { k: k, x: x, cs: cs, lider: cs[0] || null, l1: l1, virou: !!(l1 && cs[0] && String(l1.numero) !== String(cs[0].numero)) };
    }).sort(function (a, b) { return DEP_UF[a.k].localeCompare(DEP_UF[b.k], "pt-BR"); });
  }
  function placarLideres(lista, quem) {
    var n = {}; lista.forEach(function (l) { if (l.lider) n[l.lider.numero] = (n[l.lider.numero] || 0) + 1; });
    var cs = br() ? candidatos(br()).slice(0, 2) : [];
    return cs.map(function (c) { return { c: c, n: n[c.numero] || 0 }; });
  }
  function nomeCap(x) { return String(x.nome || "").toUpperCase(); }
  function telaCapitais(v) {
    var f = fontePres(false), ls = capitais(), W = v ? 540 : 1280, H = v ? 960 : 720, o, pl = placarLideres(ls);
    var sub = "Presidente · " + turnoTxt(f) + " · " + ls.length + (ls.length === 1 ? " capital" : " capitais") + " com boletim";
    if (!v) {
      o = t(73, 57, "PRESIDENTE NAS CAPITAIS", { s: 36, b: true, ls: 1 }) + t(73, 85, sub, { s: 17, c: C.apagado, max: 660 }) + seloH(W, seloDe(f));
      if (!ls.length) return svg(W, H, o + t(640, 380, "aguardando os boletins das capitais (GRAFICOS.bat)", { s: 22, c: C.apagado, a: "middle" }));
      o += r(73, 100, 1134, 44, "rgba(8,14,32,0.84)", 8);
      pl.forEach(function (p, i) { o += r(93 + i * 400, 111, 6, 22, cor(p.c), 2) + t(107 + i * 400, 130, nomeCurto(p.c) + " lidera em " + p.n + (p.n === 1 ? " capital" : " capitais"), { s: 17, b: true, max: 380 }); });
      ls.forEach(function (l, i) {
        var col = i < 14 ? 0 : 1, li = col ? i - 14 : i, x = 73 + col * 575, y = 178 + li * 37.5, c = l.lider, c2 = l.cs[1];
        o += r(x, y - 23, 559, 33, li % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)", 3);
        o += t(x + 8, y - 2, nomeCap(l.x), { s: 13, b: true, max: 170 }) + t(x + 8, y + 8, DEP_UF[l.k] + (l.x.secoes ? " · urnas " + pct1(l.x.secoes.pct) : ""), { s: 8, c: C.apagado, max: 170 });
        if (c) o += r(x + 188, y - 16, 5, 20, cor(c), 2) + t(x + 200, y, nomeCurto(c) + " " + pct(c.pct), { s: 14, b: true, max: 205 });
        if (c2) o += t(x + 420, y, nomeCurto(c2).split(" ")[0] + " " + pct(c2.pct), { s: 12, c: C.apagado, max: 100 });
        if (l.virou) o += r(x + 497, y - 14, 56, 18, "#ffffff", 3) + t(x + 525, y, "VIROU", { s: 10, b: true, c: "#0b1220", a: "middle" });
      });
      return svg(W, H, o + t(73, 708, "Fonte: TSE — boletim de Presidente de cada capital" + (f.turno === 2 ? " · VIROU = outro candidato liderava no 1º turno" : ""), { s: 11, c: C.apagado2, max: 1134 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "NAS CAPITAIS", { s: 30, b: true, ls: 1 }) + t(53, 106, "Presidente · " + turnoTxt(f), { s: 14, c: C.apagado }) + seloV(W, seloDe(f));
    if (!ls.length) return svg(W, H, o + t(270, 480, "aguardando as capitais", { s: 18, c: C.apagado, a: "middle" }));
    pl.forEach(function (p, i) { o += r(40 + i * 235, 166, 5, 18, cor(p.c), 2) + t(52 + i * 235, 181, nomeCurto(p.c) + ": " + p.n, { s: 15, b: true, max: 215 }); });
    ls.forEach(function (l, i) {
      var y = 220 + i * 26.5, c = l.lider;
      o += r(35, y - 17, 470, 24, i % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)", 3);
      o += t(42, y, nomeCap(l.x) + " (" + l.k.toUpperCase() + ")", { s: 11, b: true, max: 200 });
      if (c) o += r(250, y - 11, 4, 14, cor(c), 2) + t(260, y, nomeCurto(c) + " " + pct(c.pct), { s: 12, b: true, max: 180 });
      if (l.virou) o += t(498, y, "VIROU", { s: 10, b: true, a: "end" });
    });
    return svg(W, H, o + t(35, 950, "Fonte: TSE — Presidente em cada capital", { s: 10, c: C.apagado2 }));
  }
  G["capitais-h"] = function () { return telaCapitais(false); };
  G["capitais-v"] = function () { return telaCapitais(true); };

  // ---- BRASILEIROS NO EXTERIOR ----------------------------------------------
  // Total: boletim "zz" do TSE. Por pais: soma dos boletins das cidades do
  // exterior (TSE), agrupadas pelo pais da tabela web\exterior-paises.js.
  function chaveCidade(n) { return String(n || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim(); }
  function paisDe(x) { var P = window.GCTSE_EXTERIOR_PAISES || {}; return x.pais ? chaveCidade(x.pais) : (P[chaveCidade(x.nome)] || ""); }
  function exteriorSemPais() { return comoLista(D().exterior).filter(function (x) { return !paisDe(x); }).map(function (x) { return x.nome; }); }
  function agruparExterior(porPais) {
    var g = {};
    comoLista(D().exterior).forEach(function (x) {
      var k = porPais ? (paisDe(x) || "OUTROS PAÍSES") : String(x.nome || "").toUpperCase();
      var a = g[k] = g[k] || { nome: k, validos: 0, cs: {}, cidades: 0, aptos: 0, comp: 0 };
      a.cidades++; a.validos += +(x.votos || {}).validos || 0; a.aptos += +(x.eleitorado || {}).aptos || 0; a.comp += +(x.eleitorado || {}).comparecimento || 0;
      candidatos(x).forEach(function (c) { var s = a.cs[c.numero] = a.cs[c.numero] || { nome: c.nome, numero: c.numero, partido: c.partido, votos: 0 }; s.votos += +c.votos || 0; });
    });
    return Object.keys(g).map(function (k) {
      var a = g[k], cs = Object.keys(a.cs).map(function (n) { var c = a.cs[n]; c.pct = a.validos ? 100 * c.votos / a.validos : 0; return c; }).sort(function (p, q) { return q.votos - p.votos; });
      a.lista = cs; return a;
    }).filter(function (a) { return a.validos > 0; }).sort(function (p, q) { return q.validos - p.validos; });
  }
  function caixaExteriorTotal(x, y, w, h, k2) {
    var z = D().exterior_total, f = fontePres(false), o = r(x, y, w, h, "rgba(8,14,32,0.84)", 10);
    o += t(x + 20, y + 32 * k2, "TOTAL NO EXTERIOR", { s: Math.round(16 * k2), b: true, c: "#c9d6e6", ls: 2 });
    if (!z || !z.tem) return o + t(x + w / 2, y + h / 2, "aguardando o boletim do exterior", { s: 16, c: C.apagado, a: "middle" });
    var cs = candidatos(z).slice(0, f.turno === 2 ? 2 : 3);
    cs.forEach(function (c, i) {
      var yy = y + (62 + i * 64) * k2;
      o += r(x + 20, yy, 6, 46 * k2, cor(c), 2) + t(x + 36, yy + 20 * k2, c.nome, { s: Math.round(18 * k2), b: true, max: w - 190 }) +
        t(x + 36, yy + 42 * k2, inteiro(c.votos) + " votos", { s: Math.round(12 * k2), c: C.apagado }) + t(x + w - 20, yy + 36 * k2, pct(c.pct), { s: Math.round(30 * k2), b: true, a: "end" });
    });
    var e = z.eleitorado || {}, yb = y + h - 58 * k2, t1 = ((D().turno1 || {}).ufs || {}).zz;
    // barra dos dois primeiros e, no 2o turno, como foi o 1o turno no exterior
    var yBar = y + (62 + cs.length * 64 + 8) * k2, tot = cs.reduce(function (a0, c) { return a0 + (+c.pct || 0); }, 0) || 1, xx = x + 20;
    cs.forEach(function (c) { var wv = (w - 40) * (+c.pct || 0) / tot; o += r(xx, yBar, Math.max(0, wv - 2), 14 * k2, cor(c), 2); xx += wv; });
    if (f.turno === 2 && t1 && t1.tem && h > 400) {
      var c1s = candidatos(t1).slice(0, 4), y1 = yBar + 56 * k2;
      o += t(x + 20, y1, "1º TURNO NO EXTERIOR", { s: Math.round(13 * k2), b: true, c: C.apagado, ls: 2 });
      c1s.forEach(function (c, i) { var yy = y1 + (26 + i * 30) * k2; o += r(x + 20, yy - 13 * k2, 5, 16 * k2, cor(c), 2) + t(x + 32, yy, c.nome, { s: Math.round(14 * k2), b: true, max: w - 160 }) + t(x + w - 20, yy, pct(c.pct), { s: Math.round(15 * k2), b: true, a: "end", c: "#c9d6e6" }); });
    }
    o += t(x + 20, yb, "comparecimento " + (e.pct_comparec != null ? pct(e.pct_comparec) : "—") + " · abstenção " + (e.pct_abstencao != null ? pct(e.pct_abstencao) : "—"), { s: Math.round(13 * k2), c: "#c9d6e6", max: w - 40 });
    o += t(x + 20, yb + 20 * k2, inteiro(e.aptos) + " eleitores aptos no exterior · urnas " + pct((z.secoes || {}).pct), { s: Math.round(12 * k2), c: C.apagado, max: w - 40 });
    if (f.turno === 2 && t1 && t1.tem && h <= 400) { var c1 = candidatos(t1)[0]; if (c1) o += t(x + 20, yb + 40 * k2, "1º turno no exterior: " + nomeCurto(c1) + " " + pct(c1.pct), { s: Math.round(12 * k2), c: C.apagado, max: w - 40 }); }
    return o;
  }
  function linhasExterior(lista, x, y, w, passo, n, fs, rotulo) {
    var o = t(x, y - passo * 0.55, rotulo, { s: fs - 2, b: true, c: C.apagado, ls: 1 });
    lista.slice(0, n).forEach(function (a, i) {
      var yy = y + i * passo, c = a.lista[0], c2 = a.lista[1];
      o += r(x - 6, yy - passo * 0.62, w + 12, passo - 4, i % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)", 3);
      o += t(x, yy, a.nome, { s: fs, b: true, max: w * 0.36 }) + t(x, yy + fs * 0.95, inteiro(a.validos) + " votos válidos" + (a.cidades > 1 ? " · " + a.cidades + " cidades" : ""), { s: fs - 5, c: C.apagado, max: w * 0.36 });
      if (c) o += r(x + w * 0.39, yy - fs * 0.8, 5, fs + 2, cor(c), 2) + t(x + w * 0.39 + 12, yy, nomeCurto(c) + " " + pct(c.pct), { s: fs, b: true, max: w * 0.36 });
      if (c2) o += t(x + w, yy, nomeCurto(c2).split(" ")[0] + " " + pct(c2.pct), { s: fs - 2, c: C.apagado, a: "end", max: w * 0.22 });
    });
    return o;
  }
  function telaExterior(v, porPais) {
    var f = fontePres(false), ls = agruparExterior(porPais), W = v ? 540 : 1280, H = v ? 960 : 720, o, nCid = +D().exterior_cidades || 0;
    var venc = {}; ls.forEach(function (a) { if (a.nome !== "OUTROS PAÍSES" && a.lista[0]) venc[a.lista[0].numero] = (venc[a.lista[0].numero] || 0) + 1; });
    var csBr = br() ? candidatos(br()).slice(0, 2) : [], nGrupos = ls.filter(function (a) { return a.nome !== "OUTROS PAÍSES"; }).length;
    var resumo = porPais && nGrupos ? csBr.map(function (c) { return nomeCurto(c) + " vence em " + (venc[c.numero] || 0); }).join(" · ") + " de " + nGrupos + " países" : "";
    var tit = porPais ? "BRASILEIROS NO EXTERIOR" : "EXTERIOR — POR CIDADE";
    var rod = "Fonte: TSE — votos do exterior (boletim ZZ e de cada cidade)" + (porPais ? "; país de cada cidade: tabela exterior-paises.js" : "") + (nCid ? " · " + comoLista(D().exterior).length + " de " + nCid + " cidades lidas" : "");
    if (!v) {
      o = t(73, 57, tit, { s: 36, b: true, ls: 1, max: 667 }) + t(73, 85, "Presidente · " + turnoTxt(f) + (resumo ? " · " + resumo : ""), { s: 16, c: C.apagado, max: 660 }) + seloH(W, seloDe(f));
      o += caixaExteriorTotal(73, 106, 440, 568, 1);
      o += r(533, 106, 674, 568, "rgba(8,14,32,0.60)", 10);
      if (!ls.length) o += t(870, 390, "aguardando os boletins das cidades", { s: 18, c: C.apagado, a: "middle" });
      else o += linhasExterior(ls, 553, 160, 634, 42.5, 12, 17, porPais ? "PAÍSES COM MAIS VOTOS" : "CIDADES COM MAIS VOTOS");
      return svg(W, H, o + t(73, 704, rod, { s: 11, c: C.apagado2, max: 1134 }));
    }
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, porPais ? "NO EXTERIOR" : "EXTERIOR: CIDADES", { s: 30, b: true, ls: 1 }) + t(53, 106, "Presidente · " + turnoTxt(f), { s: 14, c: C.apagado }) + seloV(W, seloDe(f));
    o += caixaExteriorTotal(35, 160, 470, 330, 0.95);
    if (ls.length) o += linhasExterior(ls, 45, 540, 450, 40, 10, 15, porPais ? "PAÍSES COM MAIS VOTOS" : "CIDADES COM MAIS VOTOS");
    return svg(W, H, o + t(35, 950, "Fonte: TSE" + (porPais ? " · país: tabela da emissora" : ""), { s: 10, c: C.apagado2 }));
  }
  G["exterior-h"] = function () { return telaExterior(false, true); };
  G["exterior-v"] = function () { return telaExterior(true, true); };
  G["excidades-h"] = function () { return telaExterior(false, false); };
  G["excidades-v"] = function () { return telaExterior(true, false); };

  // ---- ESTADOS DECISIVOS: os 6 maiores eleitorados, placar ao vivo ----------
  // Quais sao os 6: pelo eleitorado (aptos) que o proprio TSE publica no
  // boletim de Presidente de cada estado - nada fixo no codigo.
  function decisivos() {
    var f = fontePres(false), f1 = fontePres(true);
    return Object.keys(DEP_UF).map(function (k) { var x = f.uf(k); return { k: k, x: x, aptos: x && x.eleitorado ? +x.eleitorado.aptos || 0 : 0 }; })
      .filter(function (s) { return s.aptos > 0; }).sort(function (a, b) { return b.aptos - a.aptos; }).slice(0, 6)
      .map(function (s) {
        s.cs = candidatos(s.x).slice(0, 2); s.l1 = f1.guardado ? liderF(f1, s.k) : null; s.l2 = liderF(f, s.k);
        s.virou = !!(s.l1 && s.l2 && String(s.l1.numero) !== String(s.l2.numero));
        return s;
      });
  }
  function cartaoDecisivoV(s, x, y, w, h, aptosBr) {   // vertical: compacto, sem votos
    var o = r(x, y, w, h, "rgba(8,14,32,0.84)", 8), urn = s.x && s.x.secoes ? s.x.secoes.pct : null;
    o += t(x + 14, y + 22, DEP_UF[s.k], { s: 16, b: true, max: w - 130 }) + t(x + w - 12, y + 21, "urnas " + (urn == null ? "—" : pct(urn)), { s: 11, b: true, c: "#c9d6e6", a: "end" });
    o += t(x + 14, y + 38, inteiro(s.aptos) + " eleitores" + (aptosBr ? " · " + pct1(100 * s.aptos / aptosBr) + " do Brasil" : ""), { s: 10, c: C.apagado, max: w - 28 });
    s.cs.forEach(function (c, i) {
      var yy = y + 60 + i * 30;
      o += r(x + 14, yy - 13, 5, 26, cor(c), 2) + t(x + 26, yy, c.nome, { s: 14, b: true, max: w - 130 }) + t(x + w - 12, yy + 2, pct(c.pct), { s: 19, b: true, a: "end" });
      o += barraFina(x + 26, yy + 6, w - 120, (c.pct || 0) / 100, cor(c));
    });
    if (!s.cs.length) o += t(x + w / 2, y + 74, "aguardando o boletim", { s: 13, c: C.apagado, a: "middle" });
    if (s.l1) {
      o += t(x + 14, y + h - 8, "1º turno: " + nomeCurto(s.l1) + " liderou com " + pct(s.l1.pct), { s: 10, c: C.apagado, max: w - 100 });
      if (s.virou) o += r(x + w - 74, y + h - 21, 62, 17, "#ffffff", 3) + t(x + w - 43, y + h - 8, "VIROU", { s: 11, b: true, c: "#0b1220", a: "middle", ls: 1 });
    }
    return o;
  }
  function cartaoDecisivo(s, x, y, w, h, k2, aptosBr) {
    var o = r(x, y, w, h, "rgba(8,14,32,0.84)", 8), urn = s.x && s.x.secoes ? s.x.secoes.pct : null;
    o += t(x + 16, y + 30 * k2, DEP_UF[s.k], { s: Math.round(20 * k2), b: true, max: w - 165 });
    o += t(x + w - 14, y + 28 * k2, "urnas " + (urn == null ? "—" : pct(urn)), { s: Math.round(13 * k2), b: true, c: "#c9d6e6", a: "end" });
    o += t(x + 16, y + 50 * k2, inteiro(s.aptos) + " eleitores" + (aptosBr ? " · " + pct1(100 * s.aptos / aptosBr) + " do Brasil" : ""), { s: Math.round(12 * k2), c: C.apagado, max: w - 30 });
    var lh = (h - 96 * k2) / 2;
    s.cs.forEach(function (c, i) {
      var yy = y + 62 * k2 + i * lh;
      o += r(x + 16, yy + 4, 6, lh - 12, cor(c), 2);
      o += t(x + 32, yy + lh * 0.42, c.nome, { s: Math.round(17 * k2), b: true, max: w - 160 });
      o += t(x + w - 14, yy + lh * 0.48, pct(c.pct), { s: Math.round(26 * k2), b: true, a: "end" });
      o += barraFina(x + 32, yy + lh * 0.62, w - 48, (c.pct || 0) / 100, cor(c));
      o += t(x + 32, yy + lh * 0.62 + 24 * k2, inteiro(c.votos) + " votos", { s: Math.round(11 * k2), c: C.apagado });
    });
    if (!s.cs.length) o += t(x + w / 2, y + h / 2, "aguardando o boletim", { s: 15, c: C.apagado, a: "middle" });
    var yb = y + h - 14 * k2;
    if (s.l1) {
      o += t(x + 16, yb, "1º turno: " + nomeCurto(s.l1) + " liderou com " + pct(s.l1.pct), { s: Math.round(12 * k2), c: C.apagado, max: w - 120 });
      if (s.virou) o += r(x + w - 92, yb - 15 * k2, 78, 20 * k2, "#ffffff", 3) + t(x + w - 53, yb, "VIROU", { s: Math.round(12 * k2), b: true, c: "#0b1220", a: "middle", ls: 1 });
    }
    return o;
  }
  function telaDecisivos(v) {
    var f = fontePres(false), ls = decisivos(), b = f.br, aptosBr = b && b.eleitorado ? +b.eleitorado.aptos || 0 : 0, o;
    var soma = ls.reduce(function (a, s) { return a + s.aptos; }, 0);
    var sub = "Presidente · " + turnoTxt(f) + " · os 6 maiores eleitorados" + (aptosBr && soma ? " = " + pct1(100 * soma / aptosBr) + " dos eleitores do Brasil" : "");
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, "ESTADOS DECISIVOS", { s: 36, b: true, ls: 1 }) + t(73, 85, sub, { s: 16, c: C.apagado, max: 660 }) + seloH(W, seloDe(f));
      if (!ls.length) return svg(W, H, o + t(640, 380, "aguardando os boletins dos estados", { s: 22, c: C.apagado, a: "middle" }));
      ls.forEach(function (s, i) { o += cartaoDecisivo(s, 73 + (i % 3) * 382, 108 + Math.floor(i / 3) * 296, 370, 284, 1, aptosBr); });
      return svg(W, H, o + t(73, 708, "Fonte: TSE — boletins de Presidente dos estados; eleitorado (aptos) do próprio TSE", { s: 11, c: C.apagado2 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "ESTADOS DECISIVOS", { s: 28, b: true, ls: 1 }) + t(53, 106, "os 6 maiores eleitorados · " + turnoTxt(f), { s: 13, c: C.apagado, max: 450 }) + seloV(W2, seloDe(f));
    if (!ls.length) return svg(W2, H2, o + t(270, 480, "aguardando os boletins", { s: 18, c: C.apagado, a: "middle" }));
    ls.forEach(function (s, i) { o += cartaoDecisivoV(s, 35, 162 + i * 128, 470, 122, aptosBr); });
    return svg(W2, H2, o + t(35, 948, "Fonte: TSE — Presidente por estado", { s: 10, c: C.apagado2 }));
  }
  G["decisivos-h"] = function () { return telaDecisivos(false); };
  G["decisivos-v"] = function () { return telaDecisivos(true); };

  // ---- GOVERNADOR ELEITO x PRESIDENTE MAIS VOTADO NO ESTADO ------------------
  // So o fato: o partido do governador eleito e o partido do candidato a
  // presidente mais votado no estado. "Mesmo partido" = siglas iguais; nada
  // de apoio, alianca ou coligacao (isso o boletim do TSE nao traz).
  function siglaP(c) { return String(c && c.partido || "").toUpperCase().replace(/\s+/g, ""); }
  function govPres() {
    var f = fontePres(false);
    return Object.keys(DEP_UF).sort(function (a, b) { return DEP_UF[a].localeCompare(DEP_UF[b], "pt-BR"); }).map(function (k) {
      var st = govEstado(k), lp = liderF(f, k), gv = (st.tipo === "eleito1" || st.tipo === "eleito2") && st.c ? st.c : null;
      return { k: k, st: st, gov: gv, pres: lp, mesmo: !!(gv && lp && siglaP(gv) && siglaP(gv) === siglaP(lp)) };
    });
  }
  function celulaGov(l, x, y, wmax, fs) {
    if (l.gov) return r(x, y - fs - 4, 6, fs * 2 + 6, corPartidoCamara(l.gov.partido, 0), 2) + t(x + 12, y - 4, siglaP(l.gov), { s: fs, b: true, max: wmax - 12 }) +
      t(x + 12, y + fs - 2, l.gov.nome, { s: fs - 3, c: "#c9d6e6", max: wmax - 12 });
    if (l.st.tipo === "segundo") {
      var cs = l.st.cs || [];
      return t(x, y, "2º TURNO" + (cs.length === 2 ? ": " + siglaP(cs[0]) + " × " + siglaP(cs[1]) : ""), { s: fs - 1, b: true, c: "#7fb8ff", max: wmax });
    }
    return t(x, y, l.st.tipo === "apurando" ? "apurando" : "aguardando", { s: fs - 1, c: C.apagado, max: wmax });
  }
  function celulaPres(l, x, y, wmax, fs) {
    if (!l.pres) return t(x, y, "aguardando", { s: fs - 1, c: C.apagado });
    return r(x, y - fs - 4, 6, fs * 2 + 6, cor(l.pres), 2) + t(x + 12, y - 4, nomeCurto(l.pres), { s: fs, b: true, max: wmax - 12 }) +
      t(x + 12, y + fs - 2, siglaP(l.pres) + " · " + pct(l.pres.pct), { s: fs - 3, c: "#c9d6e6", max: wmax - 12 });
  }
  function chipMesmo(x, y, fs) { return r(x - 4, y - fs - 2, fs * 8.4, fs + 7, "rgba(255,255,255,0.92)", 3) + t(x - 4 + fs * 4.2, y, "MESMO PARTIDO", { s: fs - 1, b: true, c: "#0b1220", a: "middle" }); }
  function telaGovPres(v) {
    var f = fontePres(false), ls = govPres(), o;
    var comGov = ls.filter(function (l) { return l.gov && l.pres; }).length, mesmo = ls.filter(function (l) { return l.mesmo; }).length;
    var resumo = comGov ? "mesmo partido em " + mesmo + " de " + comGov + " estados com governador eleito" : "aguardando governadores eleitos";
    if (!v) {
      var W = 1280, H = 720;
      o = t(73, 57, "GOVERNADOR × PRESIDENTE", { s: 36, b: true, ls: 1 }) + t(73, 85, "governador eleito e o candidato a presidente mais votado no estado · " + turnoTxt(f), { s: 16, c: C.apagado, max: 660 }) + seloH(W, seloDe(f));
      o += r(73, 100, 1134, 34, "rgba(8,14,32,0.84)", 6) + t(90, 123, resumo.toUpperCase(), { s: 15, b: true, ls: 1 });
      [0, 1].forEach(function (col) {
        var x = 73 + col * 575;
        o += t(x + 6, 156, "ESTADO", { s: 10, b: true, c: C.apagado, ls: 1 }) + t(x + 128, 156, "GOVERNADOR", { s: 10, b: true, c: C.apagado, ls: 1 }) + t(x + 358, 156, "MAIS VOTADO P/ PRESIDENTE", { s: 10, b: true, c: C.apagado, ls: 1 });
      });
      ls.forEach(function (l, i) {
        var col = i < 14 ? 0 : 1, li = col ? i - 14 : i, x = 73 + col * 575, y = 182 + li * 37;
        o += r(x, y - 22, 559, 35, l.mesmo ? "rgba(255,255,255,0.13)" : (li % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)"), 3);
        o += t(x + 6, y, DEP_UF[l.k], { s: 12, b: true, max: 116 });
        o += celulaGov(l, x + 128, y, 222, 13);
        o += celulaPres(l, x + 358, y, 112, 13);
        if (l.mesmo) o += chipMesmo(x + 472, y + 1, 10);
      });
      return svg(W, H, o + t(73, 708, "Fonte: TSE. \"Mesmo partido\" = a sigla do governador eleito é a mesma do candidato a presidente mais votado no estado (não indica apoio).", { s: 11, c: C.apagado2, max: 1134 }));
    }
    var W2 = 540, H2 = 960;
    o = r(35, 48, 6, 38, C.destaque) + t(53, 80, "GOVERNADOR × PRESIDENTE", { s: 24, b: true, ls: 1, max: 330 }) + t(53, 106, resumo, { s: 13, c: C.apagado, max: 450 }) + seloV(W2, seloDe(f));
    o += t(41, 176, "UF", { s: 10, b: true, c: C.apagado }) + t(80, 176, "GOVERNADOR", { s: 10, b: true, c: C.apagado }) + t(300, 176, "PRESIDENTE (MAIS VOTADO)", { s: 10, b: true, c: C.apagado });
    ls.forEach(function (l, i) {
      var y = 200 + i * 27;
      o += r(35, y - 18, 470, 24, l.mesmo ? "rgba(255,255,255,0.15)" : (i % 2 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.07)"), 3);
      o += t(41, y, l.k.toUpperCase(), { s: 12, b: true });
      if (l.gov) o += r(80, y - 11, 5, 13, corPartidoCamara(l.gov.partido, 0), 2) + t(90, y, siglaP(l.gov) + " · " + nomeCurto(l.gov), { s: 11, b: true, max: 200 });
      else o += t(80, y, l.st.tipo === "segundo" ? "2º TURNO" : "aguardando", { s: 10, b: true, c: l.st.tipo === "segundo" ? "#7fb8ff" : C.apagado });
      if (l.pres) o += r(300, y - 11, 5, 13, cor(l.pres), 2) + t(310, y, nomeCurto(l.pres) + " " + pct(l.pres.pct), { s: 11, c: "#c9d6e6", max: l.mesmo ? 120 : 190 });
      if (l.mesmo) o += t(499, y, "= PARTIDO", { s: 10, b: true, a: "end" });
    });
    return svg(W2, H2, o + t(35, 948, "Fonte: TSE · \"= partido\": mesma sigla do governador eleito e do mais votado (não indica apoio)", { s: 9, c: C.apagado2, max: 470 }));
  }
  G["govpres-h"] = function () { return telaGovPres(false); };
  G["govpres-v"] = function () { return telaGovPres(true); };

  // ---- PRESIDENTE ELEITO -----------------------------------------------------
  // Vai ao ar SOZINHA nas duas saidas quando o TSE declara o eleito (vigia do
  // gerenciador). "ELEITO" so com a marca do TSE no boletim; antes disso a
  // tela diz que aguarda a declaracao e mostra o placar.
  function eleitoPres() {
    var f = fontePres(false), b = f.br, cs = b ? candidatos(b) : [], el = cs.filter(function (c) { return c.eleito; })[0] || null;
    var outro = el ? cs.filter(function (c) { return c !== el; })[0] : cs[1];
    var nUf = 0, nOutro = 0;
    Object.keys(DEP_UF).forEach(function (k) { var l = liderF(f, k); if (!l || !el) return; if (String(l.numero) === String(el.numero)) nUf++; else nOutro++; });
    return { f: f, b: b, el: el, lider: el || cs[0] || null, outro: outro || null, nUf: nUf, nOutro: nOutro };
  }
  function mapaEleito(e, x, y, esc) {
    return mapaCor(x, y, esc, function (k) {
      var l = liderF(e.f, k); if (!l) return null;
      return e.el && String(l.numero) === String(e.el.numero) ? cor(l) : misturar(cor(l), C.fundo, 0.55);
    }, { esp: 1 });
  }
  G["eleito-h"] = function () {
    var W = 1280, H = 720, e = eleitoPres(), c = e.lider, o = "", s = e.b ? e.b.secoes : null;
    if (!c) return svg(W, H, t(73, 57, "PRESIDENTE ELEITO", { s: 36, b: true, ls: 1 }) + seloH(W) + t(640, 380, "aguardando o boletim do TSE", { s: 24, c: C.apagado, a: "middle" }));
    o += t(73, 57, e.el ? "PRESIDENTE ELEITO" : "PRESIDENTE — " + turnoTxt(e.f), { s: 36, b: true, ls: 2 }) +
      t(73, 85, e.el ? "Eleições 2026 · declarado pelo TSE" : (e.b && e.b.andamento === "f" && e.f.turno === 1 ? "sem eleito no 1º turno: haverá 2º turno · " : "aguardando o TSE declarar o eleito · ") + subtitulo(), { s: 18, c: C.apagado, max: 660 }) + seloH(W);
    o += r(73, 112, 760, 520, "rgba(8,14,32,0.84)", 12) + r(73, 112, 10, 520, cor(c), 5);
    o += fotoOuSilhueta(urlFoto(c), 108, 146, 270, 360);
    o += t(410, 190, c.nome, { s: 52, b: true, max: 400, nome: true }) + t(410, 228, c.partido, { s: 24, c: C.apagado, max: 400 });
    if (e.el) o += r(410, 252, 186, 48, C.verde, 6) + t(503, 286, "ELEITO", { s: 30, b: true, a: "middle", ls: 3 });
    else o += t(410, 284, c.segundo_turno ? "vai ao 2º turno" : "lidera a apuração", { s: 22, b: true, c: "#ffd43b" });
    o += t(410, 400, pct(c.pct), { s: 92, b: true }) + t(410, 430, "dos votos válidos", { s: 18, c: C.apagado });
    o += t(410, 470, inteiro(c.votos) + " votos", { s: 26, b: true, c: "#c9d6e6" });
    if (e.outro) o += r(108, 540, 690, 2, "rgba(255,255,255,0.15)", 0) + r(108, 562, 6, 40, cor(e.outro), 2) +
      t(126, 590, e.outro.nome + "  ·  " + e.outro.partido, { s: 22, b: true, max: 430 }) + t(798, 590, pct(e.outro.pct) + "  ·  " + inteiro(e.outro.votos) + " votos", { s: 20, c: "#c9d6e6", a: "end" });
    o += mapaEleito(e, 868, 150, 0.54);
    if (e.el) o += t(1030, 520, "venceu em " + e.nUf + (e.nUf === 1 ? " estado" : " estados"), { s: 22, b: true, a: "middle" }) +
      t(1030, 548, e.outro ? nomeCurto(e.outro) + ": " + e.nOutro : "", { s: 16, c: C.apagado, a: "middle" });
    return svg(W, H, o + t(73, 690, (s ? "urnas apuradas " + pct(s.pct) + "  ·  " : "") + "Fonte: TSE" + (e.el ? " — eleito declarado no boletim oficial" : ""), { s: 14, c: C.apagado2 }));
  };
  G["eleito-v"] = function () {
    var W = 540, H = 960, e = eleitoPres(), c = e.lider, o = "", s = e.b ? e.b.secoes : null;
    o += r(35, 48, 6, 38, C.destaque) + t(53, 80, e.el ? "PRESIDENTE ELEITO" : "PRESIDENTE", { s: 30, b: true, ls: 1 }) +
      t(53, 106, e.el ? "Eleições 2026 · declarado pelo TSE" : "aguardando o TSE declarar o eleito", { s: 14, c: C.apagado, max: 450 }) + seloV(W);
    if (!c) return svg(W, H, o + t(270, 480, "aguardando o boletim do TSE", { s: 18, c: C.apagado, a: "middle" }));
    o += r(35, 168, 470, 560, "rgba(8,14,32,0.84)", 12) + r(35, 168, 470, 8, cor(c), 4);
    o += fotoOuSilhueta(urlFoto(c), 150, 200, 240, 320);
    o += t(270, 568, c.nome, { s: 38, b: true, a: "middle", max: 440, nome: true }) + t(270, 598, c.partido, { s: 20, c: C.apagado, a: "middle" });
    if (e.el) o += r(185, 616, 170, 44, C.verde, 6) + t(270, 648, "ELEITO", { s: 28, b: true, a: "middle", ls: 3 });
    else o += t(270, 645, c.segundo_turno ? "vai ao 2º turno" : "lidera a apuração", { s: 20, b: true, c: "#ffd43b", a: "middle" });
    o += t(270, 708, pct(c.pct) + "  ·  " + inteiro(c.votos) + " votos", { s: 22, b: true, a: "middle", max: 440 });
    if (e.outro) o += r(35, 744, 6, 40, cor(e.outro), 2) + t(52, 763, e.outro.nome + " · " + e.outro.partido, { s: 17, b: true, max: 300 }) +
      t(52, 783, inteiro(e.outro.votos) + " votos", { s: 13, c: C.apagado }) + t(505, 773, pct(e.outro.pct), { s: 24, b: true, a: "end" });
    o += mapaEleito(e, 35, 800, 0.2);
    if (e.el) o += t(205, 850, "venceu em", { s: 15, c: C.apagado }) + t(205, 884, e.nUf + (e.nUf === 1 ? " estado" : " estados"), { s: 28, b: true });
    return svg(W, H, o + t(35, 950, (s ? "urnas " + pct(s.pct) + " · " : "") + "Fonte: TSE", { s: 12, c: C.apagado2 }));
  };

  // ---- TELA "AGUARDANDO O TSE" (automatica) ---------------------------------
  // Tela no ar sem o dado de que ela depende (antes das 17h, boletim ainda nao
  // lido, coleta recem-aberta): em vez de numeros zerados, uma tela limpa
  // com o nome da tela. Volta sozinha quando o dado chega.
  var SEM_PRESIDENTE = /^(senado|comparativo|mulheres|perfilcamara|camara|deputados|topdep|assembleia|assembleias|governadores|govpartido|gov2t|senadores|senadores1|senadores2)-/;
  var DE_ESTADOS = /^(camara|deputados|topdep|assembleia|assembleias|governadores|govpartido|gov2t|senadores|senadores1|senadores2|govpres)-/;
  function temPresidente() { var b = D().br; return !!(b && b.tem); }
  function temEstados() { return !!(window.GCTSE_ESTADOS && window.GCTSE_ESTADOS.gravado_em); }
  function telaAguardando(id) {
    var v = /-v$/.test(id), W = v ? 540 : 1280, H = v ? 960 : 720;
    var g = (window.GCTSE_GRAFICOS ? window.GCTSE_GRAFICOS.lista : []).filter(function (x) { return x.id === id; })[0], nm = String(g ? g.nome : "").toUpperCase();
    var sl = { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho };
    var o = v ? r(35, 48, 6, 38, C.destaque) + t(53, 80, nm, { s: 26, b: true, ls: 1, max: 450 }) + seloV(W, sl) : t(73, 57, nm, { s: 34, b: true, ls: 1, max: 660 }) + seloH(W, sl);
    o += t(W / 2, H / 2 - (v ? 10 : 6), "AGUARDANDO O TSE", { s: v ? 34 : 52, b: true, a: "middle", ls: 3 });
    o += t(W / 2, H / 2 + (v ? 30 : 44), "os números aparecem assim que o TSE publicar", { s: v ? 16 : 22, c: C.apagado, a: "middle", max: W - 60 });
    return svg(W, H, o);
  }
  function desenharTela(id) {
    if (!G[id]) return null;
    if ((!SEM_PRESIDENTE.test(id) && !temPresidente()) || (DE_ESTADOS.test(id) && !temEstados())) return telaAguardando(id);
    return G[id]();
  }
  window.GCTSE_EXTERIOR_SEM_PAIS = exteriorSemPais;
  window.GCTSE_GRAFICOS = {
    lista: [
      { id: "eleito-h", nome: "Presidente eleito", f: "h" },
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
      { id: "virar-h", nome: "Ainda dá para virar?", f: "h" },
      { id: "gov2t-h", nome: "Governadores — 2º turno (placar)", f: "h" },
      { id: "viradas-h", nome: "Estados que viraram (1º → 2º)", f: "h" },
      { id: "margem-h", nome: "Disputa mais apertada", f: "h" },
      { id: "ganho-h", nome: "Ganho de votos 1º → 2º turno", f: "h" },
      { id: "abstuf-h", nome: "Abstenção 1º × 2º por estado", f: "h" },
      { id: "turno22-h", nome: "2º turno: 2022 × 2026 por estado", f: "h" },
      { id: "capitais-h", nome: "Presidente nas capitais", f: "h" },
      { id: "exterior-h", nome: "Brasileiros no exterior (por país)", f: "h" },
      { id: "excidades-h", nome: "Exterior: por cidade", f: "h" },
      { id: "decisivos-h", nome: "Estados decisivos (6 maiores eleitorados)", f: "h" },
      { id: "govpres-h", nome: "Governador × Presidente no estado", f: "h" },
      { id: "perfilcamara-h", nome: "Perfil da nova Câmara", f: "h" },
      { id: "assembleia-h", nome: "Assembleia Legislativa (por estado)", f: "h" },
      { id: "assembleias-h", nome: "Assembleias — Brasil (por partido)", f: "h" },
      { id: "topdep-h", nome: "10 deputados federais mais votados", f: "h" },
      { id: "eleito-v", nome: "Presidente eleito", f: "v" },
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
      { id: "turnos-v", nome: "1º × 2º turno: abstenção, brancos e nulos", f: "v" },
      { id: "virar-v", nome: "Ainda dá para virar?", f: "v" },
      { id: "gov2t-v", nome: "Governadores — 2º turno (placar)", f: "v" },
      { id: "viradas-v", nome: "Estados que viraram (1º → 2º)", f: "v" },
      { id: "margem-v", nome: "Disputa mais apertada", f: "v" },
      { id: "ganho-v", nome: "Ganho de votos 1º → 2º turno", f: "v" },
      { id: "abstuf-v", nome: "Abstenção 1º × 2º por estado", f: "v" },
      { id: "turno22-v", nome: "2º turno: 2022 × 2026 por estado", f: "v" },
      { id: "capitais-v", nome: "Presidente nas capitais", f: "v" },
      { id: "exterior-v", nome: "Brasileiros no exterior (por país)", f: "v" },
      { id: "excidades-v", nome: "Exterior: por cidade", f: "v" },
      { id: "decisivos-v", nome: "Estados decisivos (6 maiores eleitorados)", f: "v" },
      { id: "govpres-v", nome: "Governador × Presidente no estado", f: "v" },
      { id: "perfilcamara-v", nome: "Perfil da nova Câmara", f: "v" },
      { id: "assembleia-v", nome: "Assembleia Legislativa (por estado)", f: "v" },
      { id: "assembleias-v", nome: "Assembleias — Brasil (por partido)", f: "v" },
      { id: "topdep-v", nome: "10 deputados federais mais votados", f: "v" }
    ],
    desenhar: function (id) { return desenharTela(id); },
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
