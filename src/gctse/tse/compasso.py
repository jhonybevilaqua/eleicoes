"""Espacamento das tentativas em arquivo que o TSE ainda nao publicou.

O TSE avisa, na documentacao do ambiente oficial:

    Multiplos erros 404 podem provocar o bloqueio temporario do endereco IP
    pelo servidor, como medida de seguranca.

E 404 nao e excecao aqui: e o estado NORMAL durante horas. Antes de as urnas
fecharem nenhum arquivo existe, e no comeco da noite muitas pracas ainda nao
publicaram. Com 28 pracas a cada 20 segundos, um sistema que insiste de forma
ingenua faz mais de cinco mil 404 por hora - e passa de "esperando o boletim"
para "bloqueado justo quando o dado ia comecar a sair".

Entao cada arquivo que responde 404 tem a sua propria espera, que cresce e
para de crescer num teto. A primeira resposta boa zera tudo: assim que a praca
publica, ela volta ao ritmo normal no ciclo seguinte.

A espera e por ARQUIVO, nao global: o Acre nao ter publicado nao pode atrasar
a leitura de Sao Paulo.
"""

from __future__ import annotations

import time


class Compasso:
    """Quando vale a pena tentar de novo cada arquivo."""

    def __init__(
        self,
        *,
        tolerancia: int = 2,
        base_segundos: float = 30.0,
        teto_segundos: float = 300.0,
    ):
        # 'tolerancia' 404 seguidos passam batido: o intervalo normal de
        # coleta ja e curto, e a praca pode publicar no ciclo seguinte.
        self.tolerancia = max(0, tolerancia)
        self.base = max(1.0, base_segundos)
        self.teto = max(self.base, teto_segundos)
        self._seguidos: dict[str, int] = {}
        self._proxima: dict[str, float] = {}

    @staticmethod
    def _agora(agora: float | None) -> float:
        # 'agora or time.monotonic()' estaria errado: o instante 0.0 e falso
        # em Python, e o relogio do teste comeca justamente em zero.
        return time.monotonic() if agora is None else agora

    def pode_tentar(self, chave: str, agora: float | None = None) -> bool:
        limite = self._proxima.get(chave)
        return limite is None or self._agora(agora) >= limite

    def registrar_404(self, chave: str, agora: float | None = None) -> float:
        """Conta o 404 e devolve quantos segundos este arquivo vai esperar."""
        seguidos = self._seguidos.get(chave, 0) + 1
        self._seguidos[chave] = seguidos
        if seguidos <= self.tolerancia:
            self._proxima.pop(chave, None)
            return 0.0
        # dobra a cada 404 alem da tolerancia, ate o teto
        espera = min(self.teto, self.base * (2 ** (seguidos - self.tolerancia - 1)))
        self._proxima[chave] = self._agora(agora) + espera
        return espera

    def registrar_ok(self, chave: str) -> None:
        """Publicou: volta ao ritmo normal ja no proximo ciclo."""
        self._seguidos.pop(chave, None)
        self._proxima.pop(chave, None)

    def espera_de(self, chave: str) -> int:
        """Quantos 404 seguidos este arquivo acumulou."""
        return self._seguidos.get(chave, 0)
