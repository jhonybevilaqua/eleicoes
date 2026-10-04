// Controle do RESUMO: qual tela esta no ar e como trocar.
//   seta direita / clique / roda p/ baixo / passador ... proxima tela
//   seta esquerda / botao direito / roda p/ cima ....... anterior
//   1 a 7 ... vai direto      Home ... primeira      ENTER ... giro automatico
(function () {
  "use strict";
  var R = window.GCTSE_RESUMO, cfg = window.GCTSE_GIRO || {};
  var q = new URLSearchParams(location.search);
  var vertical = (q.get("f") || window.GCTSE_FORMATO) === "v";
  var telas = R.telas;
  var tempoAuto = parseFloat(cfg.tempo_auto_segundos);
  if (!(tempoAuto >= 3)) tempoAuto = 10;
  var transicao = parseFloat(cfg.transicao_segundos);
  if (!(transicao >= 0)) transicao = 0.5;

  var CHAVE = "gctse-resumo-" + (vertical ? "v" : "h"), atual = 0;
  var pedida = q.get("tela");
  if (pedida == null) { try { pedida = localStorage.getItem(CHAVE); } catch (e) { } }
  telas.forEach(function (tl, i) { if (tl.id === pedida) atual = i; });

  var camadas = [document.getElementById("c0"), document.getElementById("c1")];
  camadas.forEach(function (c) { c.style.transition = "opacity " + transicao + "s ease-in-out"; });
  var visivel = 0, chaveDados = "", auto = false, timer = null;

  function chave() { return JSON.stringify([window.GCTSE_ESTADOS && window.GCTSE_ESTADOS.ufs, window.GCTSE_ESTADOS && window.GCTSE_ESTADOS.ref2022, window.GCTSE_DADOS && window.GCTSE_DADOS.ufs, window.GCTSE_DADOS && window.GCTSE_DADOS.br]); }
  function desenharEm(camada, i) { camada.innerHTML = telas[i].f(vertical); R.ajustar(camada); }
  function mostrar(i) {
    atual = (i + telas.length) % telas.length;
    var prox = camadas[1 - visivel];
    desenharEm(prox, atual);
    prox.classList.add("on"); camadas[visivel].classList.remove("on");
    visivel = 1 - visivel; chaveDados = chave();
    try { localStorage.setItem(CHAVE, telas[atual].id); } catch (e) { }
  }
  function reagendar() { clearTimeout(timer); if (auto) timer = setTimeout(function () { mostrar(atual + 1); reagendar(); }, tempoAuto * 1000); }
  function proximo() { mostrar(atual + 1); reagendar(); }
  function anterior() { mostrar(atual - 1); reagendar(); }

  // Le os dois arquivos de dados de novo a cada 3 s e redesenha se mudou.
  function recarregar(arq) {
    var sc = document.createElement("script");
    sc.charset = "utf-8"; sc.src = arq + "?t=" + Date.now();
    sc.onload = function () { sc.remove(); if (chave() !== chaveDados) { chaveDados = chave(); desenharEm(camadas[visivel], atual); } };
    sc.onerror = function () { sc.remove(); };
    document.head.appendChild(sc);
  }

  var aviso = document.getElementById("aviso"), tAviso = null;
  function avisar(txt) { aviso.textContent = txt; aviso.style.opacity = 1; clearTimeout(tAviso); tAviso = setTimeout(function () { aviso.style.opacity = 0; }, 1400); }

  document.addEventListener("keydown", function (e) {
    var k = e.key;
    if (k === "ArrowRight" || k === "ArrowDown" || k === "PageDown" || k === " ") { proximo(); e.preventDefault(); return; }
    if (k === "ArrowLeft" || k === "ArrowUp" || k === "PageUp" || k === "Backspace") { anterior(); e.preventDefault(); return; }
    if (k === "Home") { mostrar(0); reagendar(); return; }
    if (k === "Enter") { auto = !auto; avisar(auto ? "GIRO AUTOMÁTICO" : "GIRO MANUAL"); reagendar(); return; }
    if (/^[1-9]$/.test(k) && +k <= telas.length) { mostrar(+k - 1); reagendar(); }
  });
  document.addEventListener("click", proximo);
  document.addEventListener("contextmenu", function (e) { e.preventDefault(); anterior(); });
  var ultimaRoda = 0;
  document.addEventListener("wheel", function (e) {
    var agora = Date.now(); if (agora - ultimaRoda < 400) return; ultimaRoda = agora;
    if (e.deltaY > 0) proximo(); else anterior();
  }, { passive: true });

  mostrar(atual);
  setInterval(function () { recarregar("estados.js"); recarregar("dados.js"); }, 3000);
  window.GCTSE_RESUMO_CONTROLE = { atual: function () { return telas[atual].id; }, proximo: proximo };
})();
