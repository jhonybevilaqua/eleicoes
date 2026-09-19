"""Interface de linha de comando.

  gctse validar        confere a configuracao antes do ar
  gctse descobrir      lista os pleitos publicados pelo TSE (codigos p/ config)
  gctse inspecionar    baixa um arquivo do TSE e mostra as chaves reais
  gctse uma-vez        executa um unico ciclo (bom para agendador/teste)
  gctse rodar          loop continuo de operacao
  gctse ensaio         loop continuo com dados simulados
  gctse amostrar       grava o JSON atual do TSE em dados/amostras
  gctse celulas        mostra qual celula guarda qual campo (ClassX LiveBoard)
  gctse exemplo        gera arquivos de exemplo + mapa, para montar a cena hoje
  gctse mesa           janela para escolher o quadro do telao que vai ao ar
  gctse no-ar          escolhe o quadro pela linha de comando (sem janela)
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from pathlib import Path

from . import __version__
from .config import ErroConfig, carregar
from .exporters import criar
from .exporters.classx import ExporterClassX
from .modelos import CARGOS, Apuracao
from .pipeline import Pipeline
from .tse.cliente import ClienteTSE
from .tse.descoberta import inspecionar, listar_eleicoes
from .tse.endpoints import Endpoints
from .util.log import configurar

def _config_padrao() -> str:
    """config.yaml na raiz da pasta; config/config.yaml como alternativa.

    Na raiz e onde a pessoa espera encontrar - e onde ela vai editar. A pasta
    config/ segue valendo para quem trabalha a partir do codigo-fonte.
    """
    for candidato in ("config.yaml", "config/config.yaml"):
        if Path(candidato).exists():
            return candidato
    return "config.yaml"


PADRAO_CONFIG = "config/config.yaml"


def _ancorar_na_pasta_do_executavel() -> None:
    """No executavel empacotado, trabalha a partir da pasta do proprio .exe.

    Sem isso, dar duplo clique no gctse.exe faz o processo herdar um diretorio
    de trabalho qualquer (as vezes C:\Windows\System32) e todos os caminhos
    relativos da config - config/, dados/saida/, logs/ - apontam para o lugar
    errado. Ancorar aqui e o que permite distribuir uma pasta autocontida.
    """
    if getattr(sys, "frozen", False):
        os.chdir(Path(sys.executable).resolve().parent)


def _cfg(args):
    return carregar(args.config or _config_padrao())


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


def cmd_celulas(args, cfg=None) -> int:
    """Mapa de vinculo por celula, para amarrar a cena no LiveBoard.

    O mapa depende so da configuracao do exporter - nao precisa de dado do
    TSE - entao pode ser gerado semanas antes do pleito e entregue ao
    operador junto com o roteiro da cena.

    Recebe 'cfg' ja carregada quando chamado por outro comando (o 'exemplo'
    redireciona os destinos em memoria; recarregar do disco perderia isso).
    """
    if cfg is None:
        cfg = _cfg(args)
        _iniciar_log(cfg, args)

    pasta = Path(args.pasta) if args.pasta else None
    if pasta:
        pasta.mkdir(parents=True, exist_ok=True)

    encontrados = 0
    for alvo in cfg.alvos:
        for nome_exporter in alvo.exporters:
            opcoes = cfg.exporters.get(nome_exporter) or {}
            if str(opcoes.get("tipo", "")).lower() != "classx":
                continue
            exporter = criar(nome_exporter, opcoes, cfg.texto, cfg.saida)
            if not isinstance(exporter, ExporterClassX):
                continue
            encontrados += 1

            referencia = Apuracao(
                cargo_codigo=alvo.cargo,
                cargo_nome=CARGOS.get(alvo.cargo, f"Cargo {alvo.cargo}"),
                abrangencia_codigo=alvo.abrangencia.upper(),
                abrangencia_nome=alvo.apelido_abrangencia or alvo.abrangencia.upper(),
                turno=alvo.turno,
            )
            principal = exporter.caminho_saida(referencia, alvo.nome, exporter.extensao)
            nomes = {"principal": principal.name, "-resumo": principal.stem + "-resumo" + exporter.extensao}

            itens = exporter.mapa_celulas()
            estruturado = exporter.formato in ("json", "xml")
            rotulo = "CAMINHO" if estruturado else "CELULA"
            largura = max([len(rotulo)] + [len(i["celula"]) for i in itens]) + 2

            descricao = f"formato {exporter.formato}"
            if not estruturado:
                descricao += f"  /  layout {exporter.layout}"
            print(f"\n=== {alvo.nome}  /  exporter '{nome_exporter}'  /  {descricao}  /  ordem {exporter.ordem}")
            print(f"    arquivo: {principal}")
            if not estruturado and exporter.layout == "grade":
                print(f"    resumo.: {principal.with_name(nomes['-resumo'])}")
            print(f"    {rotulo:<{largura}} {'CAMPO':<26} OBSERVACAO")

            linhas_csv = [["arquivo", rotulo.lower(), "campo", "observacao"]]
            for item in itens:
                arquivo = nomes.get(item["arquivo"], item["arquivo"])
                print(f"    {item['celula']:<{largura}} {item['campo']:<26} {item['origem']}")
                linhas_csv.append([arquivo, item["celula"], item["campo"], item["origem"]])

            if pasta:
                destino = pasta / f"mapa-celulas-{alvo.nome}-{nome_exporter}.csv"
                with open(destino, "w", encoding="utf-8-sig", newline="") as fh:
                    csv.writer(fh, delimiter=";").writerows(linhas_csv)
                print(f"    -> mapa gravado em {destino}")

    if not encontrados:
        print("Nenhum exporter do tipo 'classx' associado aos alvos configurados.")
        return 1
    print("\nAs referencias so mudam se voce alterar formato, layout, ordem, slots")
    print("ou as listas de campos. Se mudar, gere o mapa de novo e refaca os vinculos.")
    return 0


def _pasta_telao(cfg, args) -> Path:
    """Pasta do telao: a da linha de comando, senao a da config."""
    if getattr(args, "pasta", None):
        return Path(args.pasta)
    return Path((cfg.telao or {}).get("destino", "dados/saida/telao"))


def cmd_mesa(args) -> int:
    """Janela com um botao por quadro, para escolher o que vai ao ar."""
    from .mesa import abrir

    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    return abrir(_pasta_telao(cfg, args))


def cmd_no_ar(args) -> int:
    """Mesma escolha da mesa, sem janela - para atalho, .bat ou agendador."""
    from .mesa import escrever_no_ar, ler_no_ar, ler_quadros

    cfg = _cfg(args)
    _iniciar_log(cfg, args)
    pasta = _pasta_telao(cfg, args)
    quadros = ler_quadros(pasta)

    if args.listar or not args.quadro:
        if not quadros:
            print(f"Nenhum quadro publicado em {pasta}.")
            print("O telao grava 'quadros.json' depois do primeiro ciclo.")
            return 1
        atual = ler_no_ar(pasta)
        print(f"Quadros em {pasta}:\n")
        for indice, quadro in enumerate(quadros, start=1):
            marca = "  <- no ar" if quadro["id"] == atual else ""
            print(f"  {indice}. {quadro['id']:<20} {quadro.get('titulo', '')}{marca}")
        print("\nUse: gctse no-ar <id>")
        return 0

    conhecidos = {q["id"] for q in quadros}
    if quadros and args.quadro not in conhecidos:
        print(f"Quadro '{args.quadro}' nao existe. Conhecidos: {', '.join(sorted(conhecidos))}")
        return 1
    escrever_no_ar(pasta, args.quadro)
    print(f"No ar: {args.quadro}")
    return 0


def cmd_exemplo(args) -> int:
    """Gera, com dados ficticios, os arquivos exatamente como sairao no ar.

    Serve para o time montar e amarrar a cena do GC agora, meses antes de o
    TSE publicar qualquer coisa: os nomes de campo, a estrutura e os caminhos
    sao os mesmos do dia da eleicao - so o conteudo e inventado.

    Com --destinos-reais grava nas pastas que a config ja usa, em vez de numa
    pasta separada. E o modo recomendado para montar a cena: o GC passa a
    apontar, desde o primeiro dia, para o MESMO caminho que recebera o dado
    real - nao existe o passo de "trocar o caminho antes do ar", que e onde
    esse tipo de montagem costuma falhar.
    """
    cfg = _cfg(args)
    _iniciar_log(cfg, args)

    reais = bool(getattr(args, "destinos_reais", False))
    pasta = Path(args.pasta)
    coleta = cfg.bruto.setdefault("coleta", {})
    coleta["fonte"] = "simulador"
    coleta["simulador_progresso"] = args.progresso
    coleta["arquivo_estado"] = str(pasta / ".estado.json") if not reais else coleta.get(
        "arquivo_estado", "dados/estado/estado.json"
    )
    coleta.pop("arquivo_saude", None)
    if not reais:
        # O exemplo nao pode escrever no historico de verdade: um ponto
        # ficticio no meio da serie estragaria a curva e a previsao do dia.
        coleta["arquivo_historico"] = str(pasta / ".historico.jsonl")
        coleta["arquivo_graficos"] = str(pasta / "graficos.json")
    cfg.bruto.setdefault("seguranca", {})["bloquear_nao_oficial"] = False
    if not reais:
        cfg.bruto.setdefault("saida", {})["destino"] = str(pasta)
        for nome, opcoes in cfg.exporters.items():
            opcoes["destino"] = str(pasta / nome)

    problemas = cfg.validar()
    if problemas:
        for problema in problemas:
            print(f"  - {problema}")
        return 1

    print(f"Gerando exemplos em {pasta} com {args.progresso:.0f}% apurado...\n")
    pipeline = Pipeline(cfg)
    try:
        resultados = pipeline.rodar_uma_vez()
    finally:
        pipeline.fechar()
    for nome, situacao in sorted(resultados.items()):
        print(f"  {nome}: {situacao}")

    if not reais:
        for temporario in (pasta / ".estado.json", pasta / ".historico.jsonl"):
            if temporario.exists():
                temporario.unlink()

    args.pasta = str(pasta / "mapa")
    print()
    cmd_celulas(args, cfg)

    if reais:
        print("\nArquivos gravados NOS DESTINOS REAIS da configuracao.")
        print("Aponte o DataSource do GC para eles e monte a cena: quando o sistema")
        print("rodar, estes mesmos arquivos passam a receber o dado do TSE.")
        print("Nao ha caminho para trocar depois - que e onde esse tipo de montagem falha.")
    else:
        print(f"\nArquivos de exemplo em {pasta}. Aponte o DataSource do GC para eles")
        print("e monte a cena agora; no dia, os mesmos caminhos recebem o dado real.")
    print("ATENCAO: conteudo ficticio, fase 'S'. Nao use no ar.")
    return 0


def _executar(cfg, args, uma_vez: bool) -> int:
    if getattr(args, "permitir_nao_oficial", False):
        # Trava por invocacao, nao por arquivo: no teste com o simulado do TSE
        # e preciso aceitar fase 'S', e uma flag de linha de comando nao pode
        # ser esquecida ligada - o proximo 'rodar' ja volta protegido.
        cfg.bruto.setdefault("seguranca", {})["bloquear_nao_oficial"] = False
        print("!" * 66)
        print("  ATENCAO: aceitando boletim NAO OFICIAL (fase 'S').")
        print("  Use so em teste. Nao coloque esta saida no ar.")
        print("!" * 66)
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
    # Ensaio tem historico proprio: a curva do ensaio nao entra na serie que o
    # coordenador vai ler no dia.
    cfg.bruto["coleta"]["arquivo_historico"] = "dados/estado/ensaio-historico.jsonl"
    cfg.bruto["coleta"]["arquivo_graficos"] = "dados/estado/ensaio-graficos.json"
    cfg.bruto["coleta"]["simulador_duracao_segundos"] = args.duracao
    if args.progresso is not None:
        cfg.bruto["coleta"]["simulador_progresso"] = args.progresso
    cfg.bruto.setdefault("seguranca", {})["bloquear_nao_oficial"] = False
    print(f"ENSAIO: dados simulados, apuracao completa em ~{args.duracao}s. Ctrl+C encerra.")
    return _executar(cfg, args, uma_vez=False)


def construir_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gctse",
        description="Automacao de apuracao eleitoral do TSE para sistemas de GC.",
    )
    parser.add_argument("-c", "--config", default=None,
                        help="arquivo de configuracao (padrao: config.yaml na pasta do programa)")
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

    p_celulas = sub.add_parser("celulas", help="mapa de celulas dos exporters ClassX LiveBoard")
    p_celulas.add_argument("--pasta", help="grava o mapa em CSV nesta pasta")
    p_celulas.set_defaults(func=cmd_celulas)

    p_uma = sub.add_parser("uma-vez", help="executa um unico ciclo")
    p_uma.set_defaults(func=cmd_uma_vez)
    p_rodar = sub.add_parser("rodar", help="loop continuo de operacao")
    p_rodar.set_defaults(func=cmd_rodar)
    for sub_parser in (p_uma, p_rodar):
        sub_parser.add_argument(
            "--permitir-nao-oficial", action="store_true",
            help="aceita boletim em fase 'S' (simulado do TSE). SO PARA TESTE.",
        )

    p_ensaio = sub.add_parser("ensaio", help="loop continuo com dados simulados")
    p_ensaio.add_argument("--duracao", type=int, default=900, help="segundos ate 100%% apurado (padrao: 900)")
    p_ensaio.add_argument("--progresso", type=float, help="trava a apuracao neste percentual")
    p_ensaio.set_defaults(func=cmd_ensaio)

    p_mesa = sub.add_parser("mesa", help="janela para escolher o quadro do telao")
    p_mesa.add_argument("--pasta", help="pasta do telao (padrao: a da config)")
    p_mesa.set_defaults(func=cmd_mesa)

    p_no_ar = sub.add_parser("no-ar", help="escolhe o quadro do telao sem abrir janela")
    p_no_ar.add_argument("quadro", nargs="?", help="id do quadro (vazio lista os disponiveis)")
    p_no_ar.add_argument("--listar", action="store_true", help="so lista, nao troca")
    p_no_ar.add_argument("--pasta", help="pasta do telao (padrao: a da config)")
    p_no_ar.set_defaults(func=cmd_no_ar)

    p_exemplo = sub.add_parser("exemplo", help="gera arquivos de exemplo + mapa para montar a cena")
    p_exemplo.add_argument("--pasta", default="exemplos", help="pasta de destino (padrao: exemplos)")
    p_exemplo.add_argument("--progresso", type=float, default=63.0, help="percentual apurado (padrao: 63)")
    p_exemplo.add_argument("--destinos-reais", action="store_true",
                           help="grava nas pastas da config, nao numa pasta separada")
    p_exemplo.set_defaults(func=cmd_exemplo)

    return parser


def main(argv: list[str] | None = None) -> int:
    _ancorar_na_pasta_do_executavel()
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
    except BrokenPipeError:
        # saida canalizada para 'head'/'more' e fechada antes do fim
        try:
            sys.stdout.close()
        except BrokenPipeError:
            pass
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
