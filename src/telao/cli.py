"""Linha de comando do telao.

  telao validar      confere a configuracao antes do ar
  telao descobrir    lista os pleitos publicados pelo TSE (codigos p/ config)
  telao rodar        no ar: coleta o TSE e reescreve as telas
  telao ensaio       o mesmo, com dados ficticios - nao toca o TSE
  telao exemplo      gera as telas uma vez, para a arte e o teste de cena
  telao mesa         janela para escolher a tela que vai ao ar
  telao no-ar        a mesma escolha, sem janela
"""

from __future__ import annotations

import argparse
import logging
import os
import signal
import sys
import threading
from pathlib import Path

from gctse.tse.cliente import ClienteTSE
from gctse.tse.descoberta import listar_eleicoes
from gctse.tse.endpoints import Endpoints
from gctse.util.log import configurar

from . import __version__
from .coleta import Coletor, rodar
from .config import ErroConfig, carregar, caminho_padrao
from .exibicao import Publicador, escrever_selecao, ler_selecao, ler_telas
from .telas import Dados, resumo
from .vertical import PublicadorVertical

log = logging.getLogger("telao")


def _ancorar_na_pasta_do_executavel() -> None:
    """No executavel empacotado, trabalha a partir da pasta do proprio .exe.

    Sem isso, dar duplo clique herda um diretorio de trabalho qualquer e todos
    os caminhos relativos da config apontam para o lugar errado.
    """
    if getattr(sys, "frozen", False):
        os.chdir(Path(sys.executable).resolve().parent)


def _cfg(args):
    return carregar(args.config or caminho_padrao())


def _log(cfg, args) -> None:
    configurar(
        nivel=args.log or cfg.bruto.get("log", {}).get("nivel", "INFO"),
        arquivo=cfg.bruto.get("log", {}).get("arquivo"),
    )


def _pasta(cfg, args) -> Path:
    return Path(args.pasta) if getattr(args, "pasta", None) else cfg.destino


def cmd_validar(args) -> int:
    cfg = _cfg(args)
    _log(cfg, args)
    problemas = cfg.validar()
    if problemas:
        print("Configuracao COM PROBLEMAS:")
        for problema in problemas:
            print(f"  - {problema}")
        return 1

    print(f"Configuracao OK ({cfg.caminho})")
    print(f"  fonte.......: {cfg.coleta.get('fonte', 'tse')}")
    print(f"  cargo.......: {cfg.cargo} (turno {cfg.turno})")
    print(f"  pracas......: br + {len(cfg.estados)} estado(s)")
    print(f"  intervalo...: {cfg.intervalo}s")
    print(f"  saida.......: {cfg.destino}")
    print(f"  telas ({len(cfg.telas)}):")
    for indice, tela in enumerate(cfg.telas, start=1):
        print(f"    {indice}. {tela.id:<20} {tela.tipo:<18} {tela.titulo}")
    if cfg.vertical.get("ativo"):
        from .vertical import telas_configuradas

        tipos = telas_configuradas(cfg)
        print(f"\n  monitor vertical 1080x1920 -> {cfg.vertical.get('destino', 'telao-vertical')}")
        print(f"    rodizio de {cfg.vertical.get('rodizio_segundos', 10)}s: {', '.join(tipos)}")
    if str(cfg.coleta.get("fonte", "tse")).lower() == "tse":
        print(f"\n  exemplo de URL: {Endpoints(cfg.tse).resultado('br', cfg.cargo)}")
    return 0


