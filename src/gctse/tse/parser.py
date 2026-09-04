"""Conversao do JSON do TSE para o modelo normalizado.

O arquivo "dados-simplificados" do TSE usa chaves abreviadas (vap = votos
apurados, pvap = percentual, pst = percentual de secoes totalizadas, etc.).
Essas abreviacoes mudaram entre pleitos, entao o mapeamento e declarativo:
cada campo do modelo aponta para uma LISTA de chaves candidatas e usamos a
primeira que existir. Para ajustar em 2026 basta editar config/mapeamento.yaml
(ou a secao 'mapeamento' da config) - nenhuma linha de codigo muda.

Use 'gctse inspecionar --url ...' para listar as chaves reais do arquivo
publicado e conferir o mapeamento antes do dia da eleicao.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from ..modelos import CARGOS, Apuracao, Candidato
from ..util.numeros import para_float, para_int
from ..util.texto import limpar
from .endpoints import tipo_abrangencia

log = logging.getLogger("gctse.parser")

# Cada entrada: campo do modelo -> chaves aceitas no JSON do TSE, em ordem.
MAPA_RESUMO: dict[str, list[str]] = {
    "eleicao": ["ele", "cdeleicao", "codigoEleicao"],
    "pleito": ["cdpleito", "pleito"],
    "cargo_codigo": ["carg", "cdcargo", "cargo"],
    "abrangencia_codigo": ["cdabr", "abr", "cdabrangencia"],
    "abrangencia_nome": ["nmabr", "nmabrangencia"],
    "abrangencia_tipo": ["tpabr", "tpabrangencia"],
    "fase": ["f", "fase", "tf"],
    "data_geracao": ["dg", "dtgeracao", "dataGeracao"],
    "hora_geracao": ["hg", "hrgeracao", "horaGeracao"],
    "votos_validos": ["vv", "vvc", "votosValidos"],
    "votos_nominais": ["vnom", "votosNominais"],
    "votos_brancos": ["vb", "votosBrancos"],
    "votos_nulos": ["vn", "votosNulos"],
    "total_apurado": ["tvn", "ta", "totalApurado"],
    "eleitorado_apto": ["ea", "eleitoradoApto", "apt"],
    "comparecimento": ["c", "comp", "comparecimento"],
    "abstencao": ["a", "abst", "abstencao"],
    "candidatos": ["cand", "candidatos", "cands"],
    "secoes": ["s", "sec", "secoes"],
}

MAPA_SECOES: dict[str, list[str]] = {
    "totalizadas": ["st", "t", "sectot", "totalizadas"],
    "total": ["s", "tot", "total", "sectotal"],
    "percentual": ["pst", "perc", "percentual"],
}

MAPA_CANDIDATO: dict[str, list[str]] = {
    "numero": ["n", "num", "numero"],
    "nome": ["nm", "nmurna", "nomeUrna"],
    "nome_completo": ["nmt", "nmcand", "nomeCompleto"],
    "partido": ["cc", "sgpart", "partido", "sg"],
    "coligacao": ["nv", "coligacao", "nmColigacao"],
    "votos": ["vap", "votos", "qtvotos"],
    "percentual": ["pvap", "perc", "percentual"],
    "eleito": ["e", "eleito"],
    "situacao": ["st", "situacao", "dsSituacao"],
    "sequencial": ["sqcand", "seq", "sequencial"],
    "vice": ["nmvice", "vice"],
}

VALORES_ELEITO = {"s", "sim", "true", "1", "eleito"}


def _primeiro(origem: dict, chaves: list[str], padrao: Any = None) -> Any:
    for chave in chaves:
        if chave in origem and origem[chave] not in (None, ""):
            return origem[chave]
    return padrao


def _mesclar_mapa(base: dict[str, list[str]], extra: dict[str, Any] | None) -> dict[str, list[str]]:
    """Config do usuario tem prioridade; a lista dele vem antes da padrao."""
    if not extra:
        return base
    resultado = {k: list(v) for k, v in base.items()}
    for campo, chaves in extra.items():
        if isinstance(chaves, str):
            chaves = [chaves]
        resultado[campo] = list(chaves) + [c for c in resultado.get(campo, []) if c not in chaves]
    return resultado


def _data_hora(data: str, hora: str) -> datetime | None:
    """'02/10/2026' + '20:34:41' -> datetime. Aceita ISO como alternativa."""
    data, hora = limpar(data), limpar(hora)
    if not data:
        return None
    for formato in ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y"):
        try:
            return datetime.strptime(f"{data} {hora}".strip(), formato)
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(data.replace("Z", "+00:00"))
    except ValueError:
        log.debug("data/hora de geracao nao reconhecida: %r %r", data, hora)
        return None


def _eh_eleito(valor: Any) -> bool:
    return str(valor).strip().lower() in VALORES_ELEITO


def analisar(
    dados: dict[str, Any],
    *,
    abrangencia: str,
    cargo: int,
    turno: int = 1,
    fonte_url: str = "",
    mapeamento: dict[str, Any] | None = None,
    limite_candidatos: int = 0,
    nome_abrangencia: str = "",
) -> Apuracao:
    """Converte o JSON simplificado do TSE em uma Apuracao normalizada."""
    mapeamento = mapeamento or {}
    mapa_resumo = _mesclar_mapa(MAPA_RESUMO, mapeamento.get("resumo"))
    mapa_secoes = _mesclar_mapa(MAPA_SECOES, mapeamento.get("secoes"))
    mapa_cand = _mesclar_mapa(MAPA_CANDIDATO, mapeamento.get("candidato"))

    cargo_codigo = para_int(_primeiro(dados, mapa_resumo["cargo_codigo"], cargo), cargo)

    apuracao = Apuracao(
        eleicao=str(_primeiro(dados, mapa_resumo["eleicao"], "") or ""),
        pleito=str(_primeiro(dados, mapa_resumo["pleito"], "") or ""),
        turno=turno,
        cargo_codigo=cargo_codigo,
        cargo_nome=CARGOS.get(cargo_codigo, f"Cargo {cargo_codigo}"),
        abrangencia_tipo=str(_primeiro(dados, mapa_resumo["abrangencia_tipo"], "") or tipo_abrangencia(abrangencia)),
        abrangencia_codigo=str(_primeiro(dados, mapa_resumo["abrangencia_codigo"], abrangencia) or abrangencia).upper(),
        abrangencia_nome=limpar(_primeiro(dados, mapa_resumo["abrangencia_nome"], "")) or nome_abrangencia or abrangencia.upper(),
        fase=str(_primeiro(dados, mapa_resumo["fase"], "") or "").upper()[:1],
        gerado_em=_data_hora(
            str(_primeiro(dados, mapa_resumo["data_geracao"], "") or ""),
            str(_primeiro(dados, mapa_resumo["hora_geracao"], "") or ""),
        ),
        capturado_em=datetime.now(timezone.utc).astimezone(),
        votos_validos=para_int(_primeiro(dados, mapa_resumo["votos_validos"])),
        votos_nominais=para_int(_primeiro(dados, mapa_resumo["votos_nominais"])),
        votos_brancos=para_int(_primeiro(dados, mapa_resumo["votos_brancos"])),
        votos_nulos=para_int(_primeiro(dados, mapa_resumo["votos_nulos"])),
        total_apurado=para_int(_primeiro(dados, mapa_resumo["total_apurado"])),
        eleitorado_apto=para_int(_primeiro(dados, mapa_resumo["eleitorado_apto"])),
        comparecimento=para_int(_primeiro(dados, mapa_resumo["comparecimento"])),
        abstencao=para_int(_primeiro(dados, mapa_resumo["abstencao"])),
        fonte_url=fonte_url,
        bruto=dados,
    )

    secoes = _primeiro(dados, mapa_resumo["secoes"], {}) or {}
    if isinstance(secoes, dict):
        apuracao.secoes_totalizadas = para_int(_primeiro(secoes, mapa_secoes["totalizadas"]))
        apuracao.secoes_total = para_int(_primeiro(secoes, mapa_secoes["total"]))
        apuracao.pct_secoes = para_float(_primeiro(secoes, mapa_secoes["percentual"]))
    # alguns arquivos trazem o percentual no nivel raiz
    if not apuracao.pct_secoes:
        apuracao.pct_secoes = para_float(_primeiro(dados, ["pst", "psec"]))
    if not apuracao.pct_secoes and apuracao.secoes_total:
        apuracao.pct_secoes = round(100.0 * apuracao.secoes_totalizadas / apuracao.secoes_total, 2)

    lista = _primeiro(dados, mapa_resumo["candidatos"], []) or []
    if isinstance(lista, dict):  # defensivo: alguns arquivos usam objeto indexado
        lista = list(lista.values())

    candidatos: list[Candidato] = []
    for item in lista:
        if not isinstance(item, dict):
            continue
        candidatos.append(
            Candidato(
                numero=str(_primeiro(item, mapa_cand["numero"], "") or "").strip(),
                nome=limpar(_primeiro(item, mapa_cand["nome"], "")),
                nome_completo=limpar(_primeiro(item, mapa_cand["nome_completo"], "")),
                partido=limpar(_primeiro(item, mapa_cand["partido"], "")),
                coligacao=limpar(_primeiro(item, mapa_cand["coligacao"], "")),
                votos=para_int(_primeiro(item, mapa_cand["votos"])),
                percentual=para_float(_primeiro(item, mapa_cand["percentual"])),
                eleito=_eh_eleito(_primeiro(item, mapa_cand["eleito"], "n")),
                situacao=limpar(_primeiro(item, mapa_cand["situacao"], "")),
                sequencial=str(_primeiro(item, mapa_cand["sequencial"], "") or ""),
                vice=limpar(_primeiro(item, mapa_cand["vice"], "")),
                extras=item,
            )
        )

    # Ordem de exibicao: votos desc; empate resolvido pelo numero, para o
    # placar nao "piscar" trocando de lugar entre um ciclo e outro.
    candidatos.sort(key=lambda c: (-c.votos, c.numero))
    for posicao, candidato in enumerate(candidatos, start=1):
        candidato.posicao = posicao
        if not candidato.percentual and apuracao.votos_validos:
            candidato.percentual = round(100.0 * candidato.votos / apuracao.votos_validos, 2)

    apuracao.candidatos = candidatos[:limite_candidatos] if limite_candidatos > 0 else candidatos
    return apuracao
