// gctse GRAFICOS - RESUMO: 7 telas de fechamento, trocadas na mao.
//   1 Mapa dos governadores      2 Governadores eleitos por partido
//   3 Senado: eleitos/partido    4 Presidente por regiao
//   5 Comparecimento por estado  6 Estado em destaque (Parana)
//   7 2026 x 2022 (comparecimento, abstencao, brancos, nulos)
// Dados: web\estados.js (ESTADOS.bat) e web\dados.js (GRAFICOS.bat).
// So soma e conta o que o TSE mandou; ELEITO e 2o TURNO so com a palavra do TSE.
(function () {
  "use strict";

  var C = {
    fundo: "#0b1220", texto: "#ffffff", apagado: "#8ea3bd", apagado2: "#6b7f99",
    trilho: "#283548", painel: "#121b2b", vermelho: "#d03b3b", verde: "#16b216",
    azul: "#2b84ff", neutro: "#7398cf", vazio: "#283548"
  };
  var FONTE = "'Segoe UI', 'DejaVu Sans', Arial, sans-serif";
  var UFS = ["ac", "al", "ap", "am", "ba", "ce", "df", "es", "go", "ma", "mt", "ms", "mg", "pa",
             "pb", "pr", "pe", "pi", "rj", "rn", "rs", "ro", "rr", "sc", "sp", "se", "to"];
  var REGIOES = [
    { nome: "NORTE", ufs: ["ac", "am", "ap", "pa", "ro", "rr", "to"] },
    { nome: "NORDESTE", ufs: ["al", "ba", "ce", "ma", "pb", "pe", "pi", "rn", "se"] },
    { nome: "CENTRO-OESTE", ufs: ["df", "go", "ms", "mt"] },
    { nome: "SUDESTE", ufs: ["es", "mg", "rj", "sp"] },
    { nome: "SUL", ufs: ["pr", "rs", "sc"] }
  ];

  // ------------------------------------------------------------- utilidades
  function esc(x) {
    return String(x == null ? "" : x).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pct(v) { return (v == null || isNaN(v)) ? "—" : Number(v).toFixed(2).replace(".", ",") + "%"; }
  function t(x, y, txt, o) {
    o = o || {};
    return '<text x="' + x + '" y="' + y + '" font-size="' + (o.s || 16) + '"' +
      (o.b ? ' font-weight="700"' : "") + ' fill="' + (o.c || C.texto) + '"' +
      (o.a ? ' text-anchor="' + o.a + '"' : "") + (o.ls ? ' letter-spacing="' + o.ls + '"' : "") +
      (o.max ? ' data-max="' + o.max + '"' : "") + (o.max && o.nome ? ' data-curto="' + esc(curto(txt)) + '"' : "") +
      ">" + esc(txt) + "</text>";
  }
  // Nome que nao cabe: primeiro e segundo nome ("DR. FERNANDO", "JOSE DA
  // SILVA" com o "DA" junto); so depois encolhe a letra.
  function curto(n) {
    var p = String(n == null ? "" : n).trim().split(/\s+/);
    if (p.length <= 2) return "";
    var k = ["DA", "DE", "DO", "DAS", "DOS", "E"].indexOf(p[1].toUpperCase()) >= 0 ? 3 : 2;
    return k >= p.length ? "" : p.slice(0, k).join(" ");
  }
  function r(x, y, w, h, c, rx) {
    return '<rect x="' + x + '" y="' + y + '" width="' + Math.max(0, w) + '" height="' + h + '" fill="' + c + '"' +
      (rx ? ' rx="' + rx + '"' : "") + "/>";
  }
  function barra(x, y, w, h, frac, c) {
    frac = Math.max(0, Math.min(1, frac || 0));
    return r(x, y, w, h, C.trilho, 4) + (frac > 0 ? r(x, y, Math.max(8, w * frac), h, c, 4) : "");
  }
  function lista(x) { return Array.isArray(x) ? x : (x && Array.isArray(x.value) ? x.value : []); }
  function svg(W, H, corpo) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + W + " " + H + '" width="' + W + '" height="' + H +
      '" font-family="' + FONTE + '">' + r(0, 0, W, H, C.fundo) + corpo + "</svg>";
  }

  // ------------------------------------------------------------------ dados
  function E() { return window.GCTSE_ESTADOS || { ufs: {} }; }
  function P() { return window.GCTSE_DADOS || { ufs: {} }; }
  function cargo(u, qual) {
    var e = (E().ufs || {})[u], c = e && e[qual];
    if (!c || !c.tem) return null;
    c.candidatos = lista(c.candidatos);
    return c;
  }
  function situacao(c) {
    if (!c) return "vazio";
    if (c.candidatos.some(function (x) { return x.eleito; })) return "eleito";
    if (c.candidatos.some(function (x) { return x.segundo_turno; })) return "segundo";
    return c.urnas_pct > 0 ? "andamento" : "vazio";
  }
  function presUf(u) {
    var x = (P().ufs || {})[u];
    if (!x || !x.tem) return null;
    x.candidatos = lista(x.candidatos);
    return x;
  }

  // Selo das telas de Governador/Senador e das de Presidente.
  function seloEstados() {
    var fim = true, algum = false;
    UFS.forEach(function (u) {
      ["gov", "sen"].forEach(function (q) {
        var c = cargo(u, q);
        if (!c || c.andamento !== "f") fim = false;
        if (c && c.urnas_pct > 0) algum = true;
      });
    });
    if (fim) return { texto: "TOTALIZAÇÃO FINAL", cor: C.verde };
    return algum ? { texto: "PARCIAL", cor: C.vermelho } : { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho };
  }
  function seloPresidente() {
    var b = P().br;
    if (b && b.tem && b.andamento === "f") return { texto: "TOTALIZAÇÃO FINAL", cor: C.verde };
    var p = b && b.tem && b.secoes ? b.secoes.pct : 0;
    return p > 0 ? { texto: "PARCIAL", cor: C.vermelho } : { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho };
  }

  // Cabecalho: titulo grande, linha de apoio e selo.
  function cab(v, W, titulo, sub, s) {
    if (!v) {
      return t(73, 74, titulo, { s: 44, b: true, ls: 1, max: W - 73 - 380 }) + t(73, 108, sub, { s: 20, c: C.apagado, max: W - 146 }) +
        '<g data-selo="1" data-x="' + (W - 73) + '">' + r(W - 340, 44, 267, 36, s.cor, 3) +
        t(W - 81, 70, s.texto, { s: 20, b: true, a: "end" }) + "</g>";
    }
    return t(30, 62, titulo, { s: 32, b: true, max: W - 60 }) + t(30, 88, sub, { s: 15, c: C.apagado, max: W - 60 }) +
      r(30, 102, W - 60, 28, s.cor, 2) + t(W / 2, 122, s.texto, { s: 16, b: true, a: "middle" });
  }
  function rodape(v, W, H, txt) { return t(v ? 30 : 73, H - (v ? 12 : 18), txt, { s: v ? 11 : 13, c: C.apagado2 }); }

  // =============================================== 1. MAPA DOS GOVERNADORES
  function corSit(s) { return s === "eleito" ? C.verde : s === "segundo" ? C.azul : s === "andamento" ? C.neutro : C.vazio; }
  function mapaGov(v) {
    var W = v ? 540 : 1280, H = v ? 960 : 720, M = window.MAPA_BRASIL, o = "";
    var cont = { eleito: 0, segundo: 0, andamento: 0, vazio: 0 }, seg = [];
    UFS.forEach(function (u) { var s = situacao(cargo(u, "gov")); cont[s]++; if (s === "segundo") seg.push(u.toUpperCase()); });
    o += cab(v, W, "GOVERNADORES", "situação em cada estado", seloEstados());
    var esc0 = v ? 0.78 : 0.86, mx = v ? 31 : 60, my = v ? 146 : 132;
    o += '<g transform="translate(' + mx + " " + my + ") scale(" + esc0 + ')">';
    var k, e;
    for (k in M.estados) {
      e = M.estados[k];
      o += '<path d="' + e.path + '" fill="' + corSit(situacao(cargo(k, "gov"))) + '" stroke="' + C.fundo +
        '" stroke-width="' + (1.4 / esc0).toFixed(2) + '" stroke-linejoin="round"/>';
    }
    var contorno = ' stroke="' + C.fundo + '" stroke-width="' + (3 / esc0).toFixed(2) + '" paint-order="stroke" stroke-linejoin="round"';
    for (k in M.estados) {
      if (["rn", "pb", "pe", "al", "se", "df", "es", "rj"].indexOf(k) >= 0) continue;
      e = M.estados[k];
      o += '<text x="' + e.cx + '" y="' + (e.cy + 5) + '" font-size="' + (14 / esc0 * (v ? 0.9 : 1)).toFixed(1) +
        '" font-weight="700" fill="#fff" text-anchor="middle"' + contorno + ">" + k.toUpperCase() + "</text>";
    }
    o += "</g>";
    // placar
    var itens = [["eleito", "ELEITOS NO 1º TURNO"], ["segundo", "VÃO AO 2º TURNO"], ["andamento", "EM APURAÇÃO"], ["vazio", "AGUARDANDO"]];
    if (!v) {
      var px = 690, py = 190;
      itens.forEach(function (it, i) {
        var yy = py + i * 104;
        o += r(px, yy, 22, 22, corSit(it[0]), 3) + t(px + 40, yy + 20, it[1], { s: 20, b: true, ls: 1, c: C.apagado });
        o += t(px + 40, yy + 78, String(cont[it[0]]), { s: 54, b: true });
        o += t(px + 40 + String(cont[it[0]]).length * 34 + 20, yy + 78, cont[it[0]] === 1 ? "estado" : "estados", { s: 22, c: C.apagado });
      });
      if (seg.length) o += t(px, 640, "2º turno: " + seg.join(", "), { s: 20, b: true, c: "#5fb0f0", max: 1207 - px });
    } else {
      itens.forEach(function (it, i) {
        var cx = 30 + (i % 2) * 245, yy = 680 + Math.floor(i / 2) * 110;
        o += r(cx, yy, 18, 18, corSit(it[0]), 3) + t(cx + 28, yy + 15, it[1], { s: 13, b: true, c: C.apagado, max: 205 });
        o += t(cx + 28, yy + 70, String(cont[it[0]]), { s: 46, b: true });
      });
      if (seg.length) o += t(30, 918, "2º turno: " + seg.join(", "), { s: 15, b: true, c: "#5fb0f0", max: W - 60 });
    }
    o += rodape(v, W, H, "Fonte: TSE");
    return svg(W, H, o);
  }

  // ===================================== 2 e 3. ELEITOS POR PARTIDO (barras)
  function porPartido(qual) {
    var conta = {};
    UFS.forEach(function (u) {
      var c = cargo(u, qual);
      if (!c) return;
      c.candidatos.forEach(function (k) {
        if (!k.eleito) return;
        var p = k.partido || "?";
        if (!conta[p]) conta[p] = { partido: p, n: 0, ufs: [] };
        conta[p].n++; conta[p].ufs.push(u.toUpperCase());
      });
    });
    return Object.keys(conta).map(function (p) { return conta[p]; })
      .sort(function (a, b) { return b.n - a.n || a.partido.localeCompare(b.partido); });
  }
  function barrasPartido(v, titulo, sub, linhas, rodapeTxt, extra) {
    var W = v ? 540 : 1280, H = v ? 960 : 720, o = cab(v, W, titulo, sub, seloEstados());
    var x0 = v ? 30 : 73, x1 = v ? W - 30 : 1207, y0 = v ? 160 : 150, alt = v ? 740 : (extra ? 470 : 510);
    if (!linhas.length) {
      o += t(x0, y0 + 60, "nenhum eleito ainda — o TSE ainda não declarou", { s: v ? 18 : 24, c: C.apagado });
    } else {
      var max = linhas[0].n, n = Math.min(linhas.length, v ? 12 : 10), passo = Math.min(v ? 70 : 80, alt / n);
      var colP = v ? 150 : 210, colN = 70, bw = x1 - x0 - colP - colN;
      for (var i = 0; i < n; i++) {
        var L = linhas[i], yy = y0 + i * passo;
        o += t(x0, yy + passo * 0.5, L.partido, { s: v ? 18 : 24, b: true, max: colP - 14 });
        o += t(x0, yy + passo * 0.5 + (v ? 18 : 22), L.ufs.join(", "), { s: v ? 11 : 14, c: C.apagado, max: colP - 14 });
        o += barra(x0 + colP, yy + passo * 0.5 - (v ? 14 : 18), bw, v ? 18 : 24, L.n / max * 0.98, C.verde);
        o += t(x1, yy + passo * 0.5, String(L.n), { s: v ? 24 : 32, b: true, a: "end" });
      }
      if (linhas.length > n) o += t(x0, y0 + n * passo + 10, "+ " + (linhas.length - n) + " partido(s)", { s: 14, c: C.apagado });
    }
    if (extra) o += t(x0, v ? 920 : 676, extra, { s: v ? 15 : 20, b: true, c: "#5fb0f0", max: x1 - x0 });
    o += rodape(v, W, H, rodapeTxt);
    return svg(W, H, o);
  }
  function govPartido(v) {
    var L = porPartido("gov"), total = L.reduce(function (a, b) { return a + b.n; }, 0), seg = [];
    UFS.forEach(function (u) { if (situacao(cargo(u, "gov")) === "segundo") seg.push(u.toUpperCase()); });
    return barrasPartido(v, "GOVERNADORES POR PARTIDO", total + " de 27 estados com governador eleito no 1º turno", L,
      "Fonte: TSE — conta só quem o TSE declarou ELEITO", seg.length ? "2º turno em " + seg.length + " estado(s): " + seg.join(", ") : "");
  }
  function senPartido(v) {
    var L = porPartido("sen"), total = L.reduce(function (a, b) { return a + b.n; }, 0);
    return barrasPartido(v, "SENADO — ELEITOS POR PARTIDO", total + " de 54 vagas definidas (2 por estado)", L,
      "Fonte: TSE — conta só quem o TSE declarou ELEITO", "");
  }

  // ====================================================== 4. PRESIDENTE POR REGIAO
  function corCand(c) {
    try { return window.GCTSE_GRAFICOS.cor(c); } catch (e) { return C.neutro; }
  }
  function regiao(R) {
    var soma = {}, ref = {}, tot = 0, sec = 0, secT = 0, com = 0;
    R.ufs.forEach(function (u) {
      var x = presUf(u);
      if (!x) return;
      com++;
      if (x.secoes) { sec += x.secoes.totalizadas || 0; secT += x.secoes.total || 0; }
      x.candidatos.forEach(function (k) {
        soma[k.numero] = (soma[k.numero] || 0) + (k.votos || 0); ref[k.numero] = k; tot += k.votos || 0;
      });
    });
    var cs = Object.keys(soma).map(function (n) { return { c: ref[n], votos: soma[n], pct: tot > 0 ? soma[n] / tot * 100 : 0 }; })
      .sort(function (a, b) { return b.votos - a.votos; });
    return { nome: R.nome, cs: cs, urnas: secT > 0 ? sec / secT * 100 : null, com: com, n: R.ufs.length };
  }
  function presRegiao(v) {
    var W = v ? 540 : 1280, H = v ? 960 : 720;
    var o = cab(v, W, "PRESIDENTE POR REGIÃO", "1º e 2º colocados em cada região", seloPresidente());
    var x0 = v ? 30 : 73, x1 = v ? W - 30 : 1207, y0 = v ? 150 : 140, passo = v ? 156 : 104;
    REGIOES.forEach(function (R, i) {
      var g = regiao(R), yy = y0 + i * passo;
      o += r(x0, yy, x1 - x0, passo - 10, C.painel, 6);
      var lx = x0 + 20, colR = v ? 0 : 250;
      o += t(lx, yy + (v ? 30 : 40), g.nome, { s: v ? 18 : 24, b: true, ls: 1 });
      o += t(lx, yy + (v ? 50 : 66), "urnas " + pct(g.urnas), { s: v ? 13 : 16, c: C.apagado });
      var cx0 = v ? lx : x0 + colR, cw = x1 - 20 - cx0;
      var top = g.cs.length && g.cs[0].pct > 0 ? g.cs[0].pct : 100;
      if (!g.cs.length || !(g.cs[0].votos > 0)) {
        o += t(cx0, yy + (v ? 92 : 52), "aguardando votos", { s: v ? 16 : 20, c: C.apagado });
        return;
      }
      g.cs.slice(0, 2).forEach(function (k, j) {
        var ly = yy + (v ? 64 : 16) + j * (v ? 40 : 40);
        o += t(cx0, ly + 18, k.c.nome, { s: v ? 16 : 20, b: true, max: cw * 0.45 });
        o += t(x1 - 20, ly + 18, pct(k.pct), { s: v ? 18 : 22, b: true, a: "end" });
        o += barra(cx0 + cw * 0.47, ly + 6, cw * 0.53 - 100, v ? 10 : 14, k.pct / top * 0.98, corCand(k.c));
      });
    });
    o += rodape(v, W, H, "Fonte: TSE — soma dos votos dos estados de cada região (sem o exterior)");
    return svg(W, H, o);
  }

  // =================================================== 5. COMPARECIMENTO POR UF
  function comparecimento(v) {
    var W = v ? 540 : 1280, H = v ? 960 : 720;
    var o = cab(v, W, "COMPARECIMENTO POR ESTADO", "% dos eleitores que votaram, nas urnas já apuradas", seloPresidente());
    var L = [];
    UFS.forEach(function (u) {
      var x = presUf(u);
      if (x && x.eleitorado && x.eleitorado.pct_comparec > 0) L.push({ u: u, p: x.eleitorado.pct_comparec });
    });
    L.sort(function (a, b) { return b.p - a.p; });
    if (!L.length) {
      o += t(v ? 30 : 73, v ? 220 : 210, "aguardando os primeiros boletins dos estados", { s: v ? 18 : 24, c: C.apagado });
      return svg(W, H, o + rodape(v, W, H, "Fonte: TSE"));
    }
    var cols = v ? 1 : 2, porCol = Math.ceil(L.length / cols), y0 = v ? 150 : 140;
    var passo = Math.min(v ? 29 : 37, (H - y0 - 40) / porCol), cw = v ? W - 60 : 540;
    L.forEach(function (it, i) {
      var c = Math.floor(i / porCol), x = (v ? 30 : 73) + c * (cw + 54), yy = y0 + (i % porCol) * passo;
      o += t(x, yy + passo * 0.62, it.u.toUpperCase(), { s: v ? 14 : 18, b: true });
      o += barra(x + 48, yy + passo * 0.25, cw - 48 - 90, passo * 0.45, it.p / 100, C.azul);
      o += t(x + cw, yy + passo * 0.62, pct(it.p), { s: v ? 14 : 18, b: true, a: "end" });
    });
    o += rodape(v, W, H, "Fonte: TSE — comparecimento sobre o eleitorado das seções já totalizadas");
    return svg(W, H, o);
  }

  // ============================================ 6. TELA DO ESTADO (PARANA)
  var NOMES = {
    ac: "ACRE", al: "ALAGOAS", ap: "AMAPÁ", am: "AMAZONAS", ba: "BAHIA", ce: "CEARÁ", df: "DISTRITO FEDERAL",
    es: "ESPÍRITO SANTO", go: "GOIÁS", ma: "MARANHÃO", mt: "MATO GROSSO", ms: "MATO GROSSO DO SUL", mg: "MINAS GERAIS",
    pa: "PARÁ", pb: "PARAÍBA", pr: "PARANÁ", pe: "PERNAMBUCO", pi: "PIAUÍ", rj: "RIO DE JANEIRO", rn: "RIO GRANDE DO NORTE",
    rs: "RIO GRANDE DO SUL", ro: "RONDÔNIA", rr: "RORAIMA", sc: "SANTA CATARINA", sp: "SÃO PAULO", se: "SERGIPE", to: "TOCANTINS"
  };
  // Estado da tela 6: o escolhido no GERENCIADOR (definirUf), senao o
  // estado_destaque do giro-config.js.
  var UF_ESCOLHIDA = null;
  function ufDestaque() {
    if (UF_ESCOLHIDA && NOMES[UF_ESCOLHIDA]) return UF_ESCOLHIDA;
    var u = String((window.GCTSE_GIRO || {}).estado_destaque || "pr").toLowerCase();
    return NOMES[u] ? u : "pr";
  }
  // --------------------------------------------------- foto oficial do TSE
  // Igual ao giro: {base}/{ciclo}/{eleicao}/fotos/{uf}/{sqcand}.jpeg, direto
  // do TSE. Foto que falhar some (a tela e refeita sem ela) e nao e pedida
  // de novo; 3 falhas sem nenhum acerto desligam as fotos.
  var FOTO = { falhou: {}, falhas: 0, acertos: 0 };
  window.__gctseFotoR = function (img, ok) {
    var url = img.getAttribute("href");
    if (ok) { FOTO.acertos++; return; }
    if (!FOTO.falhou[url]) { FOTO.falhou[url] = true; FOTO.falhas++; }
    var g = img.parentNode; if (g && g.parentNode) g.parentNode.removeChild(g);
    var refazer = (window.GCTSE_RESUMO_CONTROLE && window.GCTSE_RESUMO_CONTROLE.redesenhar) || window.__gctseRedesenhar;
    if (refazer) { clearTimeout(FOTO.timer); FOTO.timer = setTimeout(refazer, 300); }
  };
  function urlFoto(u, k) {
    if (window.GCTSE_FOTOS_DO_TSE !== true) return "";   // chave em web\fotos-config.js
    var tse = E().tse;
    if (!tse || !tse.base || !k || !k.sqcand) return "";
    if (FOTO.falhas >= 3 && FOTO.acertos === 0) return "";
    var url = tse.base + "/" + tse.ciclo + "/" + tse.eleicao + "/fotos/" + u + "/" + k.sqcand + ".jpeg";
    return FOTO.falhou[url] ? "" : url;
  }
  // Presidente: mesma foto dos graficos do Presidente (dados.js, pasta
  // fotos/br), pelo sqcand do boletim nacional.
  function urlFotoP(k) {
    if (window.GCTSE_FOTOS_DO_TSE !== true) return "";
    var tse = P().tse, br = P().br;
    if (!tse || !tse.base || !k) return "";
    if (FOTO.falhas >= 3 && FOTO.acertos === 0) return "";
    var sq = k.sqcand;
    lista(br && br.candidatos).forEach(function (n) { if (n.numero === k.numero && n.sqcand) sq = n.sqcand; });
    if (!sq) return "";
    var url = tse.base + "/" + tse.ciclo + "/" + tse.eleicao + "/fotos/br/" + sq + ".jpeg";
    return FOTO.falhou[url] ? "" : url;
  }
  function foto(url, x, y, w, h) {
    return '<g>' + r(x, y, w, h, C.trilho, 3) + '<image href="' + esc(url) + '" x="' + x + '" y="' + y + '" width="' + w +
      '" height="' + h + '" preserveAspectRatio="xMidYMid slice" onload="__gctseFotoR(this,true)" onerror="__gctseFotoR(this,false)"/></g>';
  }

  function painelCargo(x, y, w, h, titulo, urnas, faixa, linhas, v) {
    var o = r(x, y, w, h, C.painel, 8), px = x + (v ? 22 : 24), pw = w - (v ? 44 : 48);
    if (faixa) o += r(x, y, w, 6, faixa.cor, 3);
    o += t(px, y + (v ? 38 : 46), titulo, { s: v ? 20 : 24, b: true, ls: 2 });
    o += t(x + w - (v ? 22 : 24), y + (v ? 64 : 80), "urnas " + pct(urnas), { s: v ? 13 : 15, c: C.apagado, a: "end" });
    if (faixa) o += t(px, y + (v ? 64 : 80), faixa.texto, { s: v ? 15 : 18, b: true, ls: 2, c: faixa.corTexto });
    var ly = y + (v ? 78 : 100), passo = Math.min(v ? 78 : 118, (y + h - ly - 8) / Math.max(1, linhas.length));
    if (!linhas.length) o += t(px, ly + 30, "aguardando boletim do TSE", { s: v ? 15 : 18, c: C.apagado });
    var top = linhas.length && linhas[0].pct > 0 ? linhas[0].pct : 100;
    linhas.forEach(function (L, i) {
      var yy = ly + i * passo, dx = 0;
      if (L.foto) {
        var fh = v ? 58 : 76, fw = fh * 3 / 4;
        o += foto(L.foto, px, yy + (v ? 6 : 8), fw, fh);
        dx = fw + (v ? 12 : 14);
      }
      o += t(px + dx, yy + (v ? 26 : 34), L.nome, { s: v ? 22 : 28, b: true, max: pw - dx, nome: true });
      o += t(px + dx, yy + (v ? 48 : 62), L.partido, { s: v ? 13 : 16, c: C.apagado, max: pw - dx - 120 });
      o += t(px + pw, yy + (v ? 48 : 62), pct(L.pct), { s: v ? 20 : 26, b: true, a: "end" });
      o += barra(px + dx, yy + (v ? 56 : 74), pw - dx, v ? 8 : 10, (L.pct || 0) / top * 0.98, L.cor);
    });
    return o;
  }
  function faixaCargo(c) {
    var s = situacao(c);
    if (s === "eleito") {
      var n = c.candidatos.filter(function (k) { return k.eleito; }).length;
      return { texto: n > 1 ? "ELEITOS" : "ELEITO", cor: C.verde, corTexto: "#3fd13f" };
    }
    if (s === "segundo") return { texto: "VAI AO 2º TURNO", cor: C.azul, corTexto: "#5fb0f0" };
    if (s === "andamento") return { texto: "EM APURAÇÃO", cor: C.neutro, corTexto: C.apagado };
    return { texto: "AGUARDANDO", cor: C.trilho, corTexto: C.apagado };
  }
  function linhasCargo(c, n, u) {
    if (!c) return [];
    return c.candidatos.slice(0, n).map(function (k) {
      return { foto: u ? urlFoto(u, k) : "", nome: k.nome, partido: k.partido + (k.eleito ? "  ·  ELEITO" : k.segundo_turno ? "  ·  2º TURNO" : ""),
        pct: k.pct, cor: k.eleito ? C.verde : k.segundo_turno ? C.azul : C.neutro };
    });
  }
  function telaEstado(v) {
    var u = ufDestaque(), W = v ? 540 : 1280, H = v ? 960 : 720;
    var g = cargo(u, "gov"), se = cargo(u, "sen"), p = presUf(u);
    var o = cab(v, W, NOMES[u], "Presidente, Governador e Senado no estado", seloEstados());
    var lp = p ? p.candidatos.slice(0, v ? 2 : 3).map(function (k) {
      return { foto: urlFotoP(k), nome: k.nome, partido: k.partido + "  ·  % dos válidos", pct: k.pct, cor: corCand(k) };
    }) : [];
    var up = p && p.secoes ? p.secoes.pct : null;
    if (!v) {
      o += painelCargo(73, 146, 365, 528, "PRESIDENTE", up, null, lp, false);
      o += painelCargo(454, 146, 365, 528, "GOVERNADOR", g ? g.urnas_pct : null, faixaCargo(g), linhasCargo(g, 2, u), false);
      o += painelCargo(835, 146, 365, 528, "SENADO", se ? se.urnas_pct : null, faixaCargo(se), linhasCargo(se, 2, u), false);
    } else {
      o += painelCargo(30, 146, W - 60, 248, "PRESIDENTE", up, null, lp, true);
      o += painelCargo(30, 404, W - 60, 248, "GOVERNADOR", g ? g.urnas_pct : null, faixaCargo(g), linhasCargo(g, 2, u), true);
      o += painelCargo(30, 662, W - 60, 268, "SENADO", se ? se.urnas_pct : null, faixaCargo(se), linhasCargo(se, 2, u), true);
    }
    o += rodape(v, W, H, "Fonte: TSE");
    return svg(W, H, o);
  }

  // ===================================================== 7. 2026 x 2022
  // 2022 vem dos arquivos do PROPRIO TSE (estados.ps1). Sem eles, a tela diz
  // que nao estao disponiveis - nunca um numero digitado.
  function comparativo(v) {
    var W = v ? 540 : 1280, H = v ? 960 : 720, ref = E().ref2022, b = P().br;
    var o = cab(v, W, "2026 × 2022", "Presidente · Brasil · 1º turno", seloPresidente());
    var x0 = v ? 30 : 73, x1 = v ? W - 30 : 1207;
    if (!ref) {
      o += t(x0, v ? 220 : 220, "Os números de 2022 ainda não foram encontrados", { s: v ? 20 : 30, b: true, max: x1 - x0 });
      o += t(x0, v ? 252 : 262, "nos arquivos do TSE. A tela completa sozinha quando eles chegarem.", { s: v ? 15 : 20, c: C.apagado, max: x1 - x0 });
      return svg(W, H, o + rodape(v, W, H, "Fonte: TSE"));
    }
    var tem = b && b.tem, e = tem ? b.eleitorado : null, vt = tem ? b.votos : null;
    var linhas = [
      ["COMPARECIMENTO", e ? e.pct_comparec : null, ref.pct_comparec],
      ["ABSTENÇÃO", e ? e.pct_abstencao : null, ref.pct_abstencao],
      ["BRANCOS", vt ? vt.pct_brancos : null, ref.pct_brancos],
      ["NULOS", vt ? vt.pct_nulos : null, ref.pct_nulos]
    ];
    var urn = tem && b.secoes ? b.secoes.pct : null;
    var y0 = v ? 150 : 140, passo = v ? 190 : 128;
    linhas.forEach(function (L, i) {
      var yy = y0 + i * passo, max = Math.max(L[1] || 0, L[2] || 0) / 0.9 || 1;
      o += r(x0, yy, x1 - x0, passo - 12, C.painel, 6);
      var lx = x0 + 20, bx = v ? lx : x0 + 330, bw = (x1 - 20) - bx - (v ? 110 : 130);
      o += t(lx, yy + (v ? 34 : 50), L[0], { s: v ? 20 : 24, b: true, ls: 1, max: v ? 300 : 290 });
      [["2026", L[1], C.azul], ["2022", L[2], C.neutro]].forEach(function (q, j) {
        var ly = yy + (v ? 52 : 26) + j * (v ? 56 : 46);
        o += t(bx, ly + 18, q[0], { s: v ? 15 : 17, b: true, c: C.apagado });
        o += barra(bx + 56, ly + 6, bw - 56, v ? 14 : 18, (q[1] || 0) / max, q[2]);
        o += t(x1 - 20, ly + 20, q[1] == null ? "—" : pct(q[1]), { s: v ? 20 : 24, b: true, a: "end" });
      });
    });
    o += rodape(v, W, H, "Fonte: TSE · 2022: totalização final do 1º turno · 2026: urnas já apuradas (" + pct(urn) + ")");
    return svg(W, H, o);
  }

  // -------------------------------------------------------------- ajustes
  function ajustar(raiz) {
    var ms = raiz.querySelectorAll("text[data-max]");
    for (var j = 0; j < ms.length; j++) {
      var max = parseFloat(ms[j].getAttribute("data-max")), lg = ms[j].getComputedTextLength();
      if (lg <= max) continue;
      var cur = ms[j].getAttribute("data-curto");
      if (cur) { ms[j].textContent = cur; lg = ms[j].getComputedTextLength(); if (lg <= max) continue; }
      var fs0 = parseFloat(ms[j].getAttribute("font-size")), fs = Math.max(Math.floor(fs0 * max / lg), Math.ceil(fs0 * (cur != null ? 0.6 : 0.7)));
      ms[j].setAttribute("font-size", fs);
      var txt = ms[j].textContent;
      while (ms[j].getComputedTextLength() > max && txt.length > 4) { txt = txt.slice(0, -1); ms[j].textContent = txt.replace(/\s+$/, "") + "…"; }
    }
    var gs = raiz.querySelectorAll("g[data-selo]");
    for (var i = 0; i < gs.length; i++) {
      var tx = gs[i].querySelector("text"), rc = gs[i].querySelector("rect");
      var w = tx.getComputedTextLength() + 18, xd = parseFloat(gs[i].getAttribute("data-x"));
      rc.setAttribute("x", (xd - w).toFixed(1)); rc.setAttribute("width", w.toFixed(1));
      tx.setAttribute("x", (xd - 9).toFixed(1));
    }
  }

  window.GCTSE_RESUMO = {
    definirUf: function (u) { u = String(u == null ? "" : u).toLowerCase(); if (!NOMES[u]) return false; UF_ESCOLHIDA = u; return true; },
    ufAtual: function () { return ufDestaque(); },
    telas: [
      { id: "mapa-governadores", f: mapaGov },
      { id: "governadores-partido", f: govPartido },
      { id: "senado-partido", f: senPartido },
      { id: "presidente-regiao", f: presRegiao },
      { id: "comparecimento", f: comparecimento },
      { id: "estado", f: telaEstado },
      { id: "comparativo-2022", f: comparativo }
    ],
    ajustar: ajustar
  };
})();
