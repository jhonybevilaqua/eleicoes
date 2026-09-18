"""Painel de validacao: uma pagina HTML reescrita a cada ciclo.

E a tela que o coordenador deixa aberta num monitor durante a apuracao para
conferir, sem abrir arquivo nenhum, o que esta prestes a entrar no ar: quais
pracas tem dado, quanto ja apurou, quem esta na frente e o que esta bloqueado.

Deliberadamente um ARQUIVO ESTATICO, nao um servidor web: nada de porta
aberta, nada de processo extra para cair no meio da transmissao. Da duplo
clique e o proprio HTML se atualiza sozinho pelo meta refresh.
"""

from __future__ import annotations

import html
from datetime import datetime
from pathlib import Path

from .modelos import Apuracao
from .util.arquivos import escrever_texto

# Situacoes que exigem olho do operador, e como mostra-las.
ALERTAS = {
    "bloqueado": ("aviso", "Fase não oficial — nada publicado"),
    "regressao": ("aviso", "Boletim antigo descartado"),
    "falha": ("erro", "Falha na coleta"),
    "aguardando": ("neutro", "Abaixo do mínimo para publicar"),
}


def _classe(situacao: str) -> tuple[str, str]:
    for chave, (classe, _) in ALERTAS.items():
        if situacao.startswith(chave):
            return classe, situacao
    if situacao.startswith("publicado"):
        return "ok", situacao
    return "neutro", situacao


def _linha_alvo(nome: str, situacao: str, ap: Apuracao | None, previsao: dict | None = None) -> str:
    classe, rotulo = _classe(situacao)
    if ap is None:
        return (
            f'<tr class="{classe}"><td class="nome">{html.escape(nome)}</td>'
            f'<td colspan="7" class="vazio">sem boletim</td>'
            f'<td><span class="tag {classe}">{html.escape(rotulo)}</span></td></tr>'
        )

    lider = ap.candidatos[0] if ap.candidatos else None
    segundo = ap.candidatos[1] if len(ap.candidatos) > 1 else None
    oficial = "" if ap.oficial else '<span class="tag aviso">SIMULADO</span>'

    def cand(c):
        if c is None:
            return '<td class="vazio">—</td><td class="vazio">—</td>'
        sigla = f" <i>{html.escape(c.partido)}</i>" if c.partido else ""
        eleito = ' <span class="eleito">eleito</span>' if c.eleito else ""
        return (f'<td>{html.escape(c.nome)}{sigla}{eleito}</td>'
                f'<td class="num">{c.percentual:.2f}%</td>')

    # Previsao de fechamento: existe so depois de alguns boletins, e some
    # quando a apuracao para - melhor uma celula vazia do que um horario que o
    # coordenador usaria para liberar equipe sem base nenhuma.
    prev = (previsao or {}).get("previsao") or "—"
    if (previsao or {}).get("totalizada"):
        prev = "fechado"

    return (
        f'<tr class="{classe}">'
        f'<td class="nome">{html.escape(nome)} {oficial}</td>'
        f'<td>{html.escape(ap.cargo_nome)}</td>'
        f'<td class="num forte">{ap.pct_secoes:.2f}%</td>'
        f'{cand(lider)}{cand(segundo)}'
        f'<td class="num">{ap.pct_brancos_nulos:.2f}%</td>'
        f'<td class="num">{html.escape(prev)}</td>'
        f'<td><span class="tag {classe}">{html.escape(rotulo)}</span></td>'
        f"</tr>"
    )


def _linha_rodizio(nome: str, total: int, com_dado: int) -> str:
    classe = "ok" if com_dado == total else ("erro" if com_dado == 0 else "aviso")
    return (f'<tr class="{classe}"><td class="nome">{html.escape(nome)}</td>'
            f'<td class="num forte">{com_dado} de {total}</td>'
            f'<td>praças com boletim</td></tr>')


def renderizar(
    *,
    caminho: str | Path,
    fonte: str,
    ciclos: int,
    intervalo: int,
    resultados: dict[str, str],
    apuracoes: dict[str, Apuracao],
    rodizios: dict[str, tuple[int, int]],
    projecoes: dict[str, dict] | None = None,
) -> Path:
    agora = datetime.now()
    ensaio = fonte != "tse"

    projecoes = projecoes or {}
    linhas = "".join(
        _linha_alvo(nome, resultados[nome], apuracoes.get(nome), projecoes.get(nome))
        for nome in sorted(resultados)
    )
    bloco_rodizio = ""
    if rodizios:
        corpo = "".join(_linha_rodizio(n, t, c) for n, (t, c) in sorted(rodizios.items()))
        bloco_rodizio = (
            '<h2>Grupos (rodízio e mapa)</h2><table class="rod"><tbody>' + corpo + "</tbody></table>"
        )

    faixa = (
        '<div class="faixa ensaio">FONTE DE ENSAIO — dados fictícios, não use no ar</div>'
        if ensaio else ""
    )

    documento = f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="{max(5, intervalo)}">
