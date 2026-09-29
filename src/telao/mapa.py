"""Mapa do Brasil por UF, desenhado em SVG.

Recebe as 27 unidades da federacao e devolve o desenho pronto, pintado. E a
base de quatro das telas: as duas de mapa em tela cheia e as duas versoes
reduzidas que aparecem ao lado da lista de estados.

Dois modos, que respondem a perguntas diferentes:

  modo: partido    cada UF pinta com a cor do partido de quem lidera ali. E o
                   mapa classico de noite de eleicao: mostra o desenho politico
                   do pais num quadro so.
  modo: apuracao   cada UF pinta pela fracao de secoes ja totalizadas, do cinza
                   (nada) ao cheio (100%). E o mapa que "enche" ao vivo e
                   responde "quanto ja apurou onde".

O SVG e autocontido: sem fonte externa obrigatoria, sem script, sem imagem
ligada. Um arquivo que abre no navegador e no Illustrator sem depender de nada
que possa faltar no dia.

A UF cuja praca ainda nao publicou boletim sai em cinza, com a sigla legivel -
nunca some do desenho. Mapa com buraco e pior do que mapa com estado cinza: o
buraco parece erro de arte, o cinza informa que o dado nao chegou.
"""

from __future__ import annotations

from .malha_br import (
    CENTRO,
    CONTORNO,
    CREDITO,
    LEGENDA_EXTERNA,
    NOMES,
    VIEWBOX_ALTURA,
    VIEWBOX_LARGURA,
)
from .modelos import Apuracao
from .util.svg import (
    CINZA_SEM_DADO,
    COR_FUNDO,
    COR_TEXTO,
    contraste as _contraste,
    cor_de_reserva,
    escapar as _escapar,
    int_br as _int_br,
    mistura as _mistura,
    pct_br as _pct_br,
)

# Canvas do SVG: o mesmo 1920x1080 do projeto de video, para a arte entrar 1:1.
LARGURA = 1920
ALTURA = 1080

# Area do desenho do mapa dentro do canvas.
MAPA_X = 110.0
MAPA_Y = 170.0
MAPA_ESCALA = 1.22

# Coluna dos rotulos de estado pequeno e do painel lateral.
CHAMADA_X = MAPA_X + VIEWBOX_LARGURA * MAPA_ESCALA + 26
PAINEL_X = 1210.0

COR_TRACO = "#0b1220"


def _sigla(praca: str, ap: Apuracao | None) -> str:
    """Descobre a UF do registro, na ordem do que e mais confiavel.

    O apelido do alvo ja e a sigla na configuracao normal ('pr' vira 'PR'),
    mas quem apelida a praca de 'PARANA' nao pode perder o estado no mapa -
    dai a busca pelo nome por extenso como ultimo recurso.
    """
    candidatos = [praca]
    if ap is not None:
        candidatos += [ap.abrangencia_codigo, ap.abrangencia_nome]
    for bruto in candidatos:
        texto = str(bruto or "").strip().upper()
        if texto in CONTORNO:
            return texto
    por_nome = {nome.upper(): sigla for sigla, nome in NOMES.items()}
    for bruto in candidatos:
        texto = str(bruto or "").strip().upper()
        if texto in por_nome:
            return por_nome[texto]
    return ""







