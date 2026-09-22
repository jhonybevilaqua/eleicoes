"""Base comum dos exporters: contexto de campos, nomes de arquivo e guardas."""

from __future__ import annotations

import logging
import math
from abc import ABC, abstractmethod
from datetime import datetime
from pathlib import Path
from typing import Any

from ..modelos import Apuracao, Candidato
from ..util.numeros import formatar_int, formatar_pct
from ..util.texto import normalizar, slug

log = logging.getLogger("gctse.exporter")


class Exporter(ABC):
    tipo = "base"

    def __init__(self, *, nome: str, opcoes: dict, cfg_texto: dict, cfg_saida: dict):
        self.nome = nome
        self.opcoes = opcoes or {}
        # Cada tarja tem espaco diferente: o nome que cabe no placar de
        # presidente estoura na tarja de rodizio. Por isso o exporter pode
        # sobrepor o tratamento de texto, e 'limites' funde campo a campo em
        # vez de substituir o bloco inteiro.
        base_texto = dict(cfg_texto or {})
        proprio = dict((self.opcoes.get("texto") or {}))
        limites = {**(base_texto.get("limites") or {}), **(proprio.pop("limites", None) or {})}
        self.cfg_texto = {**base_texto, **proprio, "limites": limites}
        if base_texto.get("selo_sempre"):
            # O selo do modo simulado esta acima do exporter. Um bloco 'texto:'
            # de tarja poderia zera-lo sem querer - ajustando limite de nome,
            # por exemplo, e herdando um selo vazio -, e a tarja sairia limpa
            # num dia de teste. Nada aqui negocia isso.
            self.cfg_texto["selo_sempre"] = True
            self.cfg_texto["selo_nao_oficial"] = base_texto.get(
                "selo_nao_oficial", "SIMULADO"
            )
        self.cfg_saida = cfg_saida or {}
        self.destino = Path(self.opcoes.get("destino", self.cfg_saida.get("destino", "dados/saida")))
        self.encoding = str(self.opcoes.get("encoding", self.cfg_saida.get("encoding", "utf-8")))
        self.nova_linha = "\r\n" if str(self.opcoes.get("quebra_linha", self.cfg_saida.get("quebra_linha", "crlf"))).lower() == "crlf" else "\n"
        self.padrao_nome = str(self.opcoes.get("nome_arquivo", "{alvo}"))
        self.limite = int(self.opcoes.get("limite_candidatos", 0))

    # --- helpers de texto/numero ---

    def _txt(self, valor: Any, limite_chave: str = "") -> str:
        limite = int(self.cfg_texto.get("limites", {}).get(limite_chave, 0)) if limite_chave else 0
        return normalizar(
            valor,
            caixa=str(self.cfg_texto.get("caixa", "original")),
            remover_acentos=bool(self.cfg_texto.get("remover_acentos", False)),
            limite=limite,
            reticencia=str(self.cfg_texto.get("reticencia", "")),
        )

    def _num(self, valor: int) -> str:
        if self.cfg_texto.get("formatar_numeros", True):
            return formatar_int(valor, str(self.cfg_texto.get("separador_milhar", ".")))
        return str(valor)

    def _pct(self, valor: float) -> str:
        if self.cfg_texto.get("formatar_numeros", True):
            return formatar_pct(
                valor,
                int(self.cfg_texto.get("casas_percentual", 2)),
                str(self.cfg_texto.get("sufixo_percentual", "%")),
            )
        return str(valor)

    def _selo(self, ap: Apuracao) -> str:
        """O carimbo de 'isto nao e resultado'.

        Normalmente sai so em boletim fora da fase oficial. Em modo simulado,
        'selo_sempre' o mantem aceso mesmo em boletim marcado como oficial:
        num dia de teste, o que define se aquilo e resultado e o dia, nao o
        campo que veio no arquivo.
        """
        if ap.oficial and not bool(self.cfg_texto.get("selo_sempre", False)):
            return ""
        return str(self.cfg_texto.get("selo_nao_oficial", "SIMULADO"))

    # --- contexto exposto aos templates do GC ---

    def campos_resumo(self, ap: Apuracao) -> dict[str, str]:
        """Cabecalho do placar: cargo, abrangencia, apuracao, votos gerais."""
        return {
            "cargo": self._txt(ap.cargo_nome, "cargo"),
            "cargo_codigo": str(ap.cargo_codigo),
            "abrangencia": self._txt(ap.abrangencia_nome, "abrangencia"),
            "abrangencia_codigo": ap.abrangencia_codigo,
            "abrangencia_tipo": ap.abrangencia_tipo,
            "turno": str(ap.turno),
            "eleicao": ap.eleicao,
            "fase": ap.fase,
            "fase_nome": ap.fase_nome,
            "oficial": "1" if ap.oficial else "0",
            "totalizada": "1" if ap.totalizada else "0",
            "selo": self._selo(ap),
            "apuracao_pct": self._pct(ap.pct_secoes),
            "apuracao_pct_num": f"{ap.pct_secoes:.2f}",
            "secoes_totalizadas": self._num(ap.secoes_totalizadas),
            "secoes_total": self._num(ap.secoes_total),
            "eleitorado_apto": self._num(ap.eleitorado_apto),
            "comparecimento": self._num(ap.comparecimento),
            "abstencao": self._num(ap.abstencao),
            "votos_validos": self._num(ap.votos_validos),
            "votos_nominais": self._num(ap.votos_nominais),
            "votos_brancos": self._num(ap.votos_brancos),
            "votos_nulos": self._num(ap.votos_nulos),
            "total_apurado": self._num(ap.total_apurado),
            "votos_apurados": self._num(ap.votos_apurados),
            "votos_brancos_nulos": self._num(ap.votos_brancos + ap.votos_nulos),
            "diferenca_lider": self._num(ap.diferenca_lider),
            "diferenca_lider_num": str(ap.diferenca_lider),
            "diferenca_pct": self._pct(ap.diferenca_pct),
            "diferenca_pct_num": f"{ap.diferenca_pct:.2f}",
            # Composicao do voto ja em percentual: a conta nao volta para o GC.
            "pct_validos": self._pct(ap.pct_validos),
            "pct_validos_num": f"{ap.pct_validos:.2f}",
            "pct_brancos": self._pct(ap.pct_brancos),
            "pct_brancos_num": f"{ap.pct_brancos:.2f}",
            "pct_nulos": self._pct(ap.pct_nulos),
            "pct_nulos_num": f"{ap.pct_nulos:.2f}",
            "pct_brancos_nulos": self._pct(ap.pct_brancos_nulos),
            "pct_brancos_nulos_num": f"{ap.pct_brancos_nulos:.2f}",
            "pct_comparecimento": self._pct(ap.pct_comparecimento),
            "pct_comparecimento_num": f"{ap.pct_comparecimento:.2f}",
            "pct_abstencao": self._pct(ap.pct_abstencao),
            "pct_abstencao_num": f"{ap.pct_abstencao:.2f}",
            # Ritmo: quanto falta, e se a diferenca ainda cabe no que falta.
            "secoes_restantes": self._num(ap.secoes_restantes),
            "secoes_restantes_num": str(ap.secoes_restantes),
            "votos_restantes": self._num(ap.votos_restantes),
            "votos_restantes_num": str(ap.votos_restantes),
            "reversivel": "1" if ap.reversivel else "0",
            "gerado_em": ap.gerado_em.strftime("%d/%m/%Y %H:%M:%S") if ap.gerado_em else "",
            "hora_geracao": ap.gerado_em.strftime("%H:%M") if ap.gerado_em else "",
            "atualizado_em": (ap.capturado_em or datetime.now()).strftime("%d/%m/%Y %H:%M:%S"),
            "hora_atualizacao": (ap.capturado_em or datetime.now()).strftime("%H:%M"),
            "qtd_candidatos": str(len(ap.candidatos)),
            **self._composicao(ap),
        }

    # --- geometria do grafico de composicao (brancos, nulos, abstencao) ---

    FATIAS_APURADOS = ("validos", "brancos", "nulos")
    FATIAS_ELEITORADO = ("validos", "brancos", "nulos", "abstencao")

    def _composicao(self, ap: Apuracao) -> dict[str, str]:
        """Barra empilhada e rosca JA CALCULADAS para validos/brancos/nulos.

        Mesma ideia de '_barra': o GC recebe pixel e grau prontos, nao faz
        conta. Aqui isso importa ainda mais, porque a rosca exige aritmetica
        de circunferencia que nenhum gerador de caracteres faz bem.

        'base' escolhe contra o que as fatias sao medidas:
          apurados     validos + brancos + nulos (fecha 100% do que foi votado)
          eleitorado   inclui a abstencao (fecha 100% de quem podia votar)

        As duas bases nao se misturam: quem nao foi votar nao esta dentro dos
        votos apurados, e somar as duas coisas num grafico so produz um total
        que nao fecha.

        A largura de cada fatia sai de uma soma ACUMULADA arredondada, nao de
        cada pedaco arredondado por conta propria: assim a barra fecha exato
        no trilho e nao sobra 1px de fundo aparecendo entre duas fatias.
        """
        cfg = self.opcoes.get("composicao") or self.cfg_texto.get("composicao") or {}
        trilho = int(cfg.get("trilho_px", 0))
        raio = float(cfg.get("rosca_raio", 0))
        if not trilho and not raio:
            return {}

        base = str(cfg.get("base", "apurados")).lower()
        if base == "eleitorado":
            fatias = self.FATIAS_ELEITORADO
            total = ap.eleitorado_apto
            valores = {
                "validos": ap.votos_validos,
                "brancos": ap.votos_brancos,
                "nulos": ap.votos_nulos,
                "abstencao": ap.abstencao,
            }
        else:
            fatias = self.FATIAS_APURADOS
            total = ap.votos_apurados
            valores = {
                "validos": ap.votos_validos,
                "brancos": ap.votos_brancos,
                "nulos": ap.votos_nulos,
            }

        campos: dict[str, str] = {"comp_base": base, "comp_total": self._num(total)}
        fracoes = {f: (valores[f] / total if total > 0 else 0.0) for f in fatias}

        if trilho:
            campos["comp_trilho_px"] = str(trilho)
            acumulado = 0.0
            borda = 0
            for fatia in fatias:
                acumulado += fracoes[fatia]
                fim = round(trilho * acumulado)
                campos[f"comp_{fatia}_px"] = str(fim - borda)
                campos[f"comp_{fatia}_x"] = str(borda)
                campos[f"comp_{fatia}_pct"] = f"{fracoes[fatia] * 100:.2f}"
                borda = fim

        if raio:
            circunferencia = 2 * math.pi * raio
            campos["rosca_raio"] = f"{raio:g}"
            campos["rosca_circunferencia"] = f"{circunferencia:.2f}"
            acumulado = 0.0
            for fatia in fatias:
                arco = circunferencia * fracoes[fatia]
                campos[f"rosca_{fatia}_arco"] = f"{arco:.2f}"
                # stroke-dasharray pronto: "arco resto". Um <circle> por fatia,
                # todos com o mesmo raio, cada um com seu dash e seu offset.
                campos[f"rosca_{fatia}_dash"] = f"{arco:.2f} {circunferencia - arco:.2f}"
                campos[f"rosca_{fatia}_offset"] = f"{-circunferencia * acumulado:.2f}"
                # e o mesmo em graus, para o CG que so sabe girar um objeto
                campos[f"rosca_{fatia}_graus"] = f"{fracoes[fatia] * 360:.2f}"
                campos[f"rosca_{fatia}_giro"] = f"{acumulado * 360:.2f}"
                acumulado += fracoes[fatia]

        return campos

    def campos_candidato(self, cand: Candidato, ap: Apuracao | None = None) -> dict[str, str]:
        geometria = self._barra(cand, ap)
        return {
            "posicao": str(cand.posicao),
            "numero": cand.numero,
            "nome": self._txt(cand.nome, "nome"),
            "nome_completo": self._txt(cand.nome_completo, "nome_completo"),
            "partido": self._txt(cand.partido, "partido"),
            "coligacao": self._txt(cand.coligacao, "coligacao"),
            "vice": self._txt(cand.vice, "nome"),
            "votos": self._num(cand.votos),
            "votos_num": str(cand.votos),
            "percentual": self._pct(cand.percentual),
            "percentual_num": f"{cand.percentual:.2f}",
            "eleito": "1" if cand.eleito else "0",
            "situacao": self._txt(cand.situacao, "situacao"),
            "sequencial": cand.sequencial,
            "foto": self._foto(cand),
            "cor": self._cor(cand),
            **geometria,
        }

    def _barra(self, cand: Candidato, ap: Apuracao | None) -> dict[str, str]:
        """Geometria da barra JA CALCULADA, para o GC nao precisar fazer conta.

        O caminho curto para um grafico que acompanha o percentual e nao pedir
        aritmetica ao gerador de caracteres. Ele recebe a largura em pixels do
        projeto, ou uma escala 0-1, ou um indice de quadro - e so aplica.

        'base' decide contra o que o percentual e normalizado:
          validos  a propria fatia de votos validos do candidato (majoritario)
          lider    o 1o colocado vira 100% (proporcional, onde ninguem passa
                   de 5% e uma barra sobre o total ficaria invisivel no ar)

        'minimo_px' garante que um candidato com voto quase zero ainda deixe um
        traco visivel, em vez de sumir e parecer campo vazio.
        """
        cfg = self.opcoes.get("barra") or self.cfg_texto.get("barra") or {}
        trilho = int(cfg.get("trilho_px", 0))
        if not trilho:
            return {}

        base = str(cfg.get("base", "validos")).lower()
        referencia = 100.0
        if base == "lider" and ap and ap.candidatos:
            referencia = max((c.percentual for c in ap.candidatos), default=0.0)
        if referencia <= 0:
            referencia = 100.0

        fracao = max(0.0, min(1.0, cand.percentual / referencia))
        minimo = int(cfg.get("minimo_px", 0))
        largura = round(trilho * fracao)
        if cand.percentual > 0:
            largura = max(largura, minimo)
        passos = int(cfg.get("passos", 100))

        return {
            "barra_pct": f"{fracao * 100:.2f}",
            "barra_px": str(largura),
            # o que sobra do trilho: e o unico numero necessario quando a cena
            # usa um retangulo da cor do fundo cobrindo a barra cheia, truque
            # que funciona em CG que so sabe mover objeto, sem redimensionar
            "barra_resto_px": str(trilho - largura),
            "barra_esc": f"{fracao:.4f}",
            "barra_idx": str(round(fracao * passos)),
            "barra_trilho_px": str(trilho),
        }

    def _foto(self, cand: Candidato) -> str:
        """Caminho da foto do candidato, montado a partir do numero da urna.

        A arte nomeia os arquivos pelo numero (10.png, 22.png...), que e o
        identificador estavel: nome muda de grafia, numero nao. Vazio quando
        'texto.padrao_foto' nao esta configurado ou o candidato nao tem numero.
        """
        padrao = str(self.cfg_texto.get("padrao_foto", ""))
        if not padrao or not cand.numero:
            return ""
        return padrao.format(numero=cand.numero, sequencial=cand.sequencial, partido=cand.partido)

    def _cor(self, cand: Candidato) -> str:
        """Cor da barra/tarja do candidato, por partido.

        Mantem a mesma cor para o mesmo partido em todas as pracas e cargos,
        que e o que o telespectador usa para se orientar entre um bloco e outro.
        """
        cores = self.cfg_texto.get("cores_partido") or {}
        chave = (cand.partido or "").strip().upper()
        return str(cores.get(chave, self.cfg_texto.get("cor_padrao", "")))

    def candidatos(self, ap: Apuracao) -> list[Candidato]:
        return ap.candidatos[: self.limite] if self.limite > 0 else ap.candidatos

    def linhas(self, ap: Apuracao) -> list[dict[str, str]]:
        return [self.campos_candidato(c, ap) for c in self.candidatos(ap)]

    def achatado(self, ap: Apuracao) -> dict[str, str]:
        """Formato 'largo': resumo + cand1_nome, cand1_votos, cand2_... .

        E o formato que templates de take unico (CasparCG, Viz Trio, XPression
        em modo single-row) esperam: um registro com todos os campos.
        """
        plano = dict(self.campos_resumo(ap))
        for indice, cand in enumerate(self.candidatos(ap), start=1):
            for chave, valor in self.campos_candidato(cand, ap).items():
                plano[f"cand{indice}_{chave}"] = valor
        return plano

    # --- nome do arquivo ---

    def caminho_saida(self, ap: Apuracao, nome_alvo: str, extensao: str, sufixo: str = "") -> Path:
        agora = datetime.now()
        base = self.padrao_nome.format(
            alvo=slug(nome_alvo),
            abr=slug(ap.abrangencia_codigo),
            abr_nome=slug(ap.abrangencia_nome),
            cargo=ap.cargo_codigo,
            cargo_nome=slug(ap.cargo_nome),
            turno=ap.turno,
            data=agora.strftime("%Y%m%d"),
            hora=agora.strftime("%H%M%S"),
            ts=agora.strftime("%Y%m%d-%H%M%S"),
        )
        return self.destino / f"{base}{sufixo}{extensao}"

    @abstractmethod
    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        """Grava a apuracao. Retorna os caminhos escritos (vazio para push)."""