<title>Painel de apuração · gctse</title>
<style>
:root{{--bg:#0d1420;--sup:#141d2c;--sup2:#1b2534;--ln:#243247;--tx:#e6ecf6;--tx2:#93a3bb;
  --ok:#2ea36a;--av:#d8a032;--er:#d45c5c;--ac:#4a90d9}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--tx);
  font:14px/1.5 "Segoe UI",system-ui,-apple-system,sans-serif}}
.topo{{padding:18px 26px;border-bottom:1px solid var(--ln);display:flex;
  align-items:baseline;gap:18px;flex-wrap:wrap}}
h1{{margin:0;font-size:19px;font-weight:600;letter-spacing:.01em}}
.meta{{color:var(--tx2);font-size:13px;display:flex;gap:16px;margin-left:auto;flex-wrap:wrap}}
.meta b{{color:var(--tx);font-weight:600}}
.faixa{{padding:9px 26px;font-weight:600;letter-spacing:.06em;font-size:13px}}
.faixa.ensaio{{background:#4a3410;color:#f0c674;border-bottom:1px solid #6b4d18}}
main{{padding:22px 26px 40px}}
h2{{font-size:13px;text-transform:uppercase;letter-spacing:.1em;color:var(--tx2);
  font-weight:600;margin:28px 0 10px}}
h2:first-child{{margin-top:0}}
table{{width:100%;border-collapse:collapse;font-size:13.5px}}
th{{text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.09em;
  color:var(--tx2);font-weight:600;padding:0 12px 8px 0;border-bottom:1px solid var(--ln)}}
td{{padding:9px 12px 9px 0;border-bottom:1px solid var(--ln);vertical-align:middle}}
tr.erro td{{background:#2a1416}}
tr.aviso td{{background:#2a2312}}
.nome{{font-weight:600;white-space:nowrap}}
.num{{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}}
.forte{{font-weight:700;font-size:15px}}
.vazio{{color:var(--tx2)}}
i{{color:var(--tx2);font-style:normal;font-size:12px}}
.eleito{{color:var(--ok);font-size:11px;text-transform:uppercase;letter-spacing:.06em;
  font-weight:700}}
.tag{{display:inline-block;padding:2px 9px;border-radius:3px;font-size:11.5px;
  font-weight:600;white-space:nowrap}}
.tag.ok{{background:#13341f;color:#5fce93}}
.tag.aviso{{background:#3a2f12;color:#f0c674}}
.tag.erro{{background:#3a1a1c;color:#ef8d8d}}
.tag.neutro{{background:#1d2738;color:var(--tx2)}}
.rod td:first-child{{width:220px}}
footer{{color:var(--tx2);font-size:12px;margin-top:26px;padding-top:14px;
  border-top:1px solid var(--ln)}}
</style></head><body>
<div class="topo">
  <h1>Painel de apuração</h1>
  <div class="meta">
    <span>fonte <b>{html.escape(fonte)}</b></span>
    <span>ciclo <b>{ciclos}</b></span>
    <span>atualizado <b>{agora.strftime('%H:%M:%S')}</b></span>
    <span>recarrega a cada <b>{max(5, intervalo)}s</b></span>
  </div>
</div>
{faixa}
<main>
<h2>Praças</h2>
<table><thead><tr>
  <th>Alvo</th><th>Cargo</th><th class="num">Urnas</th>
  <th>1º colocado</th><th class="num">%</th>
  <th>2º colocado</th><th class="num">%</th>
  <th class="num">Br+Nu</th><th class="num">Fecha</th><th>Situação</th>
</tr></thead><tbody>{linhas}</tbody></table>
{bloco_rodizio}
<footer>Página estática reescrita a cada ciclo. Percentuais de urnas e de votos
válidos vêm do mesmo boletim exibido no ar. <b>Br+Nu</b> é a soma de brancos e
nulos sobre os votos apurados. <b>Fecha</b> é a previsão de 100% no ritmo dos
últimos boletins — serve para escala e intervalo, não para o ar.</footer>
</main></body></html>"""

    return escrever_texto(Path(caminho), documento, encoding="utf-8", nova_linha="\n")
