// Controle do GIRO: qual estado esta na tela e como trocar.
(function () {
  "use strict";
  var cfg = window.GCTSE_GIRO || {};
  var T = window.GCTSE_GIRO_TELA;
  var q = new URLSearchParams(location.search);
  var formato = q.get("f") || window.GCTSE_FORMATO || "h";
  if (formato !== "v") formato = "h";

  var ordem = (cfg.ordem || []).map(function (u) { return String(u).toLowerCase().trim(); })
    .filter(function (u) { return T.nomes[u]; });
  if (!ordem.length) ordem = Object.keys(T.nomes);
  var transicao = parseFloat(cfg.transicao_segundos);
  if (!(transicao >= 0)) transicao = 0.5;
  var tempoAuto = parseFloat(cfg.tempo_auto_segundos);
  if (!(tempoAuto >= 3)) tempoAuto = 10;

  // Estado inicial: ?uf=pr, senao o ultimo mostrado (lembrado neste PC).
  var CHAVE = "gctse-giro-uf-" + formato;
  var atual = 0, inicial = (q.get("uf") || "").toLowerCase();
  if (!inicial) { try { inicial = localStorage.getItem(CHAVE) || ""; } catch (e) { } }
  if (ordem.indexOf(inicial) >= 0) atual = ordem.indexOf(inicial);

  var camadas = [document.getElementById("c0"), document.getElementById("c1")];
  camadas.forEach(function (c) { c.style.transition = "opacity " + transicao + "s ease-in-out"; });
  var visivel = 0, chaveDados = "", auto = false, timerAuto = null;

  function desenharEm(camada, u) {
    camada.innerHTML = formato === "v" ? T.telaV(u) : T.telaH(u);
    T.ajustar(camada);
  }
  function chave() { return JSON.stringify([T.dados().modo, T.dados().ufs]); }

  function mostrar(i) {
    atual = (i + ordem.length) % ordem.length;
    var prox = camadas[1 - visivel];
    desenharEm(prox, ordem[atual]);
    prox.classList.add("on");
    camadas[visivel].classList.remove("on");
    visivel = 1 - visivel;
    chaveDados = chave();
    try { localStorage.setItem(CHAVE, ordem[atual]); } catch (e) { }
    document.title = "GIRO - " + ordem[atual].toUpperCase();
  }
  function proximo() { mostrar(atual + 1); reagendar(); }
  function anterior() { mostrar(atual - 1); reagendar(); }
  function reagendar() {
    clearTimeout(timerAuto);
    if (auto) timerAuto = setTimeout(proximo, tempoAuto * 1000);
  }

  // Dado novo: redesenha o estado que esta na tela, sem piscar.
  function recarregar() {
    var sc = document.createElement("script");
    sc.charset = "utf-8";
    sc.src = "estados.js?t=" + Date.now();
    sc.onload = function () {
      sc.remove();
      if (chave() !== chaveDados) { chaveDados = chave(); desenharEm(camadas[visivel], ordem[atual]); }
    };
    sc.onerror = function () { sc.remove(); };
    document.head.appendChild(sc);
  }

  // Aviso curto (so quando o operador aperta algo que nao e troca de estado).
  var aviso = document.getElementById("aviso"), tAviso = null;
  function avisar(txt) {
    aviso.textContent = txt; aviso.style.opacity = 1;
    clearTimeout(tAviso); tAviso = setTimeout(function () { aviso.style.opacity = 0; }, 1400);
  }

  // Digitar a sigla: duas letras em ate 1,5 s (ex.: P depois R = Parana).
  var buf = "", tBuf = null;
  document.addEventListener("keydown", function (e) {
    var k = e.key;
    if (k === "ArrowRight" || k === "ArrowDown" || k === "PageDown" || k === " ") { proximo(); e.preventDefault(); return; }
    if (k === "ArrowLeft" || k === "ArrowUp" || k === "PageUp" || k === "Backspace") { anterior(); e.preventDefault(); return; }
    if (k === "Home") { mostrar(0); reagendar(); return; }
    if (k === "End") { mostrar(ordem.length - 1); reagendar(); return; }
    if (k === "Enter") { auto = !auto; avisar(auto ? "GIRO AUTOMÁTICO" : "GIRO MANUAL"); reagendar(); return; }
    if (/^[a-zA-Z]$/.test(k)) {
      buf = (buf + k.toLowerCase()).slice(-2);
      clearTimeout(tBuf); tBuf = setTimeout(function () { buf = ""; }, 1500);
      if (buf.length === 2 && ordem.indexOf(buf) >= 0) { mostrar(ordem.indexOf(buf)); reagendar(); buf = ""; }
    }
  });
  document.addEventListener("click", function () { proximo(); });
  document.addEventListener("contextmenu", function (e) { e.preventDefault(); anterior(); });
  var ultimaRoda = 0;
  document.addEventListener("wheel", function (e) {
    var agora = Date.now();
    if (agora - ultimaRoda < 400) return;     // uma volta da roda = um estado
    ultimaRoda = agora;
    if (e.deltaY > 0) proximo(); else anterior();
  }, { passive: true });

  mostrar(atual);
  setInterval(recarregar, 3000);
  // Comandos vindos do GERENCIADOR (sem aviso na tela: a saida esta no ar).
  window.GCTSE_GIRO_CONTROLE = {
    atual: function () { return ordem[atual]; }, proximo: proximo, anterior: anterior,
    redesenhar: function () { desenharEm(camadas[visivel], ordem[atual]); },
    irPara: function (uf) { var i = ordem.indexOf(String(uf).toLowerCase()); if (i >= 0) { mostrar(i); reagendar(); } },
    alternarAuto: function () { auto = !auto; reagendar(); return auto; }
  };
})();
