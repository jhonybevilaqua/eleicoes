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

MODOS = ("simulado", "producao")

# O que cada modo faz, alem de trocar os codigos do TSE. As duas diferencas
# que importam:
#
#   SIMULADO   aceita boletim em fase 'S' - que e o que o TSE publica nos dias
#              de teste - e carimba um selo que NAO pode ser desligado.
#   PRODUCAO   so aceita fase 'O', e recusa subir com codigo de pleito por
#              preencher. E o padrao quando a config nao diz nada: esquecer de
#              escolher tem de cair no lado seguro.
MODO_PADRAO = "producao"

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

    # --- modo de operacao -------------------------------------------------

    @property
    def modo(self) -> str:
        """'simulado' nos dias de teste do TSE, 'producao' no dia da eleicao.

        Vale a variavel de ambiente TELAO_MODO antes da config, para o atalho
        do Windows poder escolher sem editar arquivo nenhum.
        """
        pedido = self._modo_pedido()
        return pedido if pedido in MODOS else MODO_PADRAO

    def _modo_pedido(self) -> str:
        """O que foi pedido, valido ou nao - a validacao precisa ver o erro."""
        for origem in (os.environ.get("TELAO_MODO"), self.bruto.get("modo")):
            # 'modo:' em branco no YAML vira None, nao string vazia
            texto = str(origem).strip().lower() if origem is not None else ""
            if texto:
                return texto
        return MODO_PADRAO

    @property
    def simulado(self) -> bool:
        return self.modo == "simulado"

    def _do_modo(self, secao: str) -> dict[str, Any]:
        """Bloco 'secao' de dentro do modo atual, se existir."""
        modos = self.bruto.get("modos") or {}
        return ((modos.get(self.modo) or {}).get(secao) or {}) if isinstance(modos, dict) else {}

    @property
    def tse(self) -> dict[str, Any]:
        """Codigos do TSE, com o modo atual por cima.

        O simulado do TSE costuma sair em caminho e codigo de pleito proprios.
        Se ficassem no mesmo lugar dos oficiais, trocar de teste para o dia da
        eleicao exigiria reescrever a config sob pressao - e reescrever a config
        no dia e exatamente o que este desenho existe para evitar.
        """
        return {**(self.bruto.get("tse", {}) or {}), **self._do_modo("tse")}

    @property
    def coleta(self) -> dict[str, Any]:
        return self.bruto.get("coleta", {}) or {}

    @property
    def seguranca(self) -> dict[str, Any]:
        """As travas, com uma regra que a config nao pode contrariar.

        Em PRODUCAO, 'bloquear_nao_oficial' e sempre verdadeiro: nao ha valor
        de config, nem de modo, que faca um simulado do TSE ir ao ar como
        resultado. Em SIMULADO ele e sempre falso, senao os dias de teste nao
        mostrariam nada - e la o selo cobre o risco.
        """
        base = {**(self.bruto.get("seguranca", {}) or {}), **self._do_modo("seguranca")}
        base["bloquear_nao_oficial"] = not self.simulado
        return base

    @property
    def selo_do_modo(self) -> str:
        """Selo que o modo impoe, acima do que a aparencia pedir."""
        if not self.simulado:
            return ""
        modos = self.bruto.get("modos") or {}
        simulado = (modos.get("simulado") or {}) if isinstance(modos, dict) else {}
        return str(
            self._do_modo("aparencia").get("selo")
            or simulado.get("selo")
            or "SIMULADO — TESTE, NÃO É RESULTADO"
        )

    @property
    def aparencia(self) -> dict[str, Any]:
        aparencia = {**(self.bruto.get("aparencia", {}) or {}), **self._do_modo("aparencia")}
        if self.simulado:
            # o selo de simulado nao e negociavel: sobrescreve o da aparencia
            aparencia["selo_nao_oficial"] = self.selo_do_modo
        return aparencia

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
        """Tudo que impede o telao de funcionar: erros e pendencias juntos."""
        erros, pendencias = self.conferir()
        return erros + pendencias

    def conferir(self) -> tuple[list[str], list[str]]:
        """Separa o que esta ERRADO do que so esta POR PREENCHER.

        A distincao existe por causa de uma situacao real: o pacote sai de
        fabrica com o codigo do pleito em '000', porque o TSE so publica esse
        codigo perto do dia. Isso nao e um defeito do pacote - e a proxima
        coisa que a pessoa tem de fazer. Tratar como erro faria a conferencia
        do pacote reprovar a si mesma.

        Erro impede rodar em qualquer situacao. Pendencia impede rodar contra
        o TSE de verdade, mas nao impede ensaiar nem conferir o pacote.
        """
        problemas: list[str] = []
        pendencias: list[str] = []
        if str(self.coleta.get("fonte", "tse")).lower() == "tse":
            for campo in ("base_url", "ciclo", "pleito", "eleicao"):
                valor = str(self.tse.get(campo) or "").strip()
                if not valor:
                    problemas.append(f"tse.{campo} nao definido (modo {self.modo})")
                elif campo in ("pleito", "eleicao") and set(valor) <= {"0"}:
                    # '000' e o marcador de 'ainda nao preenchi'. Subir assim
                    # monta uma URL que sempre devolve 404, e o telao passa a
                    # noite inteira 'aguardando boletim' sem ninguem entender.
                    pendencias.append(
                        f"tse.{campo} ainda esta em '{valor}' no modo {self.modo}: "
                        f"rode 'telao descobrir' e preencha em modos.{self.modo}.tse"
                    )
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

        pedido = self._modo_pedido()
        if pedido not in MODOS:
            origem = (
                f"TELAO_MODO={os.environ['TELAO_MODO']}"
                if str(os.environ.get("TELAO_MODO") or "").strip().lower() == pedido
                else f"modo: {self.bruto.get('modo')}"
            )
            problemas.append(
                f"{origem} nao e um modo conhecido (use {' ou '.join(MODOS)}); "
                f"valendo '{self.modo}'"
            )

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
        return problemas, pendencias


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
