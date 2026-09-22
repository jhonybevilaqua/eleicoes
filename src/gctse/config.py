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

MODOS = ("simulado", "producao")

# O modo decide as duas coisas que nao podem depender de alguem lembrar:
#
#   SIMULADO   aceita boletim em fase 'S' - que e o que o TSE publica nos dias
#              de teste - e carimba o selo em TODA tarja, inclusive nas que
#              vierem em fase 'O'. O selo nao desliga.
#   PRODUCAO   so aceita fase 'O'. Nenhum valor de config derruba essa trava.
#
# Nao ter escolhido vale 'producao': o esquecimento cai no lado seguro.
MODO_PADRAO = "producao"


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

    # --- modo de operacao ---

    @property
    def modo(self) -> str:
        """'simulado' nos dias de teste do TSE, 'producao' no dia da eleicao.

        Vale a variavel de ambiente GCTSE_MODO antes da config, para o atalho
        do Windows escolher sem ninguem editar arquivo - e sem deixar estado
        para trocar de volta depois.
        """
        pedido = self._modo_pedido()
        return pedido if pedido in MODOS else MODO_PADRAO

    def _modo_pedido(self) -> str:
        """O que foi pedido, valido ou nao - a validacao precisa ver o erro."""
        for origem in (os.environ.get("GCTSE_MODO"), self.bruto.get("modo")):
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

    # --- secoes ---
    @property
    def tse(self) -> dict[str, Any]:
        """Codigos do TSE, com o modo atual por cima.

        O simulado do TSE sai em pleito proprio. Guardar os dois preenchidos
        faz a virada de quinta para domingo ser troca de atalho, em vez de
        edicao de configuracao sob pressao.
        """
        return {**(self.bruto.get("tse", {}) or {}), **self._do_modo("tse")}

    @property
    def coleta(self) -> dict[str, Any]:
        return self.bruto.get("coleta", {})

    @property
    def saida(self) -> dict[str, Any]:
        return self.bruto.get("saida", {})

    @property
    def texto(self) -> dict[str, Any]:
        """Aparencia do texto, com o selo do modo por cima.

        Em simulado o selo e carimbado SEMPRE, inclusive em boletim que venha
        marcado como oficial. Sem isso, um dia de teste em que o TSE publique
        fase 'O' sairia com a tarja limpa - cara de resultado, no meio de um
        ensaio.
        """
        texto = {**(self.bruto.get("texto", {}) or {}), **self._do_modo("texto")}
        if self.simulado:
            texto["selo_nao_oficial"] = self.selo_do_modo
            texto["selo_sempre"] = True
        return texto

    @property
    def selo_do_modo(self) -> str:
        """Selo que o modo impoe, acima do que o 'texto' pedir."""
        if not self.simulado:
            return ""
        modos = self.bruto.get("modos") or {}
        simulado = (modos.get("simulado") or {}) if isinstance(modos, dict) else {}
        return str(
            self._do_modo("texto").get("selo")
            or simulado.get("selo")
            or "SIMULADO - TESTE, NAO E RESULTADO"
        )

    @property
    def seguranca(self) -> dict[str, Any]:
        """As travas, com a regra que a config nao pode contrariar.

        Em PRODUCAO 'bloquear_nao_oficial' e sempre verdadeiro: nao existe
        valor em arquivo que faca um simulado do TSE ir ao ar como resultado.
        Em SIMULADO e sempre falso, senao os dias de teste nao mostrariam nada
        - e la quem cobre o risco e o selo, que tambem nao desliga.
        """
        base = {**(self.bruto.get("seguranca", {}) or {}), **self._do_modo("seguranca")}
        base["bloquear_nao_oficial"] = not self.simulado
        return base

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
    def rodizios(self) -> dict[str, dict[str, Any]]:
        """Grupos de pracas que saem num arquivo so, para a tarja rodar.

        rodizios:
          governadores:
            exporter: liveboard_rodizio
            alvos: [gov-pr, gov-sp, gov-rj]   # a ordem aqui e a ordem do ar
        """
        return self.bruto.get("rodizios", {}) or {}

    @property
    def mapas(self) -> dict[str, dict[str, Any]]:
        """Grupos de UFs que viram um mapa.

        Mesma forma do rodizio - um exporter e uma lista de alvos - porque o
        problema e o mesmo: varias pracas num arquivo so. O nome separado
        existe para a config dizer o que a pessoa quis, e nao 'rodizio' para
        uma coisa que e mapa.

        mapas:
          mapa-presidente:
            exporter: mapa_br
            alvos: [pres-ac, pres-al, ...]
        """
        return self.bruto.get("mapas", {}) or {}

    @property
    def grupos(self) -> dict[str, dict[str, Any]]:
        """Rodizios e mapas juntos: tudo que o pipeline publica em lote."""
        return {**self.rodizios, **self.mapas}

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
                    # lista vazia EXPLICITA e uma escolha valida: o alvo e
                    # coletado so para alimentar um rodizio, sem arquivo proprio.
                    # 'or' trataria [] como ausente e devolveria todos.
                    exporters=list(
                        dados["exporters"] if "exporters" in dados else self.exporters.keys()
                    ),
                    apelido_abrangencia=str(dados.get("apelido_abrangencia", "")),
                )
            )
        return alvos

    def validar(self) -> list[str]:
        """Tudo que impede rodar: erros e pendencias juntos."""
        erros, pendencias = self.conferir()
        return erros + pendencias

    def conferir(self) -> tuple[list[str], list[str]]:
        """Separa o que esta ERRADO do que so esta POR PREENCHER.

        O pacote sai de fabrica com o codigo do pleito em '000', porque o TSE
        so publica esse codigo perto do dia. Nao e defeito - e a proxima coisa
        a fazer. Tratar como erro faria a conferencia do pacote reprovar a si
        mesma no build.

        Erro impede rodar em qualquer situacao. Pendencia impede rodar contra
        o TSE de verdade, mas nao impede ensaiar nem conferir o pacote.
        """
        problemas: list[str] = []
        pendencias: list[str] = []
        tse = self.tse
        contra_o_tse = str(self.coleta.get("fonte", "tse")).lower() == "tse"
        for campo in ("base_url", "ciclo", "pleito", "eleicao"):
            valor = str(tse.get(campo) or "").strip()
            if not valor:
                problemas.append(f"tse.{campo} nao definido (modo {self.modo})")
            elif contra_o_tse and campo in ("pleito", "eleicao") and set(valor) <= {"0"}:
                # '000' e o marcador de 'ainda nao preenchi'. Subir assim monta
                # uma URL que sempre devolve 404, e a operacao passa a noite
                # em 'aguardando boletim' sem ninguem entender por que.
                pendencias.append(
                    f"tse.{campo} ainda esta em '{valor}' no modo {self.modo}: "
                    f"rode 'gctse descobrir' e preencha em modos.{self.modo}.tse"
                )

        pedido = self._modo_pedido()
        if pedido not in MODOS:
            origem = (
                f"GCTSE_MODO={os.environ['GCTSE_MODO']}"
                if str(os.environ.get("GCTSE_MODO") or "").strip().lower() == pedido
                else f"modo: {self.bruto.get('modo')}"
            )
            problemas.append(
                f"{origem} nao e um modo conhecido (use {' ou '.join(MODOS)}); "
                f"valendo '{self.modo}'"
            )

        if not self.bruto.get("alvos"):
            problemas.append("nenhum alvo configurado em 'alvos'")
        if not self.exporters:
            problemas.append("nenhum exporter configurado em 'exporters'")

        conhecidos = set(self.exporters.keys())
        nomes_alvo = {a.nome for a in self.alvos}
        for rotulo, colecao in (("rodizio", self.rodizios), ("mapa", self.mapas)):
            for nome, grupo in colecao.items():
                if not grupo.get("alvos"):
                    problemas.append(f"{rotulo} '{nome}' sem lista de alvos")
                if grupo.get("exporter") not in conhecidos:
                    problemas.append(
                        f"{rotulo} '{nome}' referencia exporter inexistente '{grupo.get('exporter')}'"
                    )
                for alvo in grupo.get("alvos") or []:
                    if alvo not in nomes_alvo:
                        problemas.append(f"{rotulo} '{nome}' cita alvo inexistente '{alvo}'")
        for alvo in self.alvos:
            for nome in alvo.exporters:
                if nome not in conhecidos:
                    problemas.append(f"alvo '{alvo.nome}' referencia exporter inexistente '{nome}'")
            if alvo.cargo not in range(1, 14):
                problemas.append(f"alvo '{alvo.nome}' com cargo fora da tabela do TSE: {alvo.cargo}")
        if self.intervalo < 5:
            problemas.append("coleta.intervalo_segundos abaixo de 5s: risco de bloqueio pelo TSE")
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