class Mapa:
    """O desenho do mapa, do dado ao SVG.

    Nao guarda estado entre chamadas: recebe as pracas, monta a estrutura e
    devolve o desenho. Quem decide quando redesenhar e o publicador.
    """

    def __init__(self, opcoes: dict | None = None, aparencia: dict | None = None):
        self.opcoes = opcoes or {}
        # 'aparencia' e o que a config do telao ja usa para as outras telas:
        # cores de partido, cor padrao, caixa do texto. O mapa le do mesmo
        # lugar para nao existirem duas paletas no mesmo ar.
        self.aparencia = aparencia or {}
        self.modo = str(self.opcoes.get("modo", "partido")).lower()
        self.titulo = str(self.opcoes.get("titulo", ""))
        self.rotulo = str(self.opcoes.get("rotulo", "sigla_pct")).lower()
        self.fonte = str(
            self.opcoes.get("fonte", "Barlow Condensed, Arial Narrow, Helvetica, sans-serif")
        )
        self.cor_fundo = str(self.opcoes.get("cor_fundo", COR_FUNDO))
        self.cor_sem_dado = str(self.opcoes.get("cor_sem_dado", CINZA_SEM_DADO))
        self.cor_escala = str(self.opcoes.get("cor_escala", "#2f97e8"))
        self.fundo_transparente = bool(self.opcoes.get("fundo_transparente", False))
        self.painel = bool(self.opcoes.get("painel", True))
        self.paleta_reserva = bool(self.opcoes.get("paleta_reserva", True))
        self.cores_partido = {
            str(k).strip().upper(): str(v)
            for k, v in (self.aparencia.get("cores_partido") or {}).items()
        }
        self.cor_padrao = str(self.aparencia.get("cor_padrao", "#6b86ab"))
        self.selo_texto = str(self.opcoes.get("selo_nao_oficial", ""))
        self.selo_sempre = bool(self.opcoes.get("selo_sempre", False))

    # --- leitura dos dados ---

    def montar(self, itens: list[tuple[int, str, Apuracao | None]]) -> dict:
        """Estrutura por UF. Tambem e o que o pipeline usa para deduplicar."""
        estados: dict[str, dict] = {}
        nacional: dict | None = None

        for _ordem, praca, ap in itens:
            sigla = _sigla(praca, ap)
            if ap is not None and ap.abrangencia_tipo.upper() == "BR" and not sigla:
                nacional = self._nacional(ap)
                continue
            if not sigla:
                continue
            estados[sigla] = self._estado(sigla, ap)

        for sigla in CONTORNO:
            estados.setdefault(sigla, self._estado(sigla, None))

        self._completar_cores(estados)

        com_dado = [e for e in estados.values() if e["visivel"]]
        totalizadas = sum(e["secoes_totalizadas"] for e in com_dado)
        total = sum(e["secoes_total"] for e in com_dado)

        return {
            "composicao": self._composicao_grupo(com_dado),
            "modo": self.modo,
            "titulo": self.titulo,
            "pracas_com_dado": len(com_dado),
            "pracas_total": len(estados),
            "secoes_totalizadas": totalizadas,
            "secoes_total": total,
            "apuracao_pct": round(100.0 * totalizadas / total, 2) if total else 0.0,
            "nacional": nacional,
            "selo": self._selo_do_mapa(com_dado),
            "hora_geracao": max((e["hora_geracao"] for e in com_dado), default=""),
            "estados": {sigla: estados[sigla] for sigla in sorted(estados)},
        }

    def _selo_do_mapa(self, com_dado: list[dict]) -> str:
        """O carimbo do mapa inteiro.

        Normalmente e o da primeira praca que trouxe um - basta uma praca nao
        oficial para o mapa todo nao ser resultado. Duas excecoes carimbam
        mesmo sem praca nenhuma dizer nada:

        - 'selo_sempre' (modo simulado), que nao negocia com a fase; sem isto
          o mapa saia limpo num dia de teste enquanto as telas vizinhas saiam
          carimbadas, e o telespectador so ve a que esta no ar;
        - mapa sem praca alguma com boletim, que e um desenho completo do
          Brasil sem um unico dado - o oposto de um resultado oficial.
        """
        for estado in com_dado:
            if estado["selo"]:
                return estado["selo"]
        if self.selo_sempre or not com_dado:
            return self.selo_texto
        return ""

    def _completar_cores(self, estados: dict[str, dict]) -> None:
        """Da cor aos partidos que a config nao nomeou, e so entao pinta.

        A atribuicao roda depois de montar o mapa inteiro, sobre a lista
        ORDENADA de partidos presentes: assim o mesmo partido recebe a mesma
        cor em todos os ciclos da noite, e nao muda de cor a cada boletim.
        """
        if self.paleta_reserva:
            sem_cor = sorted(
                {
                    lider["partido"]
                    for estado in estados.values()
                    if (lider := estado.get("lider")) and not lider["cor_definida"] and lider["partido"]
                }
            )
            reserva = {
                partido: cor_de_reserva(indice) for indice, partido in enumerate(sem_cor)
            }
            for estado in estados.values():
                lider = estado.get("lider")
                if lider and not lider["cor_definida"]:
                    lider["cor"] = reserva.get(lider["partido"], lider["cor"])

        for estado in estados.values():
            estado["cor"] = self._cor_estado(estado)

    def _composicao_grupo(self, com_dado: list[dict]) -> dict:
        """Validos, brancos, nulos e abstencao somados nas pracas com boletim.

        Soma das UFs, nao o arquivo nacional do TSE: assim o bloco existe mesmo
        quando o grupo nao inclui o alvo 'br', e nunca mistura as duas fontes.
        Enquanto faltam pracas, e a composicao DO QUE JA CHEGOU - por isso o
        desenho diz quantas pracas entraram na conta.
        """
        somar = lambda campo: sum(e["votos"][campo] for e in com_dado)  # noqa: E731
        if not com_dado:
            return {"pracas": 0, "apurados": 0, "validos": 0, "brancos": 0, "nulos": 0,
                    "abstencao": 0, "eleitorado_apto": 0, "pct_validos": 0.0,
                    "pct_brancos": 0.0, "pct_nulos": 0.0, "pct_brancos_nulos": 0.0,
                    "pct_abstencao": 0.0}

        validos, brancos, nulos = somar("validos"), somar("brancos"), somar("nulos")
        apurados = validos + brancos + nulos
        abstencao, aptos = somar("abstencao"), somar("eleitorado_apto")
        fatia = lambda valor, base: round(100.0 * valor / base, 2) if base else 0.0  # noqa: E731
        return {
            "pracas": len(com_dado),
            "apurados": apurados,
            "validos": validos,
            "brancos": brancos,
            "nulos": nulos,
            "abstencao": abstencao,
            "eleitorado_apto": aptos,
            "pct_validos": fatia(validos, apurados),
            "pct_brancos": fatia(brancos, apurados),
            "pct_nulos": fatia(nulos, apurados),
            "pct_brancos_nulos": fatia(brancos + nulos, apurados),
            "pct_abstencao": fatia(abstencao, aptos),
        }

    def _nacional(self, ap: Apuracao) -> dict:
        return {
            "abrangencia": (ap.abrangencia_nome or "").upper(),
            "apuracao_pct": ap.pct_secoes,
            "secoes_totalizadas": ap.secoes_totalizadas,
            "secoes_total": ap.secoes_total,
            "votos_brancos": ap.votos_brancos,
            "votos_nulos": ap.votos_nulos,
            "pct_brancos": ap.pct_brancos,
            "pct_nulos": ap.pct_nulos,
            "pct_abstencao": ap.pct_abstencao,
        }

    def _estado(self, sigla: str, ap: Apuracao | None) -> dict:
        base = {
            "sigla": sigla,
            "nome": NOMES.get(sigla, sigla),
            "visivel": ap is not None,
            "apuracao_pct": 0.0,
            "secoes_totalizadas": 0,
            "secoes_total": 0,
            "selo": "",
            "hora_geracao": "",
            "lider": None,
            "segundo": None,
            "votos": {"validos": 0, "brancos": 0, "nulos": 0, "abstencao": 0,
                      "eleitorado_apto": 0, "comparecimento": 0},
        }
        if ap is None:
            base["cor"] = self.cor_sem_dado
            return base

        base.update(
            {
                "apuracao_pct": ap.pct_secoes,
                "secoes_totalizadas": ap.secoes_totalizadas,
                "secoes_total": ap.secoes_total,
                "selo": self._selo(ap),
                "hora_geracao": ap.gerado_em.strftime("%H:%M") if ap.gerado_em else "",
                "lider": self._chapa(ap, 0),
                "segundo": self._chapa(ap, 1),
                "diferenca_pct": ap.diferenca_pct,
                "pct_brancos": ap.pct_brancos,
                "pct_nulos": ap.pct_nulos,
                "pct_abstencao": ap.pct_abstencao,
                "votos": {
                    "validos": ap.votos_validos,
                    "brancos": ap.votos_brancos,
                    "nulos": ap.votos_nulos,
                    "abstencao": ap.abstencao,
                    "eleitorado_apto": ap.eleitorado_apto,
                    "comparecimento": ap.comparecimento,
                },
            }
        )
        return base

    def _chapa(self, ap: Apuracao, indice: int) -> dict | None:
        if len(ap.candidatos) <= indice:
            return None
        if ap.votos_validos <= 0:
            # Boletim publicado com zero voto apurado - o que acontece de
            # verdade nos primeiros minutos da noite, e o tempo todo com a
            # estrutura em branco. Sem voto nao ha quem lidere: devolver o
            # primeiro da lista pintaria o estado com a cor de um partido que
            # nao ganhou nada ali. Sem lider, o mapa pinta de cinza, que e a
            # verdade.
            return None
        cand = ap.candidatos[indice]
        sigla = (cand.partido or "").strip().upper()
        return {
            "cor_definida": bool(self.cores_partido.get(sigla)),
            "nome": (cand.nome or "").upper(),
            "partido": sigla,
            "numero": cand.numero,
            "votos": cand.votos,
            "percentual": cand.percentual,
            "eleito": cand.eleito,
            "cor": self.cores_partido.get(sigla) or self.cor_padrao,
        }

    def _selo(self, ap: Apuracao) -> str:
        """Carimbo de fase da praca. Em simulado, sai sempre."""
        if ap.oficial and not self.selo_sempre:
            return ""
        return self.selo_texto

    def _cor_estado(self, estado: dict) -> str:
        if self.modo == "apuracao":
            # Cinza com 0%, cor cheia com 100%: o mapa enche junto com a
            # apuracao, e a leitura nao depende de ler numero nenhum.
            return _mistura(self.cor_sem_dado, self.cor_escala, estado["apuracao_pct"] / 100.0)
        lider = estado.get("lider")
        if not lider:
            return self.cor_sem_dado
        return lider["cor"] or self.cor_sem_dado

    # --- desenho ---

    def desenhar(self, dados: dict) -> str:
        estados = dados["estados"]
        partes: list[str] = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {LARGURA} {ALTURA}" '
            f'width="{LARGURA}" height="{ALTURA}" font-family="{_escapar(self.fonte)}">',
            f"<title>{_escapar(self.titulo or 'Apuracao por unidade da federacao')}</title>",
            f"<desc>{_escapar(CREDITO)}</desc>",
        ]
        if not self.fundo_transparente:
            partes.append(f'<rect width="{LARGURA}" height="{ALTURA}" fill="{self.cor_fundo}"/>')

        partes += self._cabecalho(dados)
        partes += self._desenho_estados(estados)
        partes += self._chamadas(estados)
        if self.painel:
            partes += self._painel(dados)
        partes.append(
            f'<text x="{MAPA_X}" y="{ALTURA - 26}" font-size="18" fill="#7d8aa0">'
            f"{_escapar(CREDITO)}</text>"
        )
        partes.append("</svg>")
        return "\n".join(partes)

    def _cabecalho(self, dados: dict) -> list[str]:
        titulo = (
            self.titulo
            or ("APURACAO POR ESTADO" if self.modo == "apuracao" else "LIDERANCA POR ESTADO")
        ).upper()
        # O titulo e escrito pelo usuario na config e pode ser longo: encolhe a
        # fonte em vez de passar por cima do selo de fase, que e a informacao
        # que nao pode ser encoberta em hipotese nenhuma.
        corpo = max(34, min(58, int(58 * 30 / max(len(titulo), 1))))
        linhas = [
            f'<text x="{MAPA_X}" y="86" font-size="{corpo}" font-weight="700" fill="{COR_TEXTO}" '
            f'letter-spacing="1">{_escapar(titulo)}</text>'
        ]
        if self.modo == "apuracao":
            sub = (
                f"{_int_br(dados['secoes_totalizadas'])} de {_int_br(dados['secoes_total'])}"
                f" urnas totalizadas  |  {_pct_br(dados['apuracao_pct'])}%"
            )
        else:
            sub = f"{dados['pracas_com_dado']} de {dados['pracas_total']} estados com boletim publicado"
        if dados.get("hora_geracao"):
            sub += f"  |  boletim das {dados['hora_geracao']}"
        linhas.append(
            f'<text x="{MAPA_X}" y="126" font-size="28" fill="#9fb0c9">{_escapar(sub)}</text>'
        )
        if dados.get("selo"):
            linhas.append(
                f'<rect x="{LARGURA - 470}" y="50" width="350" height="48" rx="4" fill="#c0392b"/>'
                f'<text x="{LARGURA - 295}" y="83" font-size="26" font-weight="600" fill="#ffffff" '
                f'text-anchor="middle">{_escapar(dados["selo"])}</text>'
            )
        return linhas

    def _desenho_estados(self, estados: dict) -> list[str]:
        partes = [f'<g transform="translate({MAPA_X},{MAPA_Y}) scale({MAPA_ESCALA})">']
        for sigla in sorted(CONTORNO):
            estado = estados.get(sigla) or {}
            cor = estado.get("cor", self.cor_sem_dado)
            partes.append(
                f'<path id="uf-{sigla.lower()}" d="{CONTORNO[sigla]}" fill="{cor}" '
                f'stroke="{COR_TRACO}" stroke-width="1.2" stroke-linejoin="round">'
                f"<title>{_escapar(self._dica(estado, sigla))}</title></path>"
            )
        partes.append("</g>")

        # Rotulos dentro do desenho, so nos estados que comportam texto.
        for sigla in sorted(CONTORNO):
            if sigla in LEGENDA_EXTERNA:
                continue
            estado = estados.get(sigla) or {}
            x, y = self._ponto(sigla)
            cor_texto = _contraste(estado.get("cor", self.cor_sem_dado))
            partes.append(
                f'<text x="{x:.1f}" y="{y:.1f}" font-size="26" font-weight="700" '
                f'fill="{cor_texto}" text-anchor="middle">{sigla}</text>'
            )
            segunda = self._segunda_linha(estado)
            if segunda:
                partes.append(
                    f'<text x="{x:.1f}" y="{y + 25:.1f}" font-size="21" fill="{cor_texto}" '
                    f'text-anchor="middle" opacity="0.92">{_escapar(segunda)}</text>'
                )
        return partes

    def _chamadas(self, estados: dict) -> list[str]:
        """Rotulo na margem, com linha de chamada, para os estados pequenos."""
        pequenos = sorted(LEGENDA_EXTERNA, key=lambda s: self._ponto(s)[1])
        partes: list[str] = []
        y_min, passo = 230.0, 46.0
        for indice, sigla in enumerate(pequenos):
            estado = estados.get(sigla) or {}
            origem_x, origem_y = self._ponto(sigla)
            destino_y = max(self._ponto(sigla)[1], y_min + indice * passo)
            cor = estado.get("cor", self.cor_sem_dado)
            partes.append(
                f'<path d="M {origem_x:.1f} {origem_y:.1f} L {CHAMADA_X - 14:.1f} {destino_y:.1f}" '
                f'stroke="#56637a" stroke-width="1.4" fill="none"/>'
            )
            partes.append(
                f'<rect x="{CHAMADA_X:.1f}" y="{destino_y - 17:.1f}" width="18" height="24" fill="{cor}"/>'
            )
            texto = sigla
            segunda = self._segunda_linha(estado)
            if segunda:
                texto = f"{sigla}  {segunda}"
            partes.append(
                f'<text x="{CHAMADA_X + 28:.1f}" y="{destino_y + 2:.1f}" font-size="24" '
                f'font-weight="600" fill="{COR_TEXTO}">{_escapar(texto)}</text>'
            )
        return partes

    def _segunda_linha(self, estado: dict) -> str:
        if not estado.get("visivel"):
            return "—"
        if self.rotulo == "sigla":
            return ""
        if self.rotulo == "sigla_lider":
            lider = estado.get("lider")
            return (lider or {}).get("partido", "") or "—"
        return f"{estado['apuracao_pct']:.0f}%"

    def _dica(self, estado: dict, sigla: str) -> str:
        if not estado.get("visivel"):
            return f"{NOMES.get(sigla, sigla)}: sem boletim"
        lider = estado.get("lider") or {}
        parte = f"{NOMES.get(sigla, sigla)}: {_pct_br(estado['apuracao_pct'])}% apurado"
        if lider:
            parte += (
                f" | {lider.get('nome', '')} ({lider.get('partido', '')})"
                f" {_pct_br(lider.get('percentual', 0))}%"
            )
        return parte

    def _ponto(self, sigla: str) -> tuple[float, float]:
        cx, cy = CENTRO[sigla]
        return MAPA_X + cx * MAPA_ESCALA, MAPA_Y + cy * MAPA_ESCALA

    def _painel(self, dados: dict) -> list[str]:
        if self.modo == "apuracao":
            return self._painel_escala(dados)
        return self._painel_partidos(dados)

    def _painel_partidos(self, dados: dict) -> list[str]:
        """Quantos estados cada partido lidera, do maior para o menor."""
        contagem: dict[str, dict] = {}
        for estado in dados["estados"].values():
            lider = estado.get("lider")
            if not estado.get("visivel") or not lider:
                continue
            sigla = lider["partido"] or "SEM PARTIDO"
            registro = contagem.setdefault(sigla, {"ufs": 0, "cor": lider["cor"]})
            registro["ufs"] += 1

        partes = [
            f'<text x="{PAINEL_X}" y="220" font-size="26" font-weight="600" fill="#9fb0c9" '
            f'letter-spacing="2">ESTADOS POR PARTIDO</text>'
        ]
        y = 272.0
        for sigla, registro in sorted(contagem.items(), key=lambda kv: (-kv[1]["ufs"], kv[0])):
            partes.append(
                f'<rect x="{PAINEL_X}" y="{y - 26:.0f}" width="34" height="34" rx="3" fill="{registro["cor"]}"/>'
                f'<text x="{PAINEL_X + 50}" y="{y:.0f}" font-size="32" font-weight="600" fill="{COR_TEXTO}">'
                f"{_escapar(sigla)}</text>"
                f'<text x="{LARGURA - 120}" y="{y:.0f}" font-size="32" fill="{COR_TEXTO}" '
                f'text-anchor="end">{registro["ufs"]}</text>'
            )
            y += 52
        if not contagem:
            partes.append(
                f'<text x="{PAINEL_X}" y="272" font-size="30" fill="#7d8aa0">aguardando boletim</text>'
            )
            return partes

        total = f"{_pct_br(dados['apuracao_pct'])}% das urnas totalizadas"
        partes.append(
            f'<rect x="{PAINEL_X}" y="{y - 16:.0f}" width="{LARGURA - PAINEL_X - 120}" height="1" fill="#2a3547"/>'
            f'<text x="{PAINEL_X}" y="{y + 30:.0f}" font-size="26" fill="#9fb0c9">'
            f"{_escapar(total)}</text>"
        )
        return partes + self._bloco_composicao(dados, y + 96)

    def _painel_escala(self, dados: dict) -> list[str]:
        partes = [
            f'<text x="{PAINEL_X}" y="196" font-size="26" font-weight="600" fill="#9fb0c9" '
            f'letter-spacing="2">TOTAL APURADO</text>',
            # o numero que interessa, em corpo de leitura, antes da escala
            f'<text x="{PAINEL_X}" y="268" font-size="72" font-weight="700" fill="{COR_TEXTO}">'
            f'{_int_br(dados["secoes_totalizadas"])}</text>',
            f'<text x="{PAINEL_X}" y="312" font-size="26" fill="#9fb0c9">'
            f'de {_int_br(dados["secoes_total"])} urnas  ·  {_pct_br(dados["apuracao_pct"])}%</text>',
        ]
        largura = LARGURA - PAINEL_X - 120
        for passo in range(11):
            fracao = passo / 10
            partes.append(
                f'<rect x="{PAINEL_X + largura * fracao:.1f}" y="334" width="{largura / 10:.1f}" '
                f'height="26" fill="{_mistura(self.cor_sem_dado, self.cor_escala, fracao)}"/>'
            )
        partes.append(
            f'<text x="{PAINEL_X}" y="384" font-size="22" fill="#9fb0c9">0%</text>'
            f'<text x="{PAINEL_X + largura:.0f}" y="384" font-size="22" fill="#9fb0c9" '
            f'text-anchor="end">100% das urnas do estado</text>'
        )

        # A lista mostra o TOTAL APURADO por praca, nao o que falta. As duas
        # respondem a mesma apuracao, mas so uma e noticia: "ja apuramos X" e
        # o numero que o apresentador le em voz alta; "faltam Y" e conta de
        # bastidor, que interessa a coordenacao e nao ao telespectador.
        com_dado = sorted(
            (e for e in dados["estados"].values() if e["visivel"]),
            key=lambda e: -e["apuracao_pct"],
        )
        partes.append(
            f'<text x="{PAINEL_X}" y="446" font-size="26" font-weight="600" fill="#9fb0c9" '
            f'letter-spacing="2">URNAS APURADAS POR ESTADO</text>'
        )
        if not com_dado:
            partes.append(
                f'<text x="{PAINEL_X}" y="500" font-size="30" fill="#7d8aa0">'
                f"aguardando boletim</text>"
            )
            return partes

        y = 500.0
        for estado in com_dado[:11]:
            apuradas = _int_br(estado["secoes_totalizadas"])
            partes.append(
                f'<text x="{PAINEL_X}" y="{y:.0f}" font-size="30" fill="{COR_TEXTO}">'
                f'{estado["sigla"]}</text>'
                f'<text x="{PAINEL_X + 80}" y="{y:.0f}" font-size="26" fill="#9fb0c9">'
                f"{_pct_br(estado['apuracao_pct'])}%</text>"
                f'<text x="{LARGURA - 120}" y="{y:.0f}" font-size="30" fill="{COR_TEXTO}" '
                f'text-anchor="end">{apuradas}</text>'
            )
            y += 44
        if len(com_dado) > 11:
            partes.append(
                f'<text x="{PAINEL_X}" y="{y + 8:.0f}" font-size="24" fill="#7d8aa0">'
                f"e mais {len(com_dado) - 11} praca(s)</text>"
            )
        return partes

    def _bloco_composicao(self, dados: dict, y: float) -> list[str]:
        """Barra empilhada de validos/brancos/nulos + abstencao, em uma linha.

        Ocupa o espaco que sobra do painel com o numero que mais rende pauta
        depois do placar, e que ja vem no mesmo boletim: quantos foram votar e
        quantos, tendo ido, nao escolheram ninguem.
        """
        comp = dados.get("composicao") or {}
        if not comp.get("apurados"):
            return []

        largura = LARGURA - PAINEL_X - 120
        cores = {"validos": "#4c6180", "brancos": "#d8dee9", "nulos": "#e8974a"}
        partes = [
            f'<text x="{PAINEL_X}" y="{y:.0f}" font-size="26" font-weight="600" fill="#9fb0c9" '
            f'letter-spacing="2">COMPOSICAO DO VOTO</text>'
        ]

        # mesma soma acumulada do exporter base: a barra fecha exata no trilho
        acumulado = 0.0
        borda = 0.0
        for fatia in ("validos", "brancos", "nulos"):
            acumulado += comp[f"pct_{fatia}"] / 100.0
            fim = round(largura * acumulado, 1)
            partes.append(
                f'<rect x="{PAINEL_X + borda:.1f}" y="{y + 24:.0f}" width="{max(0.0, fim - borda):.1f}" '
                f'height="30" fill="{cores[fatia]}"/>'
            )
            borda = fim

        linha = y + 92
        for rotulo, chave in (("Válidos", "validos"), ("Brancos", "brancos"), ("Nulos", "nulos")):
            partes.append(
                f'<rect x="{PAINEL_X}" y="{linha - 18:.0f}" width="16" height="16" fill="{cores[chave]}"/>'
                f'<text x="{PAINEL_X + 30}" y="{linha:.0f}" font-size="26" fill="{COR_TEXTO}">'
                f"{_escapar(rotulo)}</text>"
                f'<text x="{PAINEL_X + 250}" y="{linha:.0f}" font-size="26" fill="#9fb0c9" '
                f'text-anchor="end">{_pct_br(comp[f"pct_{chave}"])}%</text>'
                f'<text x="{LARGURA - 120}" y="{linha:.0f}" font-size="26" fill="{COR_TEXTO}" '
                f'text-anchor="end">{_int_br(comp[chave])}</text>'
            )
            linha += 38

        if comp.get("eleitorado_apto"):
            partes.append(
                f'<text x="{PAINEL_X}" y="{linha + 14:.0f}" font-size="26" fill="{COR_TEXTO}">Abstenção</text>'
                f'<text x="{PAINEL_X + 250}" y="{linha + 14:.0f}" font-size="26" fill="#9fb0c9" '
                f'text-anchor="end">{_pct_br(comp["pct_abstencao"])}%</text>'
                f'<text x="{LARGURA - 120}" y="{linha + 14:.0f}" font-size="26" fill="{COR_TEXTO}" '
                f'text-anchor="end">{_int_br(comp["abstencao"])}</text>'
            )
            linha += 38
        partes.append(
            f'<text x="{PAINEL_X}" y="{linha + 22:.0f}" font-size="21" fill="#7d8aa0">'
            f"soma de {comp['pracas']} praça(s) com boletim publicado</text>"
        )
        return partes
