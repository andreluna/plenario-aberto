"""Despesas da cota parlamentar a partir dos arquivos anuais oficiais (CSV zipado).

O endpoint /deputados/{id}/despesas da API retorna sempre lista vazia (verificado em 30/10/2026),
então usamos https://www.camara.leg.br/cotas/Ano-AAAA.csv.zip, com cache em disco.
"""
import csv
import io
import threading
import time
from datetime import date
import zipfile
from collections import defaultdict
from pathlib import Path

import requests

URL = "https://www.camara.leg.br/cotas/Ano-{ano}.csv.zip"
CACHE = Path(__file__).resolve().parent.parent / "cache"
MAX_IDADE = 24 * 3600  # rebaixa o arquivo do ano corrente após 24h

_lock = threading.Lock()
_por_ano = {}  # ano -> (momento_do_parse, {id: [linhas]})


def _expirado(ano, t):
    """Anos passados não mudam; o ano corrente é renovado a cada 24h."""
    return ano >= date.today().year and time.time() - t > MAX_IDADE


def _arquivo(ano):
    CACHE.mkdir(exist_ok=True)
    p = CACHE / f"Ano-{ano}.csv.zip"
    if not p.exists() or _expirado(ano, p.stat().st_mtime):
        r = requests.get(URL.format(ano=ano), timeout=180)
        r.raise_for_status()
        p.write_bytes(r.content)
    return p


def _carregar(ano):
    with _lock:  # um download/parse por vez; as demais threads reaproveitam o resultado
        return _carregar_sem_lock(ano)


def _carregar_sem_lock(ano):
    t, idx = _por_ano.get(ano, (0, None))
    if idx is not None and not _expirado(ano, t):
        return idx
    with zipfile.ZipFile(_arquivo(ano)) as z:
        f = io.TextIOWrapper(z.open(z.namelist()[0]), encoding="utf-8-sig")
        idx = defaultdict(list)
        for r in csv.DictReader(f, delimiter=";"):
            if r["ideCadastro"]:
                idx[int(r["ideCadastro"])].append({
                    "data": r["datEmissao"][:10], "tipo": r["txtDescricao"],
                    "fornecedor": r["txtFornecedor"], "cnpj": r["txtCNPJCPF"],
                    "valor": float(r["vlrLiquido"] or 0), "mes": int(r["numMes"]),
                    "url": r["urlDocumento"]})
    _por_ano[ano] = (time.time(), idx)
    return idx


def _indice(ano):
    """Índice do ano, ou {} se o arquivo não existe (404). Outras falhas de rede propagam."""
    try:
        return _carregar(ano)
    except requests.HTTPError as e:
        if e.response is not None and e.response.status_code == 404:
            return {}
        raise


def despesas(dep_id, ano):
    """Despesas do deputado no ano, mais recentes primeiro."""
    return sorted(_indice(ano).get(dep_id, []), key=lambda x: x["data"], reverse=True)


def totais_por_deputado(ano):
    """{id_deputado: total líquido no ano}."""
    return {i: sum(x["valor"] for x in l) for i, l in _indice(ano).items()}


def por_mes(linhas):
    """Lista de 12 totais mensais."""
    m = [0.0] * 12
    for x in linhas:
        if 1 <= x["mes"] <= 12:
            m[x["mes"] - 1] += x["valor"]
    return m


def resumo(linhas):
    """(total, [(tipo, total)] ordenado desc)."""
    por_tipo = defaultdict(float)
    for x in linhas:
        por_tipo[x["tipo"]] += x["valor"]
    return sum(por_tipo.values()), sorted(por_tipo.items(), key=lambda t: -t[1])
