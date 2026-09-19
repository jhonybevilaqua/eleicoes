"""Publicacao das telas e a pagina que o PC de exibicao abre.

    telao/
        lideranca.svg        uma por tela, reescrita quando o desenho muda
        estados.svg
        como-votou.svg
        ...
        telas.json / telas.js    a lista, para a mesa e para a tela
        no-ar.json / no-ar.js    qual tela esta selecionada
        index.html               a pagina do PC de exibicao

Por que cada coisa existe em .json E em .js: a pagina e aberta de 'file://' -
quase sempre de uma pasta compartilhada do PC que coleta - e nessa origem o
navegador bloqueia 'fetch' e 'XMLHttpRequest', inclusive para o arquivo
vizinho. Um <script src> carrega sem esse bloqueio, entao a pagina le os .js.
Os .json continuam para a mesa, para o monitoramento e para quem quiser ler o
estado do telao de fora.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path

from gctse.util.arquivos import escrever_texto

from .config import Config
from .telas import Dados, desenhar

log = logging.getLogger("telao.exibicao")


def escrever_par_js(caminho: Path, funcao: str, corpo: dict) -> Path:
    return escrever_texto(
        caminho, f"{funcao}({json.dumps(corpo, ensure_ascii=False)});\n", nova_linha="\n"
    )


def escrever_selecao(pasta: Path, identificador: str) -> Path:
    """Grava qual tela esta no ar, nos DOIS formatos que o telao usa.

    Ponto unico de escrita de proposito: escrever so um deles deixa a mesa e a
    exibicao discordando em silencio - a mesa marca uma tela, o ar mostra
    outra.
    """
    corpo = {"tela": identificador, "em": datetime.now().isoformat(timespec="seconds")}
    escrever_par_js(pasta / "no-ar.js", "telaoNoAr", corpo)
    return escrever_texto(
        pasta / "no-ar.json", json.dumps(corpo, ensure_ascii=False), nova_linha="\n"
    )


def ler_selecao(pasta: Path) -> str:
    try:
        return str(json.loads((pasta / "no-ar.json").read_text(encoding="utf-8")).get("tela", ""))
    except (OSError, json.JSONDecodeError):
        return ""


def ler_telas(pasta: Path) -> list[dict]:
    try:
        dados = json.loads((pasta / "telas.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    return [t for t in dados.get("telas", []) if isinstance(t, dict) and t.get("id")]


class Publicador:
    """Escreve as telas na pasta de saida, so quando o desenho muda."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.destino = cfg.destino
        self.telas = cfg.telas
        self._impressoes: dict[str, str] = {}

    def publicar(self, dados: Dados) -> list[Path]:
        escritos: list[Path] = []
        for tela in self.telas:
            try:
                svg = desenhar(self.cfg, tela, dados)
            except Exception:
                # Uma tela com defeito nao derruba as outras nem o ciclo: o que
                # ja estava no ar continua, e o log diz qual quebrou.
                log.exception("falha ao desenhar a tela '%s'", tela.id)
                continue
            # Sem isto, o PC de exibicao redecodificaria um SVG identico a cada
            # ciclo, e a dissolvencia piscaria sem nenhum dado ter mudado.
            if self._impressoes.get(tela.id) == svg:
                continue
            self._impressoes[tela.id] = svg
            escritos.append(escrever_texto(self.destino / f"{tela.id}.svg", svg, nova_linha="\n"))

        escritos.append(self._lista())
        pagina = self.destino / "index.html"
        if not pagina.exists():
            escritos.append(escrever_texto(pagina, self.pagina(), nova_linha="\n"))
        # Primeira tela como padrao, e tambem o reparo do par .js quando so o
        # .json existe: sem o .js a exibicao nao le a selecao em file://.
        if self.telas and not (self.destino / "no-ar.js").exists():
            escrever_selecao(self.destino, ler_selecao(self.destino) or self.telas[0].id)
        return escritos

    def _lista(self) -> Path:
        corpo = {
            "atualizado_em": datetime.now().isoformat(timespec="seconds"),
            "intervalo_segundos": self.cfg.intervalo_tela,
            "telas": [
                {"id": t.id, "tipo": t.tipo, "titulo": t.titulo or t.id, "arquivo": f"{t.id}.svg"}
                for t in self.telas
            ],
        }
        escrever_par_js(self.destino / "telas.js", "telaoTelas", corpo)
        return escrever_texto(
            self.destino / "telas.json",
            json.dumps(corpo, ensure_ascii=False, indent=2),
            nova_linha="\n",
        )

    # --- a pagina do PC de exibicao ---

    def pagina(self) -> str:
        """Tela cheia, sem cursor, seguindo a selecao.

        Quatro decisoes que so aparecem quando isto esta no ar:

        1. DUAS CAMADAS, nao um 'reload'. Recarregar a pagina pisca branco por
           um quadro, e quadro branco no ar e erro visivel. A imagem nova
           carrega escondida e so assume quando esta inteira.
        2. FALHA MANTEM O QUADRO. Arquivo sendo trocado, pasta de rede
           oscilando: a camada nova nao assume e o ultimo desenho bom continua.
           Tela preta por soluco de rede e pior do que uma tela atrasada.
        3. DOIS RELOGIOS. A selecao e relida a cada segundo, porque quem clica
           na mesa espera a tela entrar agora; o desenho, no intervalo
           configurado, porque o SVG so muda quando chega boletim.
        4. <script>, nao fetch. Ver o cabecalho deste modulo.
        """
        fundo = str(self.cfg.aparencia.get("cor_fundo", "#0b1220"))
        return f"""<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<title>Telão — apuração TSE</title>
<style>
  html,body{{margin:0;height:100%;background:{fundo};overflow:hidden;cursor:none}}
  #palco{{position:fixed;inset:0}}
  #palco img{{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;
    opacity:0;transition:opacity .28s linear}}
  #palco img.ativo{{opacity:1}}
  #aviso{{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;
    color:#9fb0c9;font:28px "Barlow Condensed",Arial Narrow,sans-serif;letter-spacing:.08em}}
  #estado{{position:fixed;left:8px;bottom:6px;font:12px ui-monospace,Menlo,monospace;
    color:#7d8aa0;display:none;white-space:pre}}
  body.debug #estado{{display:block}}
  body.debug{{cursor:default}}
</style>
<div id="palco"><img id="camadaA" alt=""><img id="camadaB" alt=""></div>
<div id="aviso">AGUARDANDO O PRIMEIRO BOLETIM</div>
<div id="estado"></div>
<script>
(function () {{
  var SELECAO = 1000;
  var DESENHO = {max(2, self.cfg.intervalo_tela)} * 1000;

  var camadas = [document.getElementById("camadaA"), document.getElementById("camadaB")];
  var atual = 0, trocas = 0, falhas = 0;
  var estado = document.getElementById("estado");
  var aviso = document.getElementById("aviso");
  var telas = [], escolhida = "", manual = false, rodizio = 0, passo = 0;

  if (location.search.indexOf("debug") >= 0) document.body.classList.add("debug");

  function anotar(quando) {{
    estado.textContent = quando
      + "  |  tela: " + (escolhida || "-")
      + (rodizio ? "  (rodizio " + rodizio + "s)" : manual ? "  (teclado)" : "  (mesa)")
      + "  |  trocas: " + trocas + "  falhas: " + falhas;
  }}

  window.telaoTelas = function (lista) {{
    telas = lista.telas || [];
    if (!escolhida && telas.length) trocarPara(telas[0].id);
  }};
  window.telaoNoAr = function (sel) {{
    if (manual || rodizio || !sel.tela) return;
    if (sel.tela !== escolhida) trocarPara(sel.tela);
  }};

  function ler(arquivo) {{
    var no = document.createElement("script");
    no.src = arquivo + "?t=" + Date.now();
    no.onload = function () {{ no.parentNode && no.parentNode.removeChild(no); }};
    no.onerror = function () {{ falhas++; no.parentNode && no.parentNode.removeChild(no); }};
    document.head.appendChild(no);
  }}

  function trocarPara(id) {{ escolhida = id; mostrar(); }}

  function mostrar() {{
    if (!escolhida) return;
    var proxima = camadas[1 - atual];
    proxima.onload = function () {{
      proxima.classList.add("ativo");
      camadas[atual].classList.remove("ativo");
      atual = 1 - atual;
      trocas++;
      aviso.style.display = "none";
      anotar(new Date().toLocaleTimeString("pt-BR"));
    }};
    proxima.onerror = function () {{
      falhas++;
      anotar("falha as " + new Date().toLocaleTimeString("pt-BR"));
    }};
    proxima.src = escolhida + ".svg?t=" + Date.now();
  }}

  function indiceAtual() {{
    return telas.findIndex(function (t) {{ return t.id === escolhida; }});
  }}

  function conferirSelecao() {{
    ler("telas.js");
    if (rodizio) {{
      passo += SELECAO / 1000;
      if (passo >= rodizio && telas.length) {{
        passo = 0;
        trocarPara(telas[(indiceAtual() + 1) % telas.length].id);
      }}
      return;
    }}
    if (!manual) ler("no-ar.js");
  }}

  document.addEventListener("keydown", function (e) {{
    if (e.key >= "1" && e.key <= "9") {{
      var n = parseInt(e.key, 10) - 1;
      if (telas[n]) {{ manual = true; rodizio = 0; trocarPara(telas[n].id); }}
    }} else if (e.key === "ArrowRight" && telas.length) {{
      manual = true; rodizio = 0;
      trocarPara(telas[(indiceAtual() + 1) % telas.length].id);
    }} else if (e.key === "ArrowLeft" && telas.length) {{
      manual = true; rodizio = 0;
      trocarPara(telas[(indiceAtual() - 1 + telas.length) % telas.length].id);
    }} else if (e.key === "r" || e.key === "R") {{
      rodizio = rodizio ? 0 : 20; passo = 0; manual = false;
    }} else if (e.key === "m" || e.key === "M") {{
      manual = false; rodizio = 0;      // devolve o comando para a mesa
      ler("no-ar.js");
    }} else if (e.key === "d" || e.key === "D") {{
      document.body.classList.toggle("debug");
    }}
    anotar(new Date().toLocaleTimeString("pt-BR"));
  }});

  document.addEventListener("click", function () {{
    if (!document.fullscreenElement && document.documentElement.requestFullscreen) {{
      document.documentElement.requestFullscreen();
    }}
  }});

  conferirSelecao();
  setInterval(conferirSelecao, SELECAO);
  setInterval(mostrar, DESENHO);
}})();
</script>
</html>
"""
