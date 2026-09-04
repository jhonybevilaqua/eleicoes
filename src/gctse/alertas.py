"""Alertas operacionais para quem esta de plantao.

Dispara aviso quando a coleta para de evoluir, quando um alvo falha
repetidamente ou quando o processo cai. O destino padrao e um webhook - serve
tanto para um fluxo do Power Automate quanto para um Incoming Webhook de canal
do Teams (payload {"text": ...}), que e o caminho mais curto para chegar no
celular do coordenador durante a transmissao.

Ha supressao por repeticao: o mesmo alerta nao e reenviado antes de
'intervalo_repeticao_segundos', para nao inundar o canal em um incidente longo.
"""

from __future__ import annotations

import json
import logging
import time

import requests

log = logging.getLogger("gctse.alertas")


class Alertas:
    def __init__(self, cfg: dict | None = None):
        cfg = cfg or {}
        self.ativo = bool(cfg.get("ativo", False))
        self.url = str(cfg.get("webhook_url", "")).strip()
        self.prefixo = str(cfg.get("prefixo", "[GC-TSE]"))
        self.timeout = float(cfg.get("timeout", 5))
        self.repeticao = int(cfg.get("intervalo_repeticao_segundos", 600))
        self.campo = str(cfg.get("campo_texto", "text"))
        self._ultimos: dict[str, float] = {}

    def enviar(self, chave: str, mensagem: str, nivel: str = "AVISO") -> None:
        texto = f"{self.prefixo} {nivel}: {mensagem}"
        if nivel == "ERRO":
            log.error(texto)
        else:
            log.warning(texto)

        if not self.ativo or not self.url:
            return
        agora = time.time()
        if agora - self._ultimos.get(chave, 0.0) < self.repeticao:
            return
        self._ultimos[chave] = agora
        try:
            requests.post(
                self.url,
                data=json.dumps({self.campo: texto}, ensure_ascii=False).encode("utf-8"),
                headers={"Content-Type": "application/json; charset=utf-8"},
                timeout=self.timeout,
            )
        except requests.RequestException as exc:
            log.error("falha ao enviar alerta para o webhook: %s", exc)

    def resolver(self, chave: str) -> None:
        """Limpa a supressao para que uma nova ocorrencia avise de novo."""
        self._ultimos.pop(chave, None)
