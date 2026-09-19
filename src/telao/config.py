"""Configuracao do telao: um arquivo proprio, curto de proposito.

O gctse precisa de uma config longa porque cada alvo vira arquivo para uma cena
diferente do GC. O telao nao: ele sempre quer a mesma coisa - o resultado
nacional e o dos 27 estados para um cargo. Entao aqui voce diz o cargo, e as
28 praças saem sozinhas.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover - YAML e opcional se usar JSON
    yaml = None

from gctse.malha_br import UFS

_VAR_ENV = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")

CARGOS_VALIDOS = {1: "Presidente", 3: "Governador", 5: "Senador"}

# As telas que o sistema sabe desenhar.
TIPOS = ("lideranca", "estados", "como-votou", "apuracao-nacional", "apuracao-estados", "placar")

# Se a configuracao nao listar telas, estas entram. E a ordem em que aparecem
# na mesa e nas teclas 1..6 da tela de exibicao.
TELAS_PADRAO: list[dict[str, Any]] = [
    {"id": "lideranca", "tipo": "lideranca", "titulo": "LIDERANÇA POR ESTADO"},
    {"id": "estados", "tipo": "estados", "titulo": "COMO CADA ESTADO VOTOU"},
    {"id": "como-votou", "tipo": "como-votou", "titulo": "COMO O BRASIL VOTOU"},
    {"id": "apuracao-nacional", "tipo": "apuracao-nacional", "titulo": "APURAÇÃO NACIONAL"},
    {"id": "apuracao-estados", "tipo": "apuracao-estados", "titulo": "APURAÇÃO POR ESTADO"},
    {"id": "placar", "tipo": "placar", "titulo": "PRESIDENTE — BRASIL"},
]


class ErroConfig(Exception):
    """Configuracao ausente, malformada ou incoerente."""


def _expandir_env(valor: Any) -> Any:
    if isinstance(valor, str):
        return _VAR_ENV.sub(lambda m: os.environ.get(m.group(1), m.group(2) or ""), valor)
    if isinstance(valor, dict):
        return {k: _expandir_env(v) for k, v in valor.items()}
    if isinstance(valor, list):
        return [_expandir_env(v) for v in valor]
    return valor


@dataclass
class Tela:
    id: str
    tipo: str
    titulo: str = ""
    opcoes: dict[str, Any] = field(default_factory=dict)


@dataclass
class Config:
    bruto: dict[str, Any]
    caminho: Path

    @property
    def tse(self) -> dict[str, Any]:
        return self.bruto.get("tse", {}) or {}

    @property
    def coleta(self) -> dict[str, Any]:
        return self.bruto.get("coleta", {}) or {}

    @property
    def seguranca(self) -> dict[str, Any]:
        return self.bruto.get("seguranca", {}) or {}

    @property
    def aparencia(self) -> dict[str, Any]:
        return self.bruto.get("aparencia", {}) or {}

    @property
    def vertical(self) -> dict[str, Any]:
        """Monitor vertical de cena (1080x1920), que roda sozinho.

        Secao separada das 'telas' porque e outro problema: o telao do
        switcher tem alguem escolhendo, o monitor de cena nao tem ninguem.
        """
        return self.bruto.get("vertical", {}) or {}

    @property
    def apuracao(self) -> dict[str, Any]:
        return self.bruto.get("apuracao", {}) or {}

    @property
    def destino(self) -> Path:
        return Path(self.bruto.get("saida", {}).get("destino", "telao"))

    @property
    def cargo(self) -> int:
        return int(self.apuracao.get("cargo", 1))

    @property
    def turno(self) -> int:
        return int(self.apuracao.get("turno", self.tse.get("turno", 1)))

    @property
    def intervalo(self) -> int:
        return int(self.coleta.get("intervalo_segundos", 20))

    @property
    def intervalo_tela(self) -> int:
        return int(self.bruto.get("saida", {}).get("intervalo_tela_segundos", 8))

    @property
    def estados(self) -> list[str]:
        """Siglas que o telao vai coletar. 'todos' (padrao) traz as 27.

        Listar um punhado de estados serve para emissora regional: o mapa
        continua inteiro, com as pracas de fora em cinza, e a coleta cai de 28
        requisicoes por ciclo para o que voce realmente exibe.
        """
        pedido = self.apuracao.get("estados", "todos")
        if isinstance(pedido, str):
            if pedido.strip().lower() in ("todos", "todas", "*"):
                return list(UFS)
            pedido = [pedido]
        siglas = [str(s).strip().upper() for s in (pedido or []) if str(s).strip()]
        return [s for s in siglas if s in UFS]

    @property
    def telas(self) -> list[Tela]:
        # Lista vazia EXPLICITA e uma escolha valida: quem so quer o monitor
        # de cena escreve 'telas: []' e nao gera nada para o switcher. 'or'
        # trataria [] como ausente e devolveria as seis padrao - que foi
        # exatamente o que aconteceu na primeira tentativa de rodar so o
        # vertical.
        pedidas = self.bruto.get("telas")
        if pedidas is None:
            pedidas = TELAS_PADRAO

        telas: list[Tela] = []
        vistos: set[str] = set()
        for item in pedidas:
            if not isinstance(item, dict):
                continue
            tipo = str(item.get("tipo", "")).strip().lower()
            identificador = str(item.get("id") or "").strip() or tipo
            if tipo not in TIPOS or identificador in vistos:
                continue
            vistos.add(identificador)
            telas.append(
                Tela(
                    id=identificador,
                    tipo=tipo,
                    titulo=str(item.get("titulo", "")),
                    opcoes={k: v for k, v in item.items() if k not in ("id", "tipo", "titulo")},
                )
            )
        return telas

    def validar(self) -> list[str]:
        problemas: list[str] = []
        if str(self.coleta.get("fonte", "tse")).lower() == "tse":
            for campo in ("base_url", "ciclo", "pleito", "eleicao"):
                if not self.tse.get(campo):
                    problemas.append(f"tse.{campo} nao definido")
        if self.cargo not in CARGOS_VALIDOS:
            problemas.append(
                f"apuracao.cargo {self.cargo} nao vale para o telao "
                f"(use {', '.join(f'{c} {n}' for c, n in CARGOS_VALIDOS.items())})"
            )
        if not self.estados:
            problemas.append("apuracao.estados nao resolveu nenhuma UF valida")
        if not self.telas and not self.vertical.get("ativo"):
            problemas.append(
                "nenhuma tela reconhecida em 'telas' e o monitor vertical esta desligado: "
                "o telao nao produziria nada"
            )
        for item in self.bruto.get("telas") or []:
            if isinstance(item, dict) and str(item.get("tipo", "")).lower() not in TIPOS:
                problemas.append(
                    f"tela '{item.get('id') or item.get('tipo')}' com tipo desconhecido "
                    f"'{item.get('tipo')}' (validos: {', '.join(TIPOS)})"
                )
        if self.intervalo < 5:
            problemas.append("coleta.intervalo_segundos abaixo de 5s: risco de bloqueio pelo TSE")

        if self.vertical.get("ativo"):
            from .vertical import TIPOS as TIPOS_V

            pedidas = self.vertical.get("telas") or []
            if isinstance(pedidas, str):
                pedidas = [pedidas]
            for item in pedidas:
                if str(item).strip().lower() not in TIPOS_V:
                    problemas.append(
                        f"vertical: tela '{item}' desconhecida (validas: {', '.join(TIPOS_V)})"
                    )
            if int(self.vertical.get("rodizio_segundos", 10)) < 3:
                problemas.append("vertical.rodizio_segundos abaixo de 3s: ilegivel em cena")
        return problemas


def carregar(caminho: str | Path) -> Config:
    caminho = Path(caminho)
    if not caminho.exists():
        raise ErroConfig(f"arquivo de configuracao nao encontrado: {caminho}")
    texto = caminho.read_text(encoding="utf-8")
    if caminho.suffix.lower() in (".yaml", ".yml"):
        if yaml is None:
            raise ErroConfig("PyYAML nao instalado: use config em .json ou 'pip install PyYAML'")
        dados = yaml.safe_load(texto) or {}
    else:
        dados = json.loads(texto)
    if not isinstance(dados, dict):
        raise ErroConfig("a configuracao deve ser um mapeamento no nivel raiz")
    return Config(bruto=_expandir_env(dados), caminho=caminho)


def caminho_padrao() -> str:
    """telao.yaml na pasta do programa; config/telao.yaml como alternativa."""
    for candidato in ("telao.yaml", "config/telao.yaml"):
        if Path(candidato).exists():
            return candidato
    return "telao.yaml"
