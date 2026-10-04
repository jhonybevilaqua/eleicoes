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
  function inteiro(v) {
    if (v == null || isNaN(v)) return "—";
    return Math.round(v).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  }
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

  // ---------------------------------------------------------- um cargo (bloco)
  // Faixa de situacao + lista dos primeiros colocados.
  function bloco(x, y, w, h, titulo, c, qtd, vagas, compacto) {
    var o = r(x, y, w, h, C.painel, 8);
    var px = x + 28, pw = w - 56;
    o += t(px, y + 46, titulo, { s: compacto ? 22 : 26, b: true, ls: compacto ? 1 : 2 });
    o += t(x + w - 28, y + 46, c ? (compacto ? "urnas " : "urnas apuradas ") + pct(c.urnas_pct) : "", { s: compacto ? 15 : 17, c: C.apagado, a: "end" });

    // Faixa: ELEITO (verde) / 2o TURNO (azul) / em apuracao (cinza)
    var st = situacao(c), fy = y + 66, fh = 64, cor = C.trilho, l1 = "", l2 = "";
    if (st.tipo === "eleito") {
      cor = C.verde;
      l1 = st.lista.length > 1 ? "ELEITOS" : "ELEITO";
      l2 = st.lista.map(function (k) { return k.nome; }).join("  e  ");
    } else if (st.tipo === "segundo") {
      cor = C.destaque;
      l1 = "2º TURNO";
      l2 = st.lista.map(function (k) { return k.nome; }).join("  ×  ");
    } else {
      l1 = st.texto;
      l2 = vagas > 1 && c ? vagas + " vagas" : "";
    }
    o += r(px, fy, pw, fh, cor, 6);
    o += t(px + 18, fy + 26, l1, { s: 17, b: true, ls: 2 });
    o += t(px + 18, fy + 52, l2, { s: 22, b: true, max: pw - 36 });

    // Candidatos: com poucos (2), tudo cresce para ocupar o painel.
    var cs = c ? c.candidatos.slice(0, qtd) : [];
    var top = cs.length && cs[0].pct > 0 ? cs[0].pct : 100;
    var ly = fy + fh + 30, passo = Math.min(160, (y + h - ly - 10) / Math.max(qtd, 1));
    var f = Math.max(1, Math.min(1.55, passo / 92));
    if (!cs.length) o += t(px, ly + 30, "aguardando boletim do TSE", { s: 20, c: C.apagado });
    cs.forEach(function (k, i) {
      var yy = ly + i * passo, corBarra = k.eleito ? C.verde : (k.segundo_turno ? C.destaque : C.neutro);
      var etq = k.eleito ? "ELEITO" : (k.segundo_turno ? "2º TURNO" : "");
      var ew = Math.round((etq === "ELEITO" ? 70 : 84) * f), eh = Math.round(20 * f);
      o += t(px, yy + 24 * f, k.nome, { s: Math.round(22 * f), b: true, max: pw - 150 * f });
      o += t(px, yy + 47 * f, k.partido + (k.numero ? "  ·  " + k.numero : ""), { s: Math.round(15 * f), c: C.apagado, max: pw - 160 * f - (etq ? ew + 16 : 0) });
      o += t(px + pw, yy + 28 * f, pct(k.pct), { s: Math.round(26 * f), b: true, a: "end" });
      o += t(px + pw, yy + 49 * f, inteiro(k.votos) + " votos", { s: Math.round(14 * f), c: C.apagado, a: "end" });
      if (etq) {
        var ex = px + pw - 150 * f - ew;
        o += r(ex, yy + 33 * f, ew, eh, corBarra, 3) +
          t(ex + ew / 2, yy + 33 * f + eh * 0.74, etq, { s: Math.round(12 * f), b: true, a: "middle" });
      }
      o += barra(px, yy + 60 * f, pw, Math.round(8 * f), (k.pct || 0) / top * 0.98, corBarra);
    });
    return o;
  }

  // ------------------------------------------------------------------ telas
  function telaH(u) {
    var W = 1280, H = 720, cfg = window.GCTSE_GIRO || {};
    var s = selo(u), o = r(0, 0, W, H, C.fundo);
    o += t(73, 44, "GOVERNADOR E SENADOR", { s: 18, b: true, ls: 3, c: C.apagado });
    o += t(73, 90, NOMES[u] || u.toUpperCase(), { s: 44, b: true, ls: 1, max: W - 73 - 380 });
    o += t(73, 118, hora(u), { s: 18, c: C.apagado });
    o += '<g data-selo="1" data-x="' + (W - 73) + '">' + r(W - 340, 52, 267, 34, s.cor, 3) +
      t(W - 81, 76, s.texto, { s: 19, b: true, a: "end" }) + "</g>";
    var g = cargo(u, "gov"), se = cargo(u, "sen");
    o += bloco(73, 146, 551, 528, "GOVERNADOR", g, cfg.candidatos_governador || 2, 1);
    o += bloco(656, 146, 551, 528, "SENADOR", se, cfg.candidatos_senador || 2, se ? se.vagas : 1);
    o += t(73, 702, "Fonte: TSE — Divulgação de Resultados", { s: 12, c: C.apagado2 });
    return svg(W, H, o);
  }
  function telaV(u) {
    var W = 540, H = 960, cfg = window.GCTSE_GIRO || {};
    var s = selo(u), o = r(0, 0, W, H, C.fundo);
    o += t(30, 42, "GOVERNADOR E SENADOR", { s: 15, b: true, ls: 2, c: C.apagado });
    o += t(30, 82, NOMES[u] || u.toUpperCase(), { s: 34, b: true, max: W - 60 });
    o += t(30, 106, hora(u), { s: 14, c: C.apagado });
    o += r(30, 118, W - 60, 26, s.cor, 2) + t(W / 2, 137, s.texto, { s: 15, b: true, a: "middle" });
    var g = cargo(u, "gov"), se = cargo(u, "sen");
    o += bloco(30, 156, W - 60, 382, "GOVERNADOR", g, Math.min(cfg.candidatos_governador || 2, 3), 1, true);
    o += bloco(30, 550, W - 60, 382, "SENADOR", se, Math.min(cfg.candidatos_senador || 2, 3), se ? se.vagas : 1, true);
    o += t(30, 950, "Fonte: TSE", { s: 11, c: C.apagado2 });
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
