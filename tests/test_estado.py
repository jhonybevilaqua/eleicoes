from datetime import datetime

from gctse.estado import Estado


def test_dedupe_e_persistencia(tmp_path):
    caminho = tmp_path / "estado.json"
    estado = Estado(caminho)
    assert estado.mudou("alvo", "abc") is True

    estado.registrar("alvo", "abc", datetime(2026, 10, 4, 20, 0, 0))
    assert estado.mudou("alvo", "abc") is False
    assert estado.mudou("alvo", "def") is True

    estado.salvar()
    recarregado = Estado(caminho)
    assert recarregado.mudou("alvo", "abc") is False


def test_bloqueio_de_regressao_temporal(tmp_path):
    estado = Estado(tmp_path / "estado.json")
    estado.registrar("alvo", "abc", datetime(2026, 10, 4, 20, 10, 0))
    assert estado.regrediu("alvo", datetime(2026, 10, 4, 20, 5, 0)) is True
    assert estado.regrediu("alvo", datetime(2026, 10, 4, 20, 15, 0)) is False
    assert estado.regrediu("alvo", None) is False


def test_estado_corrompido_nao_derruba(tmp_path):
    caminho = tmp_path / "estado.json"
    caminho.write_text("{isso nao e json", encoding="utf-8")
    estado = Estado(caminho)
    assert estado.dados == {}
