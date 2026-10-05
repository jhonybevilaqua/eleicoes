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
    trilho: "#283548", painel: "rgba(8,14,32,0.78)", vermelho: "#d03b3b", verde: "#16b216",
    destaque: "#2b84ff", neutro: "#7398cf"
  };
  var FONTE = "'Segoe UI', 'DejaVu Sans', Arial, sans-serif";
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
    if (pg >= 100 && ps >= 100) return { texto: "100% DAS URNAS", cor: C.verde };
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
    // refaz a tela sem a foto (giro ou apresentacao, a que estiver aberta)
    var refazer = (window.GCTSE_GIRO_CONTROLE && window.GCTSE_GIRO_CONTROLE.redesenhar) || window.__gctseRedesenhar;
    if (refazer) { clearTimeout(FOTO.timer); FOTO.timer = setTimeout(refazer, 300); }
  };
  function urlFoto(u, cd) {
    if (window.GCTSE_FOTOS_DO_TSE !== true) return "";   // chave em web\fotos-config.js
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
  function emApuracao(x, y, w, h, titulo, c, sit, k, u) {
    var o = r(x, y, w, h, C.painel, 8), px = x + 32 * k, pw = w - 64 * k;
    o += t(px, y + 52 * k, titulo, { s: Math.round(28 * k), b: true, ls: 2 });
    o += chip(x + w - 32 * k, y + 52 * k, sit, k);
    var cs = c ? c.candidatos.slice(0, 2) : [];
    if (!cs.length) return o + t(px, y + 140 * k, "aguardando boletim do TSE", { s: Math.round(22 * k), c: C.apagado });
    var top = cs[0].pct > 0 ? cs[0].pct : 100, ly = y + 110 * k, passo = Math.min(170 * k, (y + h - ly - 10) / 2);
    cs.forEach(function (cd, i) {
      var yy = ly + i * passo, url = urlFoto(u, cd), dx = 0;
      if (url) {
        var fh = 94 * k, fw = fh * 3 / 4;
        o += foto(url, px, yy + 12 * k, fw, fh);
        dx = fw + 18 * k;
      }
      // nome na linha inteira; partido e percentual na linha de baixo
      o += t(px + dx, yy + 40 * k, cd.nome, { s: Math.round(36 * k), b: true, max: pw - dx, nome: true });
      o += t(px + dx, yy + 82 * k, cd.partido, { s: Math.round(22 * k), c: C.apagado, max: pw - dx - 200 * k });
      o += t(px + pw, yy + 84 * k, pct(cd.pct), { s: Math.round(40 * k), b: true, a: "end" });
      o += barra(px + dx, yy + 98 * k, pw - dx, Math.round(12 * k), (cd.pct || 0) / top * 0.98, C.neutro);
    });
    return o;
  }
  function bloco(x, y, w, h, titulo, c, k, u) {
    var sit = situacao(c);
    if (sit.tipo !== "eleito" && sit.tipo !== "segundo") return emApuracao(x, y, w, h, titulo, c, sit, k, u);
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
      o += t(px + dx, yy + 56 * k, cd.nome, { s: Math.round((lst.length > 1 ? 44 : 54) * k), b: true, max: pw - dx, nome: true });
      o += t(px + dx, yy + 96 * k, cd.partido + "   " + pct(cd.pct), { s: Math.round(28 * k), c: C.apagado, max: pw - dx });
    });
    return o;
  }

  // Linha pequena do cabecalho: urnas apuradas e comparecimento do estado
  // (Governador; Senador se o de Governador ainda nao veio).
  function linhaUrnas(g, se, curto) {
    var c = g || se;
    if (!c) return curto ? "aguardando o TSE" : "urnas apuradas —";
    var o = (curto ? "urnas " : "urnas apuradas ") + pct(c.urnas_pct);
    if (g && se && se.urnas_pct != null && Math.abs((se.urnas_pct || 0) - (g.urnas_pct || 0)) > 0.005)
      o = (curto ? "urnas gov " : "urnas apuradas  ·  governador ") + pct(g.urnas_pct) + (curto ? " · sen " : "  ·  senador ") + pct(se.urnas_pct);
    if (c.comparec_pct != null) o += (curto ? "  ·  comparec. " : "  ·  comparecimento ") + pct(c.comparec_pct);
    return o;
  }

  // ------------------------------------------------------------------ telas
  function telaH(u) {
    var W = 1280, H = 720, s = selo(u), o = "";
    var g = cargo(u, "gov"), se = cargo(u, "sen");
    o += t(73, 76, NOMES[u] || u.toUpperCase(), { s: 52, b: true, ls: 1, max: W - 73 - 580 });
    o += t(73, 112, linhaUrnas(g, se, false), { s: 20, c: C.apagado, max: W - 73 - 380 });
    o += '<g data-selo="1" data-x="' + (W - 73 - 200) + '">' + r(W - 540, 27, 267, 36, s.cor, 3) +
      t(W - 281, 52, s.texto, { s: 20, b: true, a: "end" }) + "</g>";
    o += bloco(73, 146, 551, 528, "GOVERNADOR", g, 1, u);
    o += bloco(656, 146, 551, 528, "SENADOR", se, 1, u);
    o += t(73, 702, "Fonte: TSE — " + hora(u), { s: 13, c: C.apagado2 });
    return svg(W, H, o);
  }
  function telaV(u) {
    var W = 540, H = 960, s = selo(u), o = "";
    var g = cargo(u, "gov"), se = cargo(u, "sen");
    o += t(30, 66, NOMES[u] || u.toUpperCase(), { s: 38, b: true, max: W - 60 });
    o += t(30, 94, linhaUrnas(g, se, true), { s: 15, c: C.apagado, max: W - 60 });
    o += r(30, 108, W - 60, 28, s.cor, 2) + t(W / 2, 128, s.texto, { s: 16, b: true, a: "middle" });
    o += bloco(30, 150, W - 60, 380, "GOVERNADOR", g, 0.78, u);
    o += bloco(30, 546, W - 60, 380, "SENADOR", se, 0.78, u);
    o += t(30, 950, "Fonte: TSE — " + hora(u), { s: 11, c: C.apagado2 });
    return svg(W, H, o);
  }
  function svg(W, H, corpo) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + W + " " + H + '" width="' + W + '" height="' + H +
      '" font-family="' + FONTE + '">' + r(0, 0, W, H, C.fundo) + arteFundo(W, H) + corpo + arteLogo(W, H, W > H ? 73 : 30) + "</svg>";
  }

  // Texto comprido encolhe para caber; o selo cresce com o texto.
  function ajustar(raiz) {
    var ms = raiz.querySelectorAll("text[data-max]");
    for (var j = 0; j < ms.length; j++) {
      var max = parseFloat(ms[j].getAttribute("data-max")), lg = ms[j].getComputedTextLength();
      if (lg <= max) continue;
      var cur = ms[j].getAttribute("data-curto");
      if (cur) { ms[j].textContent = cur; lg = ms[j].getComputedTextLength(); if (lg <= max) continue; }
      // Encolhe ate 70% do tamanho; se ainda nao couber, corta com "…"
      // (nome ilegivel no ar e pior que nome cortado).
      var fs0 = parseFloat(ms[j].getAttribute("font-size")), fs = Math.max(Math.floor(fs0 * max / lg), Math.ceil(fs0 * 0.6));
      ms[j].setAttribute("font-size", fs);
      // espacamento entre letras faz passar 1-2 px: desce de 1 em 1 ate caber
      while (ms[j].getComputedTextLength() > max && fs > Math.ceil(fs0 * 0.6)) { fs--; ms[j].setAttribute("font-size", fs); }
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
