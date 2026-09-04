"""Interface de linha de comando.

  gctse validar        confere a configuracao antes do ar
  gctse descobrir      lista os pleitos publicados pelo TSE (codigos p/ config)
  gctse inspecionar    baixa um arquivo do TSE e mostra as chaves reais
  gctse uma-vez        executa um unico ciclo (bom para agendador/teste)
  gctse rodar          loop continuo de operacao
  gctse ensaio         loop continuo com dados simulados
  gctse amostrar       grava o JSON atual do TSE em dados/amostras
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__
from .config import ErroConfig, carregar
from .pipeline import Pipeline
from .tse.cliente import ClienteTSE
from .tse.descoberta import inspecionar, listar_eleicoes
from .tse.endpoints import Endpoints
from .util.log import configurar

PADRAO_CONFIG = "config/config.yaml"


def _cfg(args):
    return carregar(args.config)


def _iniciar_log(cfg, args) -> None:
    configurar(
        nivel=args.log or cfg.bruto.get("log", {}).get("nivel", "INFO"),
        arquivo=cfg.bruto.get("log", {}).get("arquivo"),
    )


def cmd_validar(args) -> int:
    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    problemas = cfg.validar()
    if problemas:
        print("Configuracao COM PROBLEMAS:")
        for problema in problemas:
            print(f"  - {problema}")
        return 1

    print(f"Configuracao OK ({cfg.caminho})")
    print(f"  fonte........: {cfg.coleta.get('fonte', 'tse')}")
    print(f"  intervalo....: {cfg.intervalo}s")
    print(f"  exporters....: {', '.join(cfg.exporters)}")
    endpoints = Endpoints(cfg.tse)
    print(f"  alvos ({len(cfg.alvos)}):")
    for alvo in cfg.alvos:
        print(f"    - {alvo.nome}: cargo {alvo.cargo}, turno {alvo.turno} -> {', '.join(alvo.exporters)}")
        print(f"      {endpoints.resultado(alvo.abrangencia, alvo.cargo)}")
    return 0


def cmd_descobrir(args) -> int:
    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    cliente = ClienteTSE(timeout=float(cfg.coleta.get("timeout_segundos", 8)))
    endpoints = Endpoints(cfg.tse)
    eleicoes = listar_eleicoes(cliente, endpoints)
    cliente.fechar()
    if not eleicoes:
        print("Nenhum pleito retornado. Confira 'tse.base_url' e a conectividade.")
        return 1
    print(f"{len(eleicoes)} pleito(s) publicados em {endpoints.config_eleicoes()}:\n")
    for eleicao in eleicoes:
        print(f"  codigo={eleicao['codigo']:<10} turno={eleicao['turno'] or '-':<3} "
              f"data={eleicao['data'] or '-':<12} {eleicao['nome']}")
    print("\nUse o codigo do pleito em tse.pleito e tse.eleicao no config.yaml.")
    return 0


def cmd_inspecionar(args) -> int:
    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    endpoints = Endpoints(cfg.tse)
    url = args.url or endpoints.resultado(args.abrangencia, args.cargo)
    cliente = ClienteTSE(timeout=float(cfg.coleta.get("timeout_segundos", 8)))
    resumo = inspecionar(cliente, url)
    cliente.fechar()
    print(json.dumps(resumo, ensure_ascii=False, indent=2))
    return 0 if "erro" not in resumo else 1


def cmd_amostrar(args) -> int:
    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    endpoints = Endpoints(cfg.tse)
    cliente = ClienteTSE(timeout=float(cfg.coleta.get("timeout_segundos", 8)), usar_cache=False)
    pasta = Path(args.pasta)
    pasta.mkdir(parents=True, exist_ok=True)
    gravados = 0
    for alvo in cfg.alvos:
        url = endpoints.resultado(alvo.abrangencia, alvo.cargo)
        resposta = cliente.buscar_json(url)
        if not resposta.ok:
            print(f"  {alvo.nome}: FALHA ({resposta.erro or resposta.status})")
            continue
        destino = pasta / f"{alvo.abrangencia}-c{alvo.cargo:04d}.json"
        destino.write_text(json.dumps(resposta.dados, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"  {alvo.nome}: gravado em {destino}")
        gravados += 1
    cliente.fechar()
    return 0 if gravados else 1


def _executar(cfg, args, uma_vez: bool) -> int:
    problemas = cfg.validar()
    if problemas:
        print("Configuracao invalida; corrija antes de executar:")
        for problema in problemas:
            print(f"  - {problema}")
        return 1
    pipeline = Pipeline(cfg)
    pipeline.instalar_sinais()
    try:
        if uma_vez:
            resultados = pipeline.rodar_uma_vez()
            for nome, situacao in sorted(resultados.items()):
                print(f"  {nome}: {situacao}")
        else:
            pipeline.rodar()
    finally:
        pipeline.fechar()
    return 0


def cmd_rodar(args) -> int:
    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    return _executar(cfg, args, uma_vez=False)


def cmd_uma_vez(args) -> int:
    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    return _executar(cfg, args, uma_vez=True)


def cmd_ensaio(args) -> int:
    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    # ensaio nunca toca o TSE e nao herda o bloqueio de fase simulada
    cfg.bruto.setdefault("coleta", {})["fonte"] = "simulador"
    cfg.bruto["coleta"]["simulador_duracao_segundos"] = args.duracao
    cfg.bruto.setdefault("seguranca", {})["bloquear_nao_oficial"] = False
    print(f"ENSAIO: dados simulados, apuracao completa em ~{args.duracao}s. Ctrl+C encerra.")
    return _executar(cfg, args, uma_vez=False)


def construir_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gctse",
        description="Automacao de apuracao eleitoral do TSE para sistemas de GC.",
    )
    parser.add_argument("-c", "--config", default=PADRAO_CONFIG, help=f"arquivo de configuracao (padrao: {PADRAO_CONFIG})")
    parser.add_argument("--log", help="nivel de log: DEBUG, INFO, WARNING, ERROR")
    parser.add_argument("-v", "--version", action="version", version=f"gctse {__version__}")

    sub = parser.add_subparsers(dest="comando", required=True)

    sub.add_parser("validar", help="confere a configuracao").set_defaults(func=cmd_validar)
    sub.add_parser("descobrir", help="lista os pleitos publicados pelo TSE").set_defaults(func=cmd_descobrir)

    p_insp = sub.add_parser("inspecionar", help="mostra as chaves reais de um arquivo do TSE")
    p_insp.add_argument("--url", help="URL completa (sobrepoe abrangencia/cargo)")
    p_insp.add_argument("--abrangencia", default="br")
    p_insp.add_argument("--cargo", type=int, default=1)
    p_insp.set_defaults(func=cmd_inspecionar)

    p_amostra = sub.add_parser("amostrar", help="grava o JSON atual dos alvos em disco")
    p_amostra.add_argument("--pasta", default="dados/amostras")
    p_amostra.set_defaults(func=cmd_amostrar)

    sub.add_parser("uma-vez", help="executa um unico ciclo").set_defaults(func=cmd_uma_vez)
    sub.add_parser("rodar", help="loop continuo de operacao").set_defaults(func=cmd_rodar)

    p_ensaio = sub.add_parser("ensaio", help="loop continuo com dados simulados")
    p_ensaio.add_argument("--duracao", type=int, default=900, help="segundos ate 100%% apurado (padrao: 900)")
    p_ensaio.set_defaults(func=cmd_ensaio)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = construir_parser()
    args = parser.parse_args(argv)
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
