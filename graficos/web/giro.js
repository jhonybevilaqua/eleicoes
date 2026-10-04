// gctse GRAFICOS - GIRO DOS ESTADOS: Governador e Senador de UM estado por
// vez, com ELEITO / 2o TURNO como o TSE escreve. Troca de estado na mao:
//   seta direita, PageDown, espaco, clique, roda do mouse p/ baixo -> proximo
//   seta esquerda, PageUp, botao direito, roda p/ cima ............ anterior
//   Home ......... primeiro estado     digitar a sigla (P, R) .... vai direto
//   ENTER ........ liga/desliga o giro automatico
// Dados: web\estados.js, gravado pelo ESTADOS.bat. Nada aqui inventa numero.
(function () {
  "use strict";

  var C = {
    fundo: "#0b1220", texto: "#ffffff", apagado: "#8ea3bd", apagado2: "#6b7f99",
    trilho: "#283548", painel: "#121b2b", vermelho: "#d03b3b", verde: "#0ca30c",
    destaque: "#2f8fdd", neutro: "#4d6282"
  };
  var FONTE = "'Segoe UI', 'DejaVu Sans', Arial, sans-serif";
  var NOMES = {
    ac: "ACRE", al: "ALAGOAS", ap: "AMAPÁ", am: "AMAZONAS", ba: "BAHIA", ce: "CEARÁ",
    df: "DISTRITO FEDERAL", es: "ESPÍRITO SANTO", go: "GOIÁS", ma: "MARANHÃO", mt: "MATO GROSSO",
    ms: "MATO GROSSO DO SUL", mg: "MINAS GERAIS", pa: "PARÁ", pb: "PARAÍBA", pr: "PARANÁ",
    pe: "PERNAMBUCO", pi: "PIAUÍ", rj: "RIO DE JANEIRO", rn: "RIO GRANDE DO NORTE",
    rs: "RIO GRANDE DO SUL", ro: "RONDÔNIA", rr: "RORAIMA", sc: "SANTA CATARINA",
    sp: "SÃO PAULO", se: "SERGIPE", to: "TOCANTINS"
  };

  // ------------------------------------------------------------- utilidades
  function esc(t) {
    return String(t == null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pct(v) { return (v == null || isNaN(v)) ? "—" : Number(v).toFixed(2).replace(".", ",") + "%"; }
  function t(x, y, txt, o) {
    o = o || {};
    return '<text x="' + x + '" y="' + y + '" font-size="' + (o.s || 16) + '"' +
      (o.b ? ' font-weight="700"' : "") + ' fill="' + (o.c || C.texto) + '"' +
      (o.a ? ' text-anchor="' + o.a + '"' : "") + (o.ls ? ' letter-spacing="' + o.ls + '"' : "") +
      (o.max ? ' data-max="' + o.max + '"' : "") + ">" + esc(txt) + "</text>";
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

  // ------------------------------------------------------------------ dados
  function D() { return window.GCTSE_ESTADOS || { modo: "OFICIAL", ufs: {} }; }
  function cargo(u, qual) {
    var e = (D().ufs || {})[u], c = e && e[qual];
    if (!c || !c.tem) return null;
    c.candidatos = lista(c.candidatos);
    return c;
  }

  // Situacao do cargo, so com o que o TSE escreveu.
  function situacao(c) {
    if (!c) return { tipo: "vazio", texto: "AGUARDANDO O TSE" };
    var cs = c.candidatos, eleitos = cs.filter(function (x) { return x.eleito; }),
      segundo = cs.filter(function (x) { return x.segundo_turno; });
    if (eleitos.length) return { tipo: "eleito", lista: eleitos };
    if (segundo.length) return { tipo: "segundo", lista: segundo };
    if (!(c.urnas_pct > 0)) return { tipo: "vazio", texto: "AGUARDANDO APURAÇÃO" };
    return { tipo: "andamento", texto: "EM APURAÇÃO" };
  }

  function selo(u) {
    var g = cargo(u, "gov"), s = cargo(u, "sen");
    if (D().modo === "SIMULADO") return { texto: "SIMULADO — NÃO OFICIAL", cor: C.vermelho };
    if (g && s && g.andamento === "f" && s.andamento === "f") return { texto: "TOTALIZAÇÃO FINAL", cor: C.verde };
    var pg = g ? g.urnas_pct : 0, ps = s ? s.urnas_pct : 0;
    if (!(pg > 0) && !(ps > 0)) return { texto: "AGUARDANDO APURAÇÃO", cor: C.trilho };
    return { texto: "PARCIAL", cor: C.vermelho };
  }
  function hora(u) {
    var g = cargo(u, "gov"), s = cargo(u, "sen"), h = (g && g.hora) || (s && s.hora) || "";
    h = String(h).slice(0, 5);
    return h ? "atualizado às " + h + " (horário do TSE)" : "aguardando o primeiro boletim";
  }

  // --------------------------------------------------- foto oficial do TSE
  // Direto do TSE, sem pasta: {base}/{ciclo}/{eleicao}/fotos/{uf}/{sqcand}.jpeg.
  // Foto que o TSE nao tiver some e nao e pedida de novo. Se as 3 primeiras
  // falharem sem nenhum acerto, as fotos desligam (404 em excesso pode
  // bloquear o IP, avisa o TSE).
  var FOTO = { falhou: {}, falhas: 0, acertos: 0 };
  window.__gctseFoto = function (img, ok) {
    var url = img.getAttribute("href");
    if (ok) { FOTO.acertos++; return; }
    if (!FOTO.falhou[url]) { FOTO.falhou[url] = true; FOTO.falhas++; }
    var g = img.parentNode; if (g && g.parentNode) g.parentNode.removeChild(g);
    if (window.GCTSE_GIRO_CONTROLE && window.GCTSE_GIRO_CONTROLE.redesenhar) {
      clearTimeout(FOTO.timer); FOTO.timer = setTimeout(window.GCTSE_GIRO_CONTROLE.redesenhar, 300);
    }
  };
  function urlFoto(u, cd) {
    if ((window.GCTSE_GIRO || {}).fotos_do_tse === false) return "";
    var tse = D().tse;
    if (!tse || !tse.base || !cd || !cd.sqcand) return "";
    if (FOTO.falhas >= 3 && FOTO.acertos === 0) return "";
    var url = tse.base + "/" + tse.ciclo + "/" + tse.eleicao + "/fotos/" + u + "/" + cd.sqcand + ".jpeg";
    return FOTO.falhou[url] ? "" : url;
  }
  function foto(url, x, y, w, h) {
    return '<g>' + r(x, y, w, h, C.trilho, 4) + '<image href="' + esc(url) + '" x="' + x + '" y="' + y + '" width="' + w +
      '" height="' + h + '" preserveAspectRatio="xMidYMid slice" onload="__gctseFoto(this,true)" onerror="__gctseFoto(this,false)"/></g>';
  }

  // ---------------------------------------------------------- um cargo (bloco)
  // Layout "so o resultado": com ELEITO ou 2o TURNO definido pelo TSE, so os
  // nomes em destaque. Sem resultado ainda, os 2 primeiros com percentual e
  // barra. k = escala (1 na horizontal; menor no painel da vertical).
  function rotulo(sit) {
    if (sit.tipo === "eleito") return sit.lista.length > 1 ? "ELEITOS" : "ELEITO";
    if (sit.tipo === "segundo") return "2º TURNO";
    return sit.texto;
  }
  function chip(xd, y, sit, k) {
    var txt = sit.tipo === "vazio" ? "AGUARDANDO" : rotulo(sit), w = (txt.length * 13 + 30) * k, h = 34 * k;
    var cor = sit.tipo === "eleito" ? C.verde : (sit.tipo === "segundo" ? C.destaque : C.trilho);
    return r(xd - w, y - 25 * k, w, h, cor, 4) + t(xd - w / 2, y - 1 * k, txt, { s: Math.round(18 * k), b: true, a: "middle", ls: 1 });
  }
  function emApuracao(x, y, w, h, titulo, c, sit, k) {
    var o = r(x, y, w, h, C.painel, 8), px = x + 32 * k, pw = w - 64 * k;
    o += t(px, y + 52 * k, titulo, { s: Math.round(28 * k), b: true, ls: 2 });
    o += chip(x + w - 32 * k, y + 52 * k, sit, k);
    var cs = c ? c.candidatos.slice(0, 2) : [];
    if (!cs.length) return o + t(px, y + 140 * k, "aguardando boletim do TSE", { s: Math.round(22 * k), c: C.apagado });
    var top = cs[0].pct > 0 ? cs[0].pct : 100, ly = y + 110 * k, passo = Math.min(170 * k, (y + h - ly - 10) / 2);
    cs.forEach(function (cd, i) {
      var yy = ly + i * passo;
      o += t(px, yy + 40 * k, cd.nome, { s: Math.round(36 * k), b: true, max: pw - 215 * k });
      o += t(px, yy + 74 * k, cd.partido, { s: Math.round(22 * k), c: C.apagado, max: pw - 215 * k });
      o += t(px + pw, yy + 52 * k, pct(cd.pct), { s: Math.round(46 * k), b: true, a: "end" });
      o += barra(px, yy + 94 * k, pw, Math.round(12 * k), (cd.pct || 0) / top * 0.98, C.neutro);
    });
    return o;
  }
  function bloco(x, y, w, h, titulo, c, k, u) {
    var sit = situacao(c);
    if (sit.tipo !== "eleito" && sit.tipo !== "segundo") return emApuracao(x, y, w, h, titulo, c, sit, k);
    var eleito = sit.tipo === "eleito", cor = eleito ? C.verde : C.destaque;
    var o = r(x, y, w, h, C.painel, 8) + r(x, y, w, 8, cor, 4), px = x + 32 * k, pw = w - 64 * k;
    o += t(px, y + 54 * k, titulo, { s: Math.round(28 * k), b: true, ls: 2 });
    o += t(px, y + 104 * k, eleito ? rotulo(sit) : "VÃO AO 2º TURNO",
      { s: Math.round(26 * k), b: true, ls: 3, c: eleito ? "#3fd13f" : "#5fb0f0" });
    var lst = sit.lista.slice(0, 2), passo = (lst.length > 1 ? 150 : 200) * k;
    lst.forEach(function (cd, i) {
      var yy = y + 130 * k + i * passo, url = urlFoto(u, cd), dx = 0;
      if (url) {
        var fw = (lst.length > 1 ? 84 : 120) * k, fh = fw * 4 / 3;
        o += foto(url, px, yy + 14 * k, fw, fh);
        dx = fw + 20 * k;
      }
      o += t(px + dx, yy + 56 * k, cd.nome, { s: Math.round((lst.length > 1 ? 44 : 54) * k), b: true, max: pw - dx });
      o += t(px + dx, yy + 96 * k, cd.partido + "   " + pct(cd.pct), { s: Math.round(28 * k), c: C.apagado, max: pw - dx });
    });
    return o;
  }

  // ------------------------------------------------------------------ telas
  function telaH(u) {
    var W = 1280, H = 720, s = selo(u), o = r(0, 0, W, H, C.fundo);
    var g = cargo(u, "gov"), se = cargo(u, "sen");
    o += t(73, 76, NOMES[u] || u.toUpperCase(), { s: 52, b: true, ls: 1, max: W - 73 - 380 });
    o += t(73, 112, "urnas apuradas  ·  governador " + (g ? pct(g.urnas_pct) : "—") +
      "  ·  senador " + (se ? pct(se.urnas_pct) : "—"), { s: 20, c: C.apagado });
    o += '<g data-selo="1" data-x="' + (W - 73) + '">' + r(W - 340, 44, 267, 36, s.cor, 3) +
      t(W - 81, 70, s.texto, { s: 20, b: true, a: "end" }) + "</g>";
    o += bloco(73, 146, 551, 528, "GOVERNADOR", g, 1, u);
    o += bloco(656, 146, 551, 528, "SENADOR", se, 1, u);
    o += t(73, 702, "Fonte: TSE — " + hora(u), { s: 13, c: C.apagado2 });
    return svg(W, H, o);
  }
  function telaV(u) {
    var W = 540, H = 960, s = selo(u), o = r(0, 0, W, H, C.fundo);
    var g = cargo(u, "gov"), se = cargo(u, "sen");
    o += t(30, 66, NOMES[u] || u.toUpperCase(), { s: 38, b: true, max: W - 60 });
    o += t(30, 94, "urnas  ·  gov " + (g ? pct(g.urnas_pct) : "—") + "  ·  sen " + (se ? pct(se.urnas_pct) : "—"),
      { s: 15, c: C.apagado, max: W - 60 });
    o += r(30, 108, W - 60, 28, s.cor, 2) + t(W / 2, 128, s.texto, { s: 16, b: true, a: "middle" });
    o += bloco(30, 150, W - 60, 380, "GOVERNADOR", g, 0.78, u);
    o += bloco(30, 546, W - 60, 380, "SENADOR", se, 0.78, u);
    o += t(30, 950, "Fonte: TSE — " + hora(u), { s: 11, c: C.apagado2 });
    return svg(W, H, o);
  }
  function svg(W, H, corpo) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + W + " " + H + '" width="' + W + '" height="' + H +
      '" font-family="' + FONTE + '">' + corpo + "</svg>";
  }

  // Texto comprido encolhe para caber; o selo cresce com o texto.
  function ajustar(raiz) {
    var ms = raiz.querySelectorAll("text[data-max]");
    for (var j = 0; j < ms.length; j++) {
      var max = parseFloat(ms[j].getAttribute("data-max")), lg = ms[j].getComputedTextLength();
      if (lg <= max) continue;
      // Encolhe ate 70% do tamanho; se ainda nao couber, corta com "…"
      // (nome ilegivel no ar e pior que nome cortado).
      var fs0 = parseFloat(ms[j].getAttribute("font-size")), fs = Math.max(Math.floor(fs0 * max / lg), Math.ceil(fs0 * 0.7));
      ms[j].setAttribute("font-size", fs);
      var txt = ms[j].textContent;
      while (ms[j].getComputedTextLength() > max && txt.length > 4) {
        txt = txt.slice(0, -1); ms[j].textContent = txt.replace(/\s+$/, "") + "…";
      }
    }
    var gs = raiz.querySelectorAll("g[data-selo]");
    for (var i = 0; i < gs.length; i++) {
      var tx = gs[i].querySelector("text"), rc = gs[i].querySelector("rect");
      var w = tx.getComputedTextLength() + 18, xd = parseFloat(gs[i].getAttribute("data-x"));
      rc.setAttribute("x", (xd - w).toFixed(1)); rc.setAttribute("width", w.toFixed(1));
      tx.setAttribute("x", (xd - 9).toFixed(1));
    }
  }

  window.GCTSE_GIRO_TELA = { telaH: telaH, telaV: telaV, ajustar: ajustar, nomes: NOMES, dados: D };
})();
