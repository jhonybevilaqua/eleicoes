"""Linha de comando do telao.

  telao validar      confere a configuracao antes do ar
  telao descobrir    lista os pleitos publicados pelo TSE (codigos p/ config)
  telao rodar        no ar: coleta o TSE e reescreve as telas
  telao ensaio       o mesmo, com dados ficticios - nao toca o TSE
  telao exemplo      gera as telas uma vez, para a arte e o teste de cena
  telao mesa         janela para escolher a tela que vai ao ar
  telao no-ar        a mesma escolha, sem janela
  telao modo         mostra ou troca entre Simulado e Producao
"""

from __future__ import annotations

import argparse
import logging
import os
import re
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
from .config import MODOS, ErroConfig, carregar, caminho_padrao
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


def _faixa_modo(cfg) -> None:
    """Diz em que modo o sistema esta, de um jeito que nao passa batido.

    Subir em Simulado achando que esta em Producao - ou o contrario - e o erro
    mais caro possivel aqui, e ele e silencioso: os dois modos leem o TSE e
    desenham as mesmas telas. A unica defesa barata e gritar na partida.
    """
    if cfg.simulado:
        print("=" * 66)
        print("  MODO SIMULADO - dados de TESTE do TSE (fase 'S')")
        print("  Todas as telas saem carimbadas. NAO use no dia da eleicao.")
        print("=" * 66)
    else:
        print("-" * 66)
        print("  MODO PRODUCAO - so boletim oficial (fase 'O')")
        print("-" * 66)


def cmd_modo(args) -> int:
    """Mostra o modo, ou troca gravando no proprio telao.yaml."""
    cfg = _cfg(args)
    _log(cfg, args)

    if not args.novo:
        print(f"Modo atual: {cfg.modo.upper()}")
        if os.environ.get("TELAO_MODO"):
            print(f"  (vindo da variavel TELAO_MODO={os.environ['TELAO_MODO']},")
            print("   que tem prioridade sobre o arquivo)")
        print(f"  pleito {cfg.tse.get('pleito', '-')} / eleicao {cfg.tse.get('eleicao', '-')}")
        print(f"  aceita fase simulada: {'sim' if cfg.simulado else 'nao'}")
        print("\nPara trocar:  telao modo simulado   |   telao modo producao")
        return 0

    novo = str(args.novo).strip().lower()
    if novo not in MODOS:
        print(f"Modo '{args.novo}' desconhecido. Use: {' ou '.join(MODOS)}")
        return 1

    if cfg.caminho.suffix.lower() not in (".yaml", ".yml"):
        # a reescrita e linha a linha, de YAML; aplicada a um .json quebraria
        # o arquivo de vez, e sem config nenhuma o telao nao sobe
        print(f"'{cfg.caminho}' nao e YAML, entao nao sei reescrever a linha do modo.")
        print(f"Edite o arquivo e ponha:  \"modo\": \"{novo}\"")
        print(f"Ou rode com a variavel:   set TELAO_MODO={novo}")
        return 1

    texto = cfg.caminho.read_text(encoding="utf-8")
    trocado, saida = False, []
    for linha in texto.splitlines():
        if not trocado and re.match(r"^\s*modo\s*:", linha):
            saida.append(f"modo: {novo}")
            trocado = True
        else:
            saida.append(linha)
    if not trocado:
        saida.insert(0, f"modo: {novo}")
    cfg.caminho.write_text("\n".join(saida) + "\n", encoding="utf-8")

    print(f"Modo gravado em {cfg.caminho}: {novo.upper()}")
    if os.environ.get("TELAO_MODO"):
        print(f"ATENCAO: a variavel TELAO_MODO={os.environ['TELAO_MODO']} continua valendo")
        print("nesta janela e tem prioridade sobre o arquivo.")
    return 0


