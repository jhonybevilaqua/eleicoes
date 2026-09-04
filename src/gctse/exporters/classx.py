"""ClassX LiveBoard - CSV de grade fixa para vinculo por celula.

O LiveBoard le uma planilha e cada objeto da cena e amarrado a uma celula
(B7, C12...). Isso so e confiavel se a GEOMETRIA do arquivo nunca mudar: a
mesma quantidade de linhas, as mesmas colunas, na mesma ordem, do primeiro ao
ultimo boletim do dia. Um CSV que tem 4 linhas as 17h e 6 linhas as 20h faz
todo o resto deslizar e o LiveBoard passa a ler o campo errado, sem avisar.

Este exporter garante a geometria:

* numero de linhas de candidato SEMPRE igual a 'slots' - se o TSE devolver
  menos candidatos, as linhas restantes saem vazias (e o campo 'visivel' vai
  a "0", para a cena esconder o objeto); se devolver mais, o excedente e
  cortado;
* a ordem dos campos vem de uma lista fixa em codigo/config, nunca da ordem
  em que o TSE mandou;
* o cabecalho ocupa sempre a mesma linha.

Dois modos de ordenacao, que respondem a perguntas diferentes:

  ordem: colocacao  A linha 1 e sempre o 1o colocado. A celula nao se move,
                    mas na virada o NOME dentro dela troca.
                    Use em placar de apuracao.

  ordem: fixa       A linha 1 e sempre o candidato de numero X (definido em
                    'candidatos_fixos'). A pessoa naquela celula nunca muda,
                    aconteca o que acontecer no placar.
                    Use quando a cena tem foto/cor fixa por posicao.

O comando 'gctse celulas' imprime o mapa - qual celula guarda qual campo -
para o operador amarrar a cena sem adivinhar.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path

from ..modelos import Apuracao
from ..util.arquivos import escrever_texto
from .base import Exporter

# Ordem fixa dos campos. Mudar esta lista MOVE as celulas: se alterar depois
# de a cena estar amarrada, rode 'gctse celulas' e refaca os vinculos.
CAMPOS_RESUMO_PADRAO = [
    "cargo",
    "abrangencia",
    "turno",
    "apuracao_pct",
    "secoes_totalizadas",
    "secoes_total",
    "votos_validos",
    "votos_brancos",
    "votos_nulos",
    "comparecimento",
    "abstencao",
    "selo",
    "hora_atualizacao",
]

CAMPOS_CANDIDATO_PADRAO = [
    "visivel",
    "numero",
    "nome",
    "partido",
    "nome_partido",
    "percentual",
    "votos",
    "eleito",
]


def letra_coluna(indice: int) -> str:
    """0 -> A, 1 -> B, 26 -> AA (notacao de planilha)."""
    letras = ""
    indice += 1
    while indice > 0:
        indice, resto = divmod(indice - 1, 26)
        letras = chr(65 + resto) + letras
    return letras


class ExporterClassX(Exporter):
    tipo = "classx"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.layout = str(self.opcoes.get("layout", "chave_valor")).lower()
        self.ordem = str(self.opcoes.get("ordem", "colocacao")).lower()
        self.slots = int(self.opcoes.get("slots", 6))
        self.colunas_resumo = list(self.opcoes.get("campos_resumo") or CAMPOS_RESUMO_PADRAO)
        self.colunas_candidato = list(self.opcoes.get("campos_candidato") or CAMPOS_CANDIDATO_PADRAO)
        self.formato_nome_partido = str(self.opcoes.get("formato_nome_partido", "{nome} ({partido})"))
        self.candidatos_fixos = [str(n).strip() for n in (self.opcoes.get("candidatos_fixos") or [])]
        self.vazio = str(self.opcoes.get("preencher_vazio", ""))
        self.cabecalho = bool(self.opcoes.get("cabecalho", True))
        delimitador = str(self.opcoes.get("delimitador", ";"))
        self.delimitador = "\t" if delimitador.lower() in ("tab", "\\t") else delimitador
        self.extensao = str(self.opcoes.get("extensao", ".csv"))

        if self.ordem == "fixa" and self.candidatos_fixos:
            # em ordem fixa a quantidade de linhas e a propria lista
            self.slots = len(self.candidatos_fixos)

    # --- montagem das linhas de candidato ---

    def _linha_vazia(self) -> dict[str, str]:
        linha = {campo: self.vazio for campo in self.colunas_candidato}
        if "visivel" in linha:
            linha["visivel"] = "0"
        return linha

    def _linha_candidato(self, cand_campos: dict[str, str]) -> dict[str, str]:
        nome = cand_campos.get("nome", "")
        partido = cand_campos.get("partido", "")
        completo = dict(cand_campos)
        completo["visivel"] = "1"
        completo["nome_partido"] = (
            self.formato_nome_partido.format(nome=nome, partido=partido) if partido else nome
        )
        return {campo: completo.get(campo, self.vazio) for campo in self.colunas_candidato}

    def slots_preenchidos(self, ap: Apuracao) -> list[dict[str, str]]:
        """Sempre 'slots' linhas, na ordem escolhida. Geometria garantida."""
        campos = [self.campos_candidato(c) for c in ap.candidatos]

        if self.ordem == "fixa" and self.candidatos_fixos:
            por_numero = {c["numero"]: c for c in campos}
            return [
                self._linha_candidato(por_numero[numero]) if numero in por_numero else self._linha_vazia()
                for numero in self.candidatos_fixos
            ]

        linhas = [self._linha_candidato(c) for c in campos[: self.slots]]
        while len(linhas) < self.slots:
            linhas.append(self._linha_vazia())
        return linhas

    # --- escrita ---

    def exportar(self, ap: Apuracao, nome_alvo: str) -> list[Path]:
        resumo = self._resumo_filtrado(ap)
        linhas = self.slots_preenchidos(ap)

        if self.layout == "grade":
            return self._escrever_grade(ap, nome_alvo, resumo, linhas)
        if self.layout == "largo":
            return self._escrever_largo(ap, nome_alvo, resumo, linhas)
        return self._escrever_chave_valor(ap, nome_alvo, resumo, linhas)

    def _resumo_filtrado(self, ap: Apuracao) -> dict[str, str]:
        todos = self.campos_resumo(ap)
        return {campo: todos.get(campo, self.vazio) for campo in self.colunas_resumo}

    def _render(self, linhas: list[list[str]]) -> str:
        buffer = io.StringIO()
        escritor = csv.writer(buffer, delimiter=self.delimitador, lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
        escritor.writerows(linhas)
        return buffer.getvalue()

    def _gravar(self, ap: Apuracao, nome_alvo: str, sufixo: str, linhas: list[list[str]]) -> Path:
        destino = self.caminho_saida(ap, nome_alvo, self.extensao, sufixo)
        return escrever_texto(destino, self._render(linhas), encoding=self.encoding, nova_linha=self.nova_linha)

    def _escrever_chave_valor(self, ap, nome_alvo, resumo, linhas) -> list[Path]:
        """Duas colunas: A = nome do campo, B = valor. A linha de cada campo
        e sempre a mesma, entao o vinculo e sempre B<n>."""
        saida: list[list[str]] = []
        if self.cabecalho:
            saida.append(["campo", "valor"])
        for campo in self.colunas_resumo:
            saida.append([campo, resumo.get(campo, self.vazio)])
        for indice, linha in enumerate(linhas, start=1):
            for campo in self.colunas_candidato:
                saida.append([f"cand{indice}_{campo}", linha.get(campo, self.vazio)])
        return [self._gravar(ap, nome_alvo, "", saida)]

    def _escrever_grade(self, ap, nome_alvo, resumo, linhas) -> list[Path]:
        """Tabela: linha 1 cabecalho, linhas 2..N+1 os slots. Resumo em arquivo
        separado, tambem de geometria fixa."""
        grade: list[list[str]] = []
        if self.cabecalho:
            grade.append(list(self.colunas_candidato))
        for linha in linhas:
            grade.append([linha.get(campo, self.vazio) for campo in self.colunas_candidato])

        arquivos = [self._gravar(ap, nome_alvo, "", grade)]

        bloco_resumo: list[list[str]] = []
        if self.cabecalho:
            bloco_resumo.append(list(self.colunas_resumo))
        bloco_resumo.append([resumo.get(campo, self.vazio) for campo in self.colunas_resumo])
        arquivos.append(self._gravar(ap, nome_alvo, "-resumo", bloco_resumo))
        return arquivos

    def _escrever_largo(self, ap, nome_alvo, resumo, linhas) -> list[Path]:
        """Uma unica linha de valores: linha 1 cabecalho, linha 2 os dados."""
        cabecalhos = list(self.colunas_resumo)
        valores = [resumo.get(campo, self.vazio) for campo in self.colunas_resumo]
        for indice, linha in enumerate(linhas, start=1):
            for campo in self.colunas_candidato:
                cabecalhos.append(f"cand{indice}_{campo}")
                valores.append(linha.get(campo, self.vazio))
        saida = [cabecalhos, valores] if self.cabecalho else [valores]
        return [self._gravar(ap, nome_alvo, "", saida)]

    # --- mapa de celulas (nao depende de dado) ---

    def mapa_celulas(self) -> list[dict[str, str]]:
        """Diz qual celula guarda qual campo, para amarrar a cena no LiveBoard."""
        mapa: list[dict[str, str]] = []
        deslocamento = 1 if self.cabecalho else 0

        if self.layout == "chave_valor":
            linha = deslocamento + 1
            for campo in self.colunas_resumo:
                mapa.append({"arquivo": "principal", "celula": f"B{linha}", "campo": campo, "origem": "resumo"})
                linha += 1
            for indice in range(1, self.slots + 1):
                origem = self._descricao_slot(indice)
                for campo in self.colunas_candidato:
                    mapa.append(
                        {"arquivo": "principal", "celula": f"B{linha}", "campo": f"cand{indice}_{campo}", "origem": origem}
                    )
                    linha += 1
            return mapa

        if self.layout == "grade":
            for indice in range(1, self.slots + 1):
                origem = self._descricao_slot(indice)
                for coluna, campo in enumerate(self.colunas_candidato):
                    celula = f"{letra_coluna(coluna)}{indice + deslocamento}"
                    mapa.append({"arquivo": "principal", "celula": celula, "campo": campo, "origem": origem})
            for coluna, campo in enumerate(self.colunas_resumo):
                mapa.append(
                    {"arquivo": "-resumo", "celula": f"{letra_coluna(coluna)}{1 + deslocamento}", "campo": campo, "origem": "resumo"}
                )
            return mapa

        # largo
        linha = 1 + deslocamento
        coluna = 0
        for campo in self.colunas_resumo:
            mapa.append({"arquivo": "principal", "celula": f"{letra_coluna(coluna)}{linha}", "campo": campo, "origem": "resumo"})
            coluna += 1
        for indice in range(1, self.slots + 1):
            origem = self._descricao_slot(indice)
            for campo in self.colunas_candidato:
                mapa.append(
                    {"arquivo": "principal", "celula": f"{letra_coluna(coluna)}{linha}", "campo": f"cand{indice}_{campo}", "origem": origem}
                )
                coluna += 1
        return mapa

    def _descricao_slot(self, indice: int) -> str:
        if self.ordem == "fixa" and self.candidatos_fixos:
            numero = self.candidatos_fixos[indice - 1]
            return f"sempre o candidato numero {numero}"
        return f"{indice}o colocado no momento"
