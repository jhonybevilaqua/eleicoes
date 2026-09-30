// Apresentacao: troca de grafico a cada N segundos, em tela cheia.
// Usada por apresentacao-horizontal.html (1920x1080) e
// apresentacao-vertical.html (1080x1920). Os dados vem do mesmo dados.js
// que o GRAFICOS.bat grava; nada aqui inventa numero.
(function () {
  var cfg = window.GCTSE_APRESENTACAO || {};
  var q = new URLSearchParams(location.search);
  var formato = q.get("f") || window.GCTSE_FORMATO || "h";
  if (formato !== "v") formato = "h";

  var tempo = parseFloat(q.get("tempo") || cfg.tempo_segundos);
  if (!(tempo >= 3)) tempo = 15;
  var transicao = parseFloat(q.get("transicao") != null ? q.get("transicao") : cfg.transicao_segundos);
  if (!(transicao >= 0)) transicao = 0.6;
  transicao = Math.min(transicao, tempo / 3);
  var girar = formato === "v" ? parseInt(q.get("girar") != null ? q.get("girar") : cfg.girar_vertical, 10) || 0 : 0;
  if (girar !== 90 && girar !== -90 && girar !== 270) girar = 0;
  if (girar === 270) girar = -90;
  var comBarra = q.get("barra") != null ? q.get("barra") === "1" : !!cfg.barra_progresso;

  // Lista de graficos: so ids que existem e sao do formato certo.
  var conhecidos = {};
  window.GCTSE_GRAFICOS.lista.forEach(function (g) { conhecidos[g.id] = g.f; });
  var pedidos = q.get("lista") ? q.get("lista").split(",") : (formato === "v" ? cfg.vertical : cfg.horizontal);
  var ids = (pedidos || []).map(function (s) { return String(s).trim(); })
    .filter(function (id) { return conhecidos[id] === formato; });
  if (!ids.length) ids = window.GCTSE_GRAFICOS.lista.filter(function (g) { return g.f === formato; }).map(function (g) { return g.id; });

  // Palco: do tamanho da tela; girado quando o monitor vertical
  // recebe sinal de paisagem.
  var palco = document.getElementById("palco");
  if (girar) {
    palco.style.width = "100vh"; palco.style.height = "100vw";
    palco.style.transform = "translate(-50%, -50%) rotate(" + girar + "deg)";
  }
  var camadas = [document.getElementById("c0"), document.getElementById("c1")];
  camadas.forEach(function (c) { c.style.transition = "opacity " + transicao + "s ease-in-out"; });
  var barra = document.getElementById("barra");
  if (comBarra) barra.style.display = "block";

  var atual = 0, visivel = 0, chaveDados = "", pausado = false, timer = null;

  function chave() {
    var d = window.GCTSE_DADOS || {};
    return JSON.stringify([d.modo, d.br, d.ufs, d.cor_slot, d.cores]);
  }
  function desenharEm(camada, id) {
    var s = window.GCTSE_GRAFICOS.desenhar(id);
    camada.innerHTML = s || "";
    window.GCTSE_GRAFICOS.ajustarSelos(camada);
  }

  // Desenha o proximo na camada escondida e cruza.
  function mostrar(i) {
    atual = (i + ids.length) % ids.length;
    var prox = camadas[1 - visivel];
    desenharEm(prox, ids[atual]);
    prox.classList.add("on");
    camadas[visivel].classList.remove("on");
    visivel = 1 - visivel;
    chaveDados = chave();
    iniciarBarra();
  }
  function iniciarBarra() {
    if (!comBarra) return;
    barra.style.transition = "none"; barra.style.width = "0";
    void barra.offsetWidth;
    if (!pausado) { barra.style.transition = "width " + tempo + "s linear"; barra.style.width = "100%"; }
  }
  function agendar() {
    clearTimeout(timer);
    if (pausado || ids.length < 2) return;
    timer = setTimeout(function () { mostrar(atual + 1); agendar(); }, tempo * 1000);
  }

  // Dado novo: redesenha o grafico que esta no ar, sem piscar e sem
  // mexer no tempo dele.
  function recarregar() {
    var sc = document.createElement("script");
    sc.charset = "utf-8";
    sc.src = "dados.js?t=" + Date.now();
    sc.onload = function () {
      sc.remove();
      if (chave() !== chaveDados) { chaveDados = chave(); desenharEm(camadas[visivel], ids[atual]); }
    };
    sc.onerror = function () { sc.remove(); };
    document.head.appendChild(sc);
  }

  // Teclas: setas trocam, espaco pausa, F11 tela cheia.
  var aviso = document.getElementById("aviso"), tAviso = null;
  function avisar(txt) {
    aviso.textContent = txt; aviso.style.opacity = 1;
    clearTimeout(tAviso); tAviso = setTimeout(function () { aviso.style.opacity = 0; }, 1500);
  }
  document.addEventListener("keydown", function (e) {
    if (e.key === "ArrowRight" || e.key === "PageDown") { mostrar(atual + 1); agendar(); }
    else if (e.key === "ArrowLeft" || e.key === "PageUp") { mostrar(atual - 1); agendar(); }
    else if (e.key === " ") { pausado = !pausado; avisar(pausado ? "PAUSADO" : "RODANDO"); iniciarBarra(); agendar(); e.preventDefault(); }
  });

  // Nao deixa o monitor apagar (quando o navegador permite).
  function manterTelaLigada() {
    try { if (navigator.wakeLock) navigator.wakeLock.request("screen").catch(function () {}); } catch (e) {}
  }
  document.addEventListener("visibilitychange", function () { if (!document.hidden) manterTelaLigada(); });
  manterTelaLigada();

  document.title = "gctse APRESENTACAO " + (formato === "v" ? "VERTICAL" : "HORIZONTAL");
  mostrar(0);
  agendar();
  setInterval(recarregar, 3000);
})();
