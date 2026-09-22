"""Interface de linha de comando.

  gctse modo           mostra ou troca entre simulado e producao
  gctse validar        confere a configuracao antes do ar
  gctse descobrir      lista os pleitos publicados pelo TSE (codigos p/ config)
  gctse inspecionar    baixa um arquivo do TSE e mostra as chaves reais
  gctse uma-vez        executa um unico ciclo (bom para agendador/teste)
  gctse rodar          loop continuo de operacao
  gctse ensaio         loop continuo com dados simulados
  gctse amostrar       grava o JSON atual do TSE em dados/amostras
  gctse celulas        mostra qual celula guarda qual campo (ClassX LiveBoard)
  gctse exemplo        gera arquivos de exemplo + mapa, para montar a cena hoje
                       (--em-branco: estrutura sem nenhum dado inventado)
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import tempfile
from pathlib import Path

from . import __version__
from .config import MODOS, ErroConfig, carregar
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


def _faixa_modo(cfg) -> None:
    """Diz em que modo o sistema esta, de um jeito que nao passa batido.

    Subir em Simulado achando que esta em Producao - ou o contrario - e o erro
    mais caro possivel aqui, e ele e silencioso: os dois modos leem o TSE e
    escrevem as mesmas tarjas, nos mesmos caminhos. A unica defesa barata e
    gritar na partida.
    """
    if cfg.simulado:
        print("=" * 66)
        print("  MODO SIMULADO - dados de TESTE do TSE")
        print("  Todas as tarjas saem carimbadas. NAO use no dia da eleicao.")
        print("=" * 66)
    else:
        print("-" * 66)
        print("  MODO PRODUCAO - so boletim oficial (fase 'O')")
        print("-" * 66)


def cmd_modo(args) -> int:
    """Mostra o modo, ou troca gravando no proprio config.yaml."""
    cfg = _cfg(args)
    _iniciar_log(cfg, args)

    if not args.novo:
        print(f"Modo atual: {cfg.modo.upper()}")
        if os.environ.get("GCTSE_MODO"):
            print(f"  (vindo da variavel GCTSE_MODO={os.environ['GCTSE_MODO']},")
            print("   que tem prioridade sobre o arquivo)")
        print(f"  pleito {cfg.tse.get('pleito', '-')} / eleicao {cfg.tse.get('eleicao', '-')}")
        print(f"  aceita fase simulada: {'sim' if cfg.simulado else 'nao'}")
        print("\nPara trocar:  gctse modo simulado   |   gctse modo producao")
        return 0

    novo = str(args.novo).strip().lower()
    if novo not in MODOS:
        print(f"Modo '{args.novo}' desconhecido. Use: {' ou '.join(MODOS)}")
        return 1

    if cfg.caminho.suffix.lower() not in (".yaml", ".yml"):
        # a reescrita e linha a linha, de YAML; aplicada a um .json quebraria
        # o arquivo de vez, e sem config nenhuma o gctse nao sobe
        print(f"'{cfg.caminho}' nao e YAML, entao nao sei reescrever a linha do modo.")
        print(f"Edite o arquivo e ponha:  \"modo\": \"{novo}\"")
        print(f"Ou rode com a variavel:   set GCTSE_MODO={novo}")
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
    if os.environ.get("GCTSE_MODO"):
        print(f"ATENCAO: a variavel GCTSE_MODO={os.environ['GCTSE_MODO']} continua valendo")
        print("nesta janela e tem prioridade sobre o arquivo.")
    return 0


def cmd_validar(args) -> int:
    cfg = _cfg(args)
    _iniciar_log(cfg, args)
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
    print(f"  modo.........: {cfg.modo.upper()}")
    print(f"  pleito.......: {cfg.tse.get('pleito', '-')} / eleicao {cfg.tse.get('eleicao', '-')}")
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


def cmd_exemplo(args) -> int:
    """Gera os arquivos exatamente como sairao no ar, para amarrar a cena hoje.

    Os nomes de campo, a estrutura e os caminhos sao os do dia da eleicao. So
    o conteudo e que nao vem do TSE, e ha duas formas dele:

      --em-branco   estrutura completa, tudo zerado e com travessao no lugar
                    dos nomes. E o que o pacote entregue leva: da para vincular
                    campo por campo sem um unico nome inventado em disco.
      (sem a flag)  chapa ficticia com placar cheio, util para ver a cena
                    montada, com barra e foto, antes de existir dado real.

    Com --destinos-reais grava nas pastas que a config ja usa. E o modo
    recomendado: o GC aponta, desde o primeiro dia, para o MESMO caminho que
    recebera o dado do TSE - nao existe o passo de "trocar o caminho antes do
    ar", que e onde esse tipo de montagem costuma falhar.
    """
    cfg = _cfg(args)
    _iniciar_log(cfg, args)

    reais = bool(getattr(args, "destinos_reais", False))
    em_branco = bool(getattr(args, "em_branco", False))
    pasta = Path(args.pasta)
    temporarios = pasta if not reais else Path(tempfile.gettempdir())

    coleta = cfg.bruto.setdefault("coleta", {})
    coleta["fonte"] = "em-branco" if em_branco else "simulador"
    coleta["simulador_progresso"] = args.progresso
    coleta.pop("arquivo_saude", None)
    # Estado e historico vao para arquivo descartavel SEMPRE, inclusive com
    # --destinos-reais: mesmo o exemplo gravando nos caminhos de producao, um
    # ponto que nao veio do TSE nao pode entrar na serie que alimenta a curva
    # e a previsao de fechamento da noite.
    coleta["arquivo_estado"] = str(temporarios / ".exemplo-estado.json")
    coleta["arquivo_historico"] = str(temporarios / ".exemplo-historico.jsonl")
    if not reais:
        coleta["arquivo_graficos"] = str(pasta / "graficos.json")
        cfg.bruto.setdefault("saida", {})["destino"] = str(pasta)
        for nome, opcoes in cfg.exporters.items():
            opcoes["destino"] = str(pasta / nome)

    problemas = cfg.validar()
    if problemas:
        for problema in problemas:
            print(f"  - {problema}")
        return 1

    if em_branco:
        print(f"Gerando a estrutura EM BRANCO em {pasta}...\n")
    else:
        print(f"Gerando exemplos em {pasta} com {args.progresso:.0f}% apurado...\n")
    pipeline = Pipeline(cfg)
    try:
        resultados = pipeline.rodar_uma_vez()
    finally:
        pipeline.fechar()
    for nome, situacao in sorted(resultados.items()):
        print(f"  {nome}: {situacao}")

    for temporario in (
        Path(coleta["arquivo_estado"]),
        Path(coleta["arquivo_historico"]),
    ):
        temporario.unlink(missing_ok=True)

    # O mapa de celulas e o unico subproduto que vale a pena guardar junto do
    # pacote: diz qual campo do JSON alimenta qual item da cena. Com
    # --destinos-reais ele vai para uma pasta de nome obvio, ao lado das
    # tarjas, em vez de uma 'exemplos/' que ninguem sabe de onde saiu.
    args.pasta = str(Path("MAPA-CASTALIA") if reais else pasta / "mapa")
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
    if em_branco:
        print("Conteudo: NENHUM. Zeros e travessoes ate o TSE publicar.")
    else:
        print("ATENCAO: conteudo ficticio, fase 'S'. Nao use no ar.")
    return 0


def _executar(cfg, args, uma_vez: bool) -> int:
    _faixa_modo(cfg)
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

    p_modo = sub.add_parser("modo", help="mostra ou troca entre simulado e producao")
    p_modo.add_argument("novo", nargs="?", choices=MODOS, help="deixe vazio para so consultar")
    p_modo.set_defaults(func=cmd_modo)

    sub.add_parser("uma-vez", help="executa um unico ciclo").set_defaults(func=cmd_uma_vez)
    sub.add_parser("rodar", help="loop continuo de operacao").set_defaults(func=cmd_rodar)

    p_ensaio = sub.add_parser("ensaio", help="loop continuo com dados simulados")
    p_ensaio.add_argument("--duracao", type=int, default=900, help="segundos ate 100%% apurado (padrao: 900)")
    p_ensaio.add_argument("--progresso", type=float, help="trava a apuracao neste percentual")
    p_ensaio.set_defaults(func=cmd_ensaio)

    p_exemplo = sub.add_parser("exemplo", help="gera arquivos de exemplo + mapa para montar a cena")
    p_exemplo.add_argument("--pasta", default="exemplos", help="pasta de destino (padrao: exemplos)")
    p_exemplo.add_argument("--progresso", type=float, default=63.0, help="percentual apurado (padrao: 63)")
    p_exemplo.add_argument("--destinos-reais", action="store_true",
                           help="grava nas pastas da config, nao numa pasta separada")
    p_exemplo.add_argument("--em-branco", action="store_true",
                           help="estrutura completa, sem nome nem numero inventado")
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
