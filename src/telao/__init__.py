"""Telao - sistema de exibicao de apuracao em tela cheia.

Um programa proprio, separado do gctse. O gctse abastece o gerador de
caracteres com as tarjas; o telao desenha telas inteiras de 1920x1080 e as
entrega prontas para um PC de exibicao, cuja saida de video entra no switcher
como uma fonte qualquer.

Os dois nao se falam. Executavel proprio, configuracao propria, pasta propria,
coleta propria. Dar problema num nao derruba o outro, e a operacao do GC no dia
- que estara ocupada com as tarjas - nao divide atencao com o telao.

O que os dois compartilham e a BIBLIOTECA de leitura do TSE: o cliente HTTP com
cache condicional, o parser das abreviacoes do boletim, as travas de fase e de
regressao e a malha do Brasil. Reescrever isso aqui seria manter duas copias das
travas que impedem um simulado de ir ao ar - e, no dia em que o TSE mudar uma
abreviacao, corrigir uma e esquecer a outra.
"""

__version__ = "1.0.0"
