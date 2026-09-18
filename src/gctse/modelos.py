"""Modelo normalizado da apuracao.

Tudo que vem do TSE e convertido para estas estruturas antes de chegar aos
exporters. Assim, se o TSE mudar nomes de campo em 2026, so o parser muda -
os exporters e os templates do GC continuam iguais.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

CARGOS = {
    1: "Presidente",
    2: "Vice-Presidente",
    3: "Governador",
    4: "Vice-Governador",
    5: "Senador",
    6: "Deputado Federal",
    7: "Deputado Estadual",
    8: "Deputado Distrital",
    9: "1o Suplente",
    10: "2o Suplente",
    11: "Prefeito",
    12: "Vice-Prefeito",
    13: "Vereador",
}

FASES = {
    "O": "Oficial",
    "S": "Simulado",
    "T": "Teste",
}


@dataclass
class Candidato:
    """Uma linha do placar."""

    posicao: int = 0
    numero: str = ""
    nome: str = ""
    nome_completo: str = ""
    partido: str = ""
    coligacao: str = ""
    votos: int = 0
    percentual: float = 0.0
    eleito: bool = False
    situacao: str = ""
    sequencial: str = ""
    vice: str = ""
    extras: dict[str, Any] = field(default_factory=dict)

    def como_dict(self) -> dict[str, Any]:
        return {
            "posicao": self.posicao,
            "numero": self.numero,
            "nome": self.nome,
            "nome_completo": self.nome_completo,
            "partido": self.partido,
            "coligacao": self.coligacao,
            "votos": self.votos,
            "percentual": self.percentual,
            "eleito": self.eleito,
            "situacao": self.situacao,
            "sequencial": self.sequencial,
            "vice": self.vice,
        }


@dataclass
class Apuracao:
    """Boletim de um cargo em uma abrangencia, num instante."""

    eleicao: str = ""
    pleito: str = ""
    turno: int = 1
    cargo_codigo: int = 0
    cargo_nome: str = ""
    abrangencia_tipo: str = ""   # BR | UF | MU
    abrangencia_codigo: str = ""
    abrangencia_nome: str = ""
    fase: str = ""               # O | S | T
    gerado_em: datetime | None = None   # data/hora de geracao no TSE
    capturado_em: datetime | None = None
    secoes_totalizadas: int = 0
    secoes_total: int = 0
    pct_secoes: float = 0.0
    eleitorado_apto: int = 0
    comparecimento: int = 0
    abstencao: int = 0
    votos_validos: int = 0
    votos_nominais: int = 0
    votos_brancos: int = 0
    votos_nulos: int = 0
    total_apurado: int = 0
    candidatos: list[Candidato] = field(default_factory=list)
    fonte_url: str = ""
    bruto: dict[str, Any] = field(default_factory=dict)

    # --- propriedades usadas pelos templates de GC ---

    @property
    def oficial(self) -> bool:
        return self.fase.upper() == "O"

    @property
    def fase_nome(self) -> str:
        return FASES.get(self.fase.upper(), self.fase or "Indefinida")

    @property
    def totalizada(self) -> bool:
        return self.pct_secoes >= 100.0

    @property
    def lider(self) -> Candidato | None:
        return self.candidatos[0] if self.candidatos else None

    @property
    def diferenca_lider(self) -> int:
        """Votos de vantagem do 1o sobre o 2o - usado em placar de virada."""
        if len(self.candidatos) < 2:
            return 0
        return self.candidatos[0].votos - self.candidatos[1].votos

    @property
    def diferenca_pct(self) -> float:
        """Vantagem do 1o sobre o 2o em pontos percentuais."""
        if len(self.candidatos) < 2:
            return 0.0
        return round(self.candidatos[0].percentual - self.candidatos[1].percentual, 2)

    # --- composicao do voto: validos, brancos, nulos, abstencao ---
    #
    # O TSE manda os absolutos; o percentual de cada fatia nao vem pronto. Como
    # o grafico de brancos e nulos e sempre percentual, a conta fica aqui: um
    # lugar so, testado, em vez de espalhada por cada template de GC.

    @property
    def votos_apurados(self) -> int:
        """Base do grafico de composicao: validos + brancos + nulos.

        Prefere 'total_apurado' quando o TSE o publica; quando nao, soma as
        tres fatias, que e a mesma conta pela definicao do boletim.
        """
        soma = self.votos_validos + self.votos_brancos + self.votos_nulos
        return self.total_apurado or soma

    def _fatia(self, valor: int, base: int) -> float:
        return round(100.0 * valor / base, 2) if base > 0 else 0.0

    @property
    def pct_validos(self) -> float:
        return self._fatia(self.votos_validos, self.votos_apurados)

    @property
    def pct_brancos(self) -> float:
        return self._fatia(self.votos_brancos, self.votos_apurados)

    @property
    def pct_nulos(self) -> float:
        return self._fatia(self.votos_nulos, self.votos_apurados)

    @property
    def pct_brancos_nulos(self) -> float:
        """Brancos e nulos somados - a leitura que costuma virar materia."""
        return self._fatia(self.votos_brancos + self.votos_nulos, self.votos_apurados)

    @property
    def pct_comparecimento(self) -> float:
        return self._fatia(self.comparecimento, self.eleitorado_apto)

    @property
    def pct_abstencao(self) -> float:
        """Percentual sobre o eleitorado apto, nao sobre os votos apurados.

        Quem nao foi votar nao esta dentro dos votos apurados; misturar as duas
        bases num grafico so produz uma soma que nao fecha 100%.
        """
        return self._fatia(self.abstencao, self.eleitorado_apto)

    # --- ritmo da apuracao ---

    @property
    def secoes_restantes(self) -> int:
        return max(0, self.secoes_total - self.secoes_totalizadas)

    @property
    def votos_restantes(self) -> int:
        """Estimativa de votos que ainda faltam apurar.

        Regra de tres sobre o que ja foi apurado: se X votos sairam de Y% das
        secoes, os (100-Y)% restantes trazem aproximadamente a mesma proporcao.
        E estimativa - secao grande e secao pequena nao valem igual - e serve
        para responder no ar se a diferenca entre 1o e 2o ainda e reversivel,
        nao para projetar resultado.
        """
        if self.pct_secoes <= 0 or self.pct_secoes >= 100:
            return 0
        return int(self.votos_apurados * (100.0 / self.pct_secoes - 1))

    @property
    def reversivel(self) -> bool:
        """A diferenca entre 1o e 2o cabe no que ainda falta apurar?"""
        return self.diferenca_lider < self.votos_restantes

    @property
    def chave(self) -> str:
        """Identificador estavel do alvo (abrangencia + cargo + turno)."""
        return f"{self.abrangencia_tipo}:{self.abrangencia_codigo}:c{self.cargo_codigo}:t{self.turno}"

    def impressao(self) -> str:
        """Hash do conteudo relevante: se nao mudou, nao reescreve arquivo."""
        corpo = {
            "gerado_em": self.gerado_em.isoformat() if self.gerado_em else "",
            "fase": self.fase,
            "pct": self.pct_secoes,
            "secoes": self.secoes_totalizadas,
            "validos": self.votos_validos,
            "brancos": self.votos_brancos,
            "nulos": self.votos_nulos,
            "cands": [(c.numero, c.votos, c.percentual, c.eleito) for c in self.candidatos],
        }
        bruto = json.dumps(corpo, ensure_ascii=False, sort_keys=True, default=str)
        return hashlib.sha1(bruto.encode("utf-8")).hexdigest()

    def como_dict(self) -> dict[str, Any]:
        return {
            "eleicao": self.eleicao,
            "pleito": self.pleito,
            "turno": self.turno,
            "cargo_codigo": self.cargo_codigo,
            "cargo_nome": self.cargo_nome,
            "abrangencia_tipo": self.abrangencia_tipo,
            "abrangencia_codigo": self.abrangencia_codigo,
            "abrangencia_nome": self.abrangencia_nome,
            "fase": self.fase,
            "fase_nome": self.fase_nome,
            "oficial": self.oficial,
            "totalizada": self.totalizada,
            "gerado_em": self.gerado_em.isoformat() if self.gerado_em else "",
            "capturado_em": self.capturado_em.isoformat() if self.capturado_em else "",
            "secoes_totalizadas": self.secoes_totalizadas,
            "secoes_total": self.secoes_total,
            "pct_secoes": self.pct_secoes,
            "eleitorado_apto": self.eleitorado_apto,
            "comparecimento": self.comparecimento,
            "abstencao": self.abstencao,
            "votos_validos": self.votos_validos,
            "votos_nominais": self.votos_nominais,
            "votos_brancos": self.votos_brancos,
            "votos_nulos": self.votos_nulos,
            "total_apurado": self.total_apurado,
            "diferenca_lider": self.diferenca_lider,
            "diferenca_pct": self.diferenca_pct,
            "votos_apurados": self.votos_apurados,
            "pct_validos": self.pct_validos,
            "pct_brancos": self.pct_brancos,
            "pct_nulos": self.pct_nulos,
            "pct_brancos_nulos": self.pct_brancos_nulos,
            "pct_comparecimento": self.pct_comparecimento,
            "pct_abstencao": self.pct_abstencao,
            "secoes_restantes": self.secoes_restantes,
            "votos_restantes": self.votos_restantes,
            "reversivel": self.reversivel,
            "fonte_url": self.fonte_url,
            "candidatos": [c.como_dict() for c in self.candidatos],
        }