def cmd_descobrir(args) -> int:
    cfg = _cfg(args)
    _log(cfg, args)
    cliente = ClienteTSE(timeout=float(cfg.coleta.get("timeout_segundos", 8)))
    endpoints = Endpoints(cfg.tse)
    eleicoes = listar_eleicoes(cliente, endpoints)
    cliente.fechar()
    if not eleicoes:
        print("Nenhum pleito retornado. Confira 'tse.base_url' e a conectividade.")
        return 1
    print(f"{len(eleicoes)} pleito(s) publicados:\n")
    for eleicao in eleicoes:
        print(f"  codigo={eleicao['codigo']:<10} turno={eleicao['turno'] or '-':<3} "
              f"data={eleicao['data'] or '-':<12} {eleicao['nome']}")
    print("\nUse o codigo em tse.pleito e tse.eleicao no telao.yaml.")
    return 0


def _publicar(cfg, coletor: Coletor, publicador: Publicador,
              vertical: PublicadorVertical | None = None) -> None:
    dados = Dados.do_coletor(coletor)
    escritos = publicador.publicar(dados)
    if vertical is not None:
        escritos += vertical.publicar(dados)
    numeros = resumo(dados)
    log.info(
        "telas: %d arquivo(s) | %d estado(s) com boletim | %.2f%% apurado",
        len(escritos), numeros["estados_com_boletim"], numeros["pct"],
    )


def _executar(cfg, args, uma_vez: bool) -> int:
    problemas = cfg.validar()
    if problemas:
        print("Configuracao invalida; corrija antes de executar:")
        for problema in problemas:
            print(f"  - {problema}")
        return 1

    publicador = Publicador(cfg)
    vertical = PublicadorVertical(cfg)
    if uma_vez:
        coletor = Coletor(cfg)
        try:
            coletor.ciclo()
            _publicar(cfg, coletor, publicador, vertical)
        finally:
            coletor.fechar()
        print(f"\nTelas gravadas em {cfg.destino}")
        print("Abra index.html no PC de exibicao (TELAO-TELA.bat).")
        if vertical.ativo:
            print(f"Monitor vertical em {vertical.destino} (TELAO-VERTICAL.bat).")
        return 0

    parar = threading.Event()

    def encerrar(_signum, _frame):
        log.info("sinal recebido: encerrando apos o ciclo atual")
        parar.set()

    for sinal in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sinal, encerrar)
        except (ValueError, OSError):  # fora da thread principal / Windows
            pass

    rodar(cfg, lambda coletor: _publicar(cfg, coletor, publicador, vertical), parar)
    return 0


def cmd_rodar(args) -> int:
    cfg = _cfg(args)
    _log(cfg, args)
    return _executar(cfg, args, uma_vez=False)


def cmd_exemplo(args) -> int:
    """Um ciclo so, com dados ficticios: telas prontas para a arte conferir."""
    cfg = _cfg(args)
    _log(cfg, args)
    cfg.bruto.setdefault("coleta", {})["fonte"] = "simulador"
    cfg.bruto["coleta"]["simulador_progresso"] = args.progresso
    cfg.bruto.setdefault("seguranca", {})["bloquear_nao_oficial"] = False
    if args.pasta:
        cfg.bruto.setdefault("saida", {})["destino"] = args.pasta
    print(f"Gerando as telas em {cfg.destino} com {args.progresso:.0f}% apurado...")
    codigo = _executar(cfg, args, uma_vez=True)
    print("ATENCAO: conteudo ficticio, fase 'S'. Nao use no ar.")
    return codigo


def cmd_ensaio(args) -> int:
    cfg = _cfg(args)
    _log(cfg, args)
    cfg.bruto.setdefault("coleta", {})["fonte"] = "simulador"
    cfg.bruto["coleta"]["simulador_duracao_segundos"] = args.duracao
    # o ensaio tem historico proprio: a curva do treino nao entra na serie que
    # a coordenacao vai ler no dia
    cfg.bruto["coleta"]["arquivo_historico"] = str(cfg.destino / "ensaio-historico.jsonl")
    cfg.bruto.setdefault("seguranca", {})["bloquear_nao_oficial"] = False
    print(f"ENSAIO: dados ficticios, apuracao completa em ~{args.duracao}s. Ctrl+C encerra.")
    return _executar(cfg, args, uma_vez=False)


