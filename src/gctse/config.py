"""Leitura e validacao da configuracao (YAML ou JSON)."""

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

_VAR_ENV = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")


class ErroConfig(Exception):
    """Configuracao ausente, malformada ou incoerente."""


def _expandir_env(valor: Any) -> Any:
    """Substitui ${VAR} e ${VAR:-padrao} para nao versionar segredos."""
    if isinstance(valor, str):
        def troca(m: re.Match) -> str:
            return os.environ.get(m.group(1), m.group(2) or "")
        return _VAR_ENV.sub(troca, valor)
    if isinstance(valor, dict):
        return {k: _expandir_env(v) for k, v in valor.items()}
    if isinstance(valor, list):
        return [_expandir_env(v) for v in valor]
    return valor


@dataclass
class Alvo:
    """Um par abrangencia x cargo que sera consultado e exportado."""

    nome: str
    abrangencia: str          # "br", "pr", "pr75353" (UF+cod. TSE do municipio)
    cargo: int
    turno: int = 1
    intervalo: int | None = None
    limite_candidatos: int = 0
    exporters: list[str] = field(default_factory=list)
    apelido_abrangencia: str = ""


@dataclass
class Config:
    bruto: dict[str, Any]
    caminho: Path

    # --- secoes ---
    @property
    def tse(self) -> dict[str, Any]:
        return self.bruto.get("tse", {})

    @property
    def coleta(self) -> dict[str, Any]:
        return self.bruto.get("coleta", {})

    @property
    def saida(self) -> dict[str, Any]:
        return self.bruto.get("saida", {})

    @property
    def texto(self) -> dict[str, Any]:
        return self.bruto.get("texto", {})

    @property
    def seguranca(self) -> dict[str, Any]:
        return self.bruto.get("seguranca", {})

    @property
    def alertas(self) -> dict[str, Any]:
        return self.bruto.get("alertas", {})

    @property
    def mapeamento(self) -> dict[str, Any]:
        return self.bruto.get("mapeamento", {})

    @property
    def exporters(self) -> dict[str, dict[str, Any]]:
        return self.bruto.get("exporters", {})

    @property
    def intervalo(self) -> int:
        return int(self.coleta.get("intervalo_segundos", 20))

    @property
    def alvos(self) -> list[Alvo]:
        alvos: list[Alvo] = []
        padroes = self.bruto.get("padroes_alvo", {}) or {}
        for item in self.bruto.get("alvos", []) or []:
            dados = {**padroes, **item}
            abrangencia = str(dados.get("abrangencia", "")).strip().lower()
            cargo = int(dados.get("cargo", 0))
            if not abrangencia or not cargo:
                raise ErroConfig(f"alvo invalido (abrangencia/cargo obrigatorios): {item!r}")
            alvos.append(
                Alvo(
                    nome=str(dados.get("nome") or f"{abrangencia}-c{cargo}"),
                    abrangencia=abrangencia,
                    cargo=cargo,
                    turno=int(dados.get("turno", self.tse.get("turno", 1))),
                    intervalo=int(dados["intervalo"]) if dados.get("intervalo") else None,
                    limite_candidatos=int(dados.get("limite_candidatos", 0)),
                    exporters=list(dados.get("exporters") or list(self.exporters.keys())),
                    apelido_abrangencia=str(dados.get("apelido_abrangencia", "")),
                )
            )
        return alvos

    def validar(self) -> list[str]:
        """Retorna a lista de problemas encontrados (vazia = config ok)."""
        problemas: list[str] = []
        tse = self.tse
        for campo in ("base_url", "ciclo", "pleito", "eleicao"):
            if not tse.get(campo):
                problemas.append(f"tse.{campo} nao definido")
        if not self.bruto.get("alvos"):
            problemas.append("nenhum alvo configurado em 'alvos'")
        if not self.exporters:
            problemas.append("nenhum exporter configurado em 'exporters'")

        conhecidos = set(self.exporters.keys())
        for alvo in self.alvos:
            for nome in alvo.exporters:
                if nome not in conhecidos:
                    problemas.append(f"alvo '{alvo.nome}' referencia exporter inexistente '{nome}'")
            if alvo.cargo not in range(1, 14):
                problemas.append(f"alvo '{alvo.nome}' com cargo fora da tabela do TSE: {alvo.cargo}")
        if self.intervalo < 5:
            problemas.append("coleta.intervalo_segundos abaixo de 5s: risco de bloqueio pelo TSE")
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