def cmd_validar(args) -> int:
    cfg = _cfg(args)
    _log(cfg, args)
    _faixa_modo(cfg)
    erros, pendencias = cfg.conferir()
    if erros:
        print("Configuracao COM PROBLEMAS:")
        for problema in erros:
            print(f"  - {problema}")
        return 1
    if pendencias:
        print("Configuracao OK, mas FALTA PREENCHER antes de ir ao TSE:")
        for pendencia in pendencias:
            print(f"  ! {pendencia}")
        print()

    print(f"Configuracao OK ({cfg.caminho})")
    print(f"  modo........: {cfg.modo.upper()}")
    print(f"  fonte.......: {cfg.coleta.get('fonte', 'tse')}")
    print(f"  pleito......: {cfg.tse.get('pleito', '-')} / eleicao {cfg.tse.get('eleicao', '-')}")
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
    print(f"\nPreencha o codigo em telao.yaml, na secao:  modos: {cfg.modo}: tse:")
    print("  pleito: \"<codigo>\"")
    print("  eleicao: \"<codigo>\"")
    print("\nCada modo tem os seus - preencha os dois agora e trocar de teste")
    print("para o ar vira uma linha so, em vez de editar config no domingo.")
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
    contra_o_tse = str(cfg.coleta.get("fonte", "tse")).lower() == "tse"
    if contra_o_tse:
        _faixa_modo(cfg)

    erros, pendencias = cfg.conferir()
    # Pendencia (codigo do pleito em branco) so barra quem vai falar com o
    # TSE: com o simulador interno ela nao atrapalha nada, e e assim que o
    # ensaio e a conferencia do pacote funcionam antes de o TSE publicar.
    if contra_o_tse:
        erros = erros + pendencias
    if erros:
        print("Configuracao invalida; corrija antes de executar:")
        for problema in erros:
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
    """Um ciclo so, sem tocar o TSE: telas prontas para a arte conferir.

    Com --em-branco as telas saem com a estrutura completa e nenhum dado: e o
    que o pacote entregue leva, para o PC de exibicao ja ter pagina e desenho
    antes do primeiro boletim, sem um unico nome inventado no disco.
    """
    cfg = _cfg(args)
    _log(cfg, args)
    em_branco = bool(getattr(args, "em_branco", False))
    cfg.bruto.setdefault("coleta", {})["fonte"] = "em-branco" if em_branco else "simulador"
    cfg.bruto["coleta"]["simulador_progresso"] = args.progresso
    # o historico nunca recebe ponto que nao veio do TSE
    cfg.bruto["coleta"]["historico"] = False
    # nao ha 'bloquear_nao_oficial' para desligar aqui: a trava e decidida
    # pelo modo, e o simulador interno passa por ela de qualquer jeito
    if args.pasta:
        cfg.bruto.setdefault("saida", {})["destino"] = args.pasta
        # o vertical vai junto: sem isto ele continuaria gravando na pasta de
        # producao enquanto o resto do exemplo vai para a pasta de conferencia
        if cfg.bruto.get("vertical", {}).get("ativo"):
            cfg.bruto["vertical"]["destino"] = str(Path(args.pasta) / "vertical")
    if em_branco:
        print(f"Gerando as telas EM BRANCO em {cfg.destino}...")
    else:
        print(f"Gerando as telas em {cfg.destino} com {args.progresso:.0f}% apurado...")
    codigo = _executar(cfg, args, uma_vez=True)
    if em_branco:
        print("Conteudo: NENHUM. Zeros e travessoes ate o TSE publicar.")
    else:
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
    p_exemplo.add_argument("--em-branco", action="store_true",
                           help="estrutura completa, sem nome nem numero inventado")
    p_exemplo.set_defaults(func=cmd_exemplo)

    p_mesa = sub.add_parser("mesa", help="janela para escolher a tela que vai ao ar")
    p_mesa.add_argument("--pasta", help="pasta do telao (padrao: a da config)")
    p_mesa.set_defaults(func=cmd_mesa)

    p_no_ar = sub.add_parser("no-ar", help="escolhe a tela sem abrir janela")
    p_no_ar.add_argument("tela", nargs="?", help="id da tela (vazio lista as disponiveis)")
    p_no_ar.add_argument("--listar", action="store_true", help="so lista, nao troca")
    p_no_ar.add_argument("--pasta", help="pasta do telao (padrao: a da config)")
    p_no_ar.set_defaults(func=cmd_no_ar)

    p_modo = sub.add_parser("modo", help="mostra ou troca entre Simulado e Producao")
    p_modo.add_argument("novo", nargs="?", help="simulado | producao (vazio so mostra)")
    p_modo.set_defaults(func=cmd_modo)

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