def cmd_mesa(args) -> int:
    from .mesa import abrir

    cfg = _cfg(args)
    _log(cfg, args)
    return abrir(_pasta(cfg, args))


def cmd_no_ar(args) -> int:
    cfg = _cfg(args)
    _log(cfg, args)
    pasta = _pasta(cfg, args)
    telas = ler_telas(pasta)

    if args.listar or not args.tela:
        if not telas:
            print(f"Nenhuma tela publicada em {pasta}.")
            print("O telao grava 'telas.json' depois do primeiro ciclo.")
            return 1
        atual = ler_selecao(pasta)
        print(f"Telas em {pasta}:\n")
        for indice, tela in enumerate(telas, start=1):
            marca = "  <- no ar" if tela["id"] == atual else ""
            print(f"  {indice}. {tela['id']:<20} {tela.get('titulo', '')}{marca}")
        print("\nUse: telao no-ar <id>")
        return 0

    conhecidas = {t["id"] for t in telas}
    if telas and args.tela not in conhecidas:
        print(f"Tela '{args.tela}' nao existe. Conhecidas: {', '.join(sorted(conhecidas))}")
        return 1
    escrever_selecao(pasta, args.tela)
    print(f"No ar: {args.tela}")
    return 0


def construir_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="telao",
        description="Telas de apuracao em 1920x1080 para um PC de exibicao.",
    )
    parser.add_argument("-c", "--config", default=None,
                        help="arquivo de configuracao (padrao: telao.yaml)")
    parser.add_argument("--log", help="nivel de log: DEBUG, INFO, WARNING, ERROR")
    parser.add_argument("-v", "--version", action="version", version=f"telao {__version__}")

    sub = parser.add_subparsers(dest="comando", required=True)
    sub.add_parser("validar", help="confere a configuracao").set_defaults(func=cmd_validar)
    sub.add_parser("descobrir", help="lista os pleitos publicados pelo TSE").set_defaults(
        func=cmd_descobrir
    )
    sub.add_parser("rodar", help="no ar: coleta e reescreve as telas").set_defaults(func=cmd_rodar)

    p_ensaio = sub.add_parser("ensaio", help="loop continuo com dados ficticios")
    p_ensaio.add_argument("--duracao", type=int, default=900,
                          help="segundos ate 100%% apurado (padrao: 900)")
    p_ensaio.set_defaults(func=cmd_ensaio)

    p_exemplo = sub.add_parser("exemplo", help="gera as telas uma vez, com dados ficticios")
    p_exemplo.add_argument("--progresso", type=float, default=63.0,
                           help="percentual apurado (padrao: 63)")
    p_exemplo.add_argument("--pasta", help="pasta de destino (padrao: a da config)")
    p_exemplo.set_defaults(func=cmd_exemplo)

    p_mesa = sub.add_parser("mesa", help="janela para escolher a tela que vai ao ar")
    p_mesa.add_argument("--pasta", help="pasta do telao (padrao: a da config)")
    p_mesa.set_defaults(func=cmd_mesa)

    p_no_ar = sub.add_parser("no-ar", help="escolhe a tela sem abrir janela")
    p_no_ar.add_argument("tela", nargs="?", help="id da tela (vazio lista as disponiveis)")
    p_no_ar.add_argument("--listar", action="store_true", help="so lista, nao troca")
    p_no_ar.add_argument("--pasta", help="pasta do telao (padrao: a da config)")
    p_no_ar.set_defaults(func=cmd_no_ar)

    return parser


def main(argv: list[str] | None = None) -> int:
    _ancorar_na_pasta_do_executavel()
    args = construir_parser().parse_args(argv)
    try:
        return args.func(args)
    except ErroConfig as exc:
        print(f"ERRO DE CONFIGURACAO: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\ninterrompido pelo operador")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
