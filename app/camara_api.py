"""Cliente mínimo da API de Dados Abertos da Câmara dos Deputados."""
import re
import threading
import time
import unicodedata

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

BASE = "https://dadosabertos.camara.leg.br/api/v2"
_session = requests.Session()
_session.headers["Accept"] = "application/json"
_session.mount("https://", HTTPAdapter(max_retries=Retry(total=3, backoff_factor=0.5, status_forcelist=(429, 500, 502, 503, 504))))


def get(path, **params):
    """GET em BASE+path. Retorna (dados, links). Levanta requests.HTTPError em erro."""
    params = {k: v for k, v in params.items() if v not in (None, "")}
    r = _session.get(f"{BASE}{path}", params=params, timeout=20)
    r.raise_for_status()
    body = r.json()
    return body.get("dados"), {l["rel"]: l["href"] for l in body.get("links", [])}


_cache = {}
_lock = threading.Lock()


def _cached(chave, fn, ttl=600):
    with _lock:
        t, v = _cache.get(chave, (0, None))
        if time.time() - t > ttl:
            v = fn()
            _cache[chave] = (time.time(), v)
        return v


def _norm(t):
    return unicodedata.normalize("NFD", t).encode("ascii", "ignore").decode().lower()


def _padrao(texto):
    """Texto com % como curinga (estilo SQL LIKE). Sem %, busca por 'contém'."""
    partes = [re.escape(p) for p in _norm(texto.strip()).split("%")]
    return re.compile(".*".join(partes) if "%" in texto else partes[0])


def _todos_deputados():
    out, pag = [], 1
    while True:
        lista, links = get("/deputados", pagina=pag, itens=100, ordem="ASC", ordenarPor="nome")
        out += lista
        if "next" not in links:
            return out
        pag += 1


def buscar_deputados(nome=None, partidos=None, ufs=None):
    """Deputados em exercício. nome aceita % como curinga e ignora acentos/caixa;
    partidos e ufs aceitam siglas separadas por vírgula."""
    lista = _cached("deputados", _todos_deputados)
    siglas = {p.strip().upper() for p in (partidos or "").split(",") if p.strip()}
    estados = {u.strip().upper() for u in (ufs or "").split(",") if u.strip()}
    if siglas:
        lista = [d for d in lista if d["siglaPartido"].upper() in siglas]
    if estados:
        lista = [d for d in lista if d["siglaUf"].upper() in estados]
    if nome and nome.strip("% "):
        pad = _padrao(nome)
        lista = [d for d in lista if pad.search(_norm(d["nome"]))]
    return lista


def agrupar_por_partido(deps):
    """[(sigla, [deputados])] ordenado por tamanho desc e depois sigla."""
    g = {}
    for d in deps:
        g.setdefault(d["siglaPartido"], []).append(d)
    return sorted(g.items(), key=lambda kv: (-len(kv[1]), kv[0]))


def deputado(id_):
    return get(f"/deputados/{id_}")[0]


def partidos():
    return _cached("partidos", lambda: get("/partidos", itens=100, ordem="ASC", ordenarPor="sigla")[0])


def ufs():
    return _cached("ufs", lambda: get("/referencias/deputados/siglaUF")[0])


# ---------- Proposições e votações ----------

def proposicoes(pagina=1, itens=20, **filtros):
    """Lista de proposições, mais recentes primeiro. filtros: siglaTipo, ano, keywords,
    siglaPartidoAutor, idDeputadoAutor, siglaUfAutor, codSituacao, codTema."""
    return get("/proposicoes", pagina=pagina, itens=itens, ordem="DESC", ordenarPor="id", **filtros)


def proposicao(id_):
    return get(f"/proposicoes/{id_}")[0]


def proposicao_autores(id_):
    return get(f"/proposicoes/{id_}/autores")[0] or []


def proposicao_tramitacoes(id_):
    return get(f"/proposicoes/{id_}/tramitacoes")[0] or []


def proposicao_votacoes(id_):
    return get(f"/proposicoes/{id_}/votacoes", ordem="DESC", ordenarPor="dataHoraRegistro")[0] or []


def tipos_proposicao():
    """[(sigla, nome)] dos tipos de proposição, para o filtro."""
    return _cached("tipos", lambda: [(t["sigla"], t["nome"])
                                     for t in get("/referencias/proposicoes/siglaTipo")[0]], ttl=86400)


def votacoes(data_inicio, data_fim, pagina=1, itens=20):
    return get("/votacoes", dataInicio=data_inicio, dataFim=data_fim, pagina=pagina, itens=itens,
               ordem="DESC", ordenarPor="dataHoraRegistro")


def votacao(id_):
    return get(f"/votacoes/{id_}")[0]


def votacao_votos(id_):
    """Votos nominais ([] se simbólica). Este endpoint não aceita pagina/itens (400)."""
    return _cached(("votos", id_), lambda: get(f"/votacoes/{id_}/votos")[0] or [])


def votacao_orientacoes(id_):
    return get(f"/votacoes/{id_}/orientacoes")[0] or []


def votos_por_partido(votos):
    """[(sigla, {tipoVoto: n}, total)] ordenado por total desc. O deputado vem em 'deputado_'."""
    g = {}
    for v in votos:
        c = g.setdefault(v["deputado_"]["siglaPartido"], {})
        c[v["tipoVoto"]] = c.get(v["tipoVoto"], 0) + 1
    return sorted(((s, c, sum(c.values())) for s, c in g.items()), key=lambda t: (-t[2], t[0]))
