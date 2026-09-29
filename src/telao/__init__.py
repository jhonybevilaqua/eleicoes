"""Telao - telas de apuracao do TSE.

Le os boletins da Divulgacao de Resultados do TSE e desenha telas inteiras,
prontas para entrar no switcher como fonte de video:

  1920x1080  seis telas para o switcher, escolhidas numa mesa
  1080x1920  seis telas para o monitor vertical de cena, girando sozinhas

O sistema nao produz mais nada: nao alimenta gerador de caracteres, nao
escreve arquivo para outro programa ler. Um executavel, uma configuracao, uma
pasta - e o que sai dela sao desenhos.

O caminho do dado, de ponta a ponta:

  TSE -> cliente HTTP (cache condicional, espacamento por 404)
      -> parser das abreviacoes do boletim
      -> travas de fase e de regressao
      -> desenho (SVG)
      -> pasta compartilhada -> PC de exibicao

Antes do primeiro boletim as telas saem inteiras com os campos vazios. Nada
e inventado em lugar nenhum: o que aparece na tela veio do TSE.
"""

__version__ = "2.0.0"
