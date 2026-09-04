"""Cliente HTTP do TSE: retentativa, timeout e cache condicional.

Pontos que importam em dia de eleicao:

* ETag / If-Modified-Since: o TSE republica o mesmo arquivo a cada ciclo de
  totalizacao. Com cache condicional, a maioria das consultas volta 304 e nao
  gasta banda nem CPU - e nos permite pesquisar em intervalo curto sem abusar
  da origem.
* Retentativa com backoff: falha de rede no ar nao pode derrubar o processo.
  Quem chama recebe None e mantem o ultimo boletim valido no GC.
* Timeout curto e obrigatorio: uma conexao pendurada trava o ciclo inteiro.
"""

from __future__ import annotations

import logging
import random
import time
from dataclasses import dataclass
from typing import Any

import requests

from .. import __version__

log = logging.getLogger("gctse.tse")


@dataclass
class Resposta:
    url: str
    dados: dict[str, Any] | None   # None = sem novidade (304) ou falha
    status: int = 0
    inalterado: bool = False
    erro: str = ""

    @property
    def ok(self) -> bool:
        return self.dados is not None


class ClienteTSE:
    def __init__(
        self,
        *,
        timeout: float = 8.0,
        tentativas: int = 3,
        backoff: float = 1.5,
        usar_cache: bool = True,
        user_agent: str | None = None,
        verificar_tls: bool = True,
        proxies: dict[str, str] | None = None,
    ):
        self.timeout = timeout
        self.tentativas = max(1, tentativas)
        self.backoff = backoff
        self.usar_cache = usar_cache
        self._cache: dict[str, dict[str, str]] = {}
        self.sessao = requests.Session()
        self.sessao.headers.update(
            {
                "User-Agent": user_agent or f"gctse/{__version__} (automacao GC emissora)",
                "Accept": "application/json, text/plain, */*",
                "Accept-Encoding": "gzip, deflate",
            }
        )
        self.sessao.verify = verificar_tls
        if proxies:
            self.sessao.proxies.update(proxies)

    def fechar(self) -> None:
        self.sessao.close()

    def buscar_json(self, url: str) -> Resposta:
        cabecalhos: dict[str, str] = {}
        if self.usar_cache and url in self._cache:
            cabecalhos.update(self._cache[url])

        ultimo_erro = ""
        for tentativa in range(1, self.tentativas + 1):
            try:
                resp = self.sessao.get(url, headers=cabecalhos, timeout=self.timeout)
            except requests.RequestException as exc:
                ultimo_erro = f"{type(exc).__name__}: {exc}"
                log.warning("falha de rede (%d/%d) em %s: %s", tentativa, self.tentativas, url, ultimo_erro)
            else:
                if resp.status_code == 304:
                    return Resposta(url=url, dados=None, status=304, inalterado=True)
                if resp.status_code == 404:
                    # arquivo ainda nao publicado para este cargo/abrangencia
                    return Resposta(url=url, dados=None, status=404, erro="nao publicado")
                if resp.status_code >= 500 or resp.status_code == 429:
                    ultimo_erro = f"HTTP {resp.status_code}"
                    log.warning("resposta %s (%d/%d) em %s", resp.status_code, tentativa, self.tentativas, url)
                elif not resp.ok:
                    return Resposta(url=url, dados=None, status=resp.status_code, erro=f"HTTP {resp.status_code}")
                else:
                    try:
                        dados = resp.json()
                    except ValueError as exc:
                        return Resposta(url=url, dados=None, status=resp.status_code, erro=f"JSON invalido: {exc}")
                    if self.usar_cache:
                        novo: dict[str, str] = {}
                        if resp.headers.get("ETag"):
                            novo["If-None-Match"] = resp.headers["ETag"]
                        if resp.headers.get("Last-Modified"):
                            novo["If-Modified-Since"] = resp.headers["Last-Modified"]
                        if novo:
                            self._cache[url] = novo
                    return Resposta(url=url, dados=dados, status=resp.status_code)

            if tentativa < self.tentativas:
                # jitter evita que varios alvos re-tentem no mesmo instante
                espera = (self.backoff ** tentativa) + random.uniform(0, 0.4)
                time.sleep(espera)

        return Resposta(url=url, dados=None, erro=ultimo_erro or "falha desconhecida")
