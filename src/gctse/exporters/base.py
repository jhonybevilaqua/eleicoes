"""Base comum dos exporters: contexto de campos, nomes de arquivo e guardas."""

from __future__ import annotations

import logging
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
        self.cfg_texto = cfg_texto or {}
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
            "selo": "" if ap.oficial else str(self.cfg_texto.get("selo_nao_oficial", "SIMULADO")),
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
            "diferenca_lider": self._num(ap.diferenca_lider),
            "gerado_em": ap.gerado_em.strftime("%d/%m/%Y %H:%M:%S") if ap.gerado_em else "",
            "hora_geracao": ap.gerado_em.strftime("%H:%M") if ap.gerado_em else "",
            "atualizado_em": (ap.capturado_em or datetime.now()).strftime("%d/%m/%Y %H:%M:%S"),
            "hora_atualizacao": (ap.capturado_em or datetime.now()).strftime("%H:%M"),
            "qtd_candidatos": str(len(ap.candidatos)),
        }

    def campos_candidato(self, cand: Candidato) -> dict[str, str]:
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
        return [self.campos_candidato(c) for c in self.candidatos(ap)]

    def achatado(self, ap: Apuracao) -> dict[str, str]:
        """Formato 'largo': resumo + cand1_nome, cand1_votos, cand2_... .

        E o formato que templates de take unico (CasparCG, Viz Trio, XPression
        em modo single-row) esperam: um registro com todos os campos.
        """
        plano = dict(self.campos_resumo(ap))
        for indice, cand in enumerate(self.candidatos(ap), start=1):
            for chave, valor in self.campos_candidato(cand).items():
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
