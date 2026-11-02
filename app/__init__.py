import re
import secrets
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

import requests
from flask import Flask, abort, g, render_template, request

from . import camara_api as api
from . import cotas

ANO_MIN = 2009  # primeiro ano com arquivos de cota parlamentar

CSP = ("default-src 'none'; script-src 'self' https://cdnjs.cloudflare.com 'nonce-{nonce}'; "
       "style-src 'self' 'unsafe-inline'; img-src 'self' data: https://www.camara.leg.br; "
       "connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")


def brl(v, casas=2):
    return "R$ " + f"{v:,.{casas}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def brl_curto(v):
    for lim, suf in ((1e9, " bi"), (1e6, " mi"), (1e3, " mil")):
        if v >= lim:
            return f"R$ {v / lim:,.1f}".replace(".", ",") + suf
    return brl(v, 0)


def anos_disponiveis():
    hoje = date.today().year
    return list(range(hoje, hoje - 6, -1))


def ano_da_url():
    """Ano pedido na URL, limitado ao intervalo válido (evita downloads de anos arbitrários)."""
    ano = request.args.get("ano", date.today().year, type=int)
    return min(max(ano, ANO_MIN), date.today().year)


def texto_url(nome, tamanho=60):
    """Parâmetro de texto da URL, sem caracteres de controle e com tamanho limitado."""
    return re.sub(r"[\x00-\x1f]", "", request.args.get(nome, ""))[:tamanho].strip()


def data_url(nome, padrao):
    v = request.args.get(nome, "")
    try:
        return date.fromisoformat(v)
    except ValueError:
        return padrao


def id_de_uri(uri):
    m = re.search(r"/(\d+)$", uri or "")
    return int(m.group(1)) if m else None


def create_app():
    app = Flask(__name__)
    app.jinja_env.filters["brl"] = brl
    app.jinja_env.filters["brl_curto"] = brl_curto

    @app.before_request
    def _nonce():
        g.nonce = secrets.token_urlsafe(16)

    @app.context_processor
    def _ctx():
        return {"nonce": g.nonce}

    @app.after_request
    def _seguranca(resp):
        resp.headers["Content-Security-Policy"] = CSP.format(nonce=g.nonce)
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Referrer-Policy"] = "same-origin"
        resp.headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()"
        return resp

    @app.errorhandler(requests.RequestException)
    def erro_api(e):
        app.logger.error("Falha ao consultar a Câmara: %s", e)
        return render_template("erro.html"), 502

    @app.route("/")
    def index():
        f = {k: request.args.get(k, "") for k in ("nome", "partido", "uf")}
        ano = ano_da_url()
        deps = api.buscar_deputados(f["nome"], f["partido"], f["uf"])
        totais = cotas.totais_por_deputado(ano)
        grupos = []
        for sigla, ds in api.agrupar_por_partido(deps):
            for d in ds:
                d["gasto"] = totais.get(d["id"], 0.0)
            soma = sum(d["gasto"] for d in ds)
            grupos.append({"sigla": sigla, "deps": ds, "gasto": soma, "media": soma / len(ds)})
        total_gasto = sum(g["gasto"] for g in grupos)
        maior = max(grupos, key=lambda g: g["gasto"], default=None)
        return render_template("index.html", grupos=grupos, total=len(deps), f=f, ano=ano,
                               anos=anos_disponiveis(), total_gasto=total_gasto, maior=maior,
                               partidos=api.partidos(), ufs=api.ufs(),
                               graf={"siglas": [g["sigla"] for g in grupos],
                                     "deps": [len(g["deps"]) for g in grupos],
                                     "gasto": [round(g["gasto"], 2) for g in grupos]})


    @app.route("/deputado/<int:id_>")
    def deputado(id_):
        ano = ano_da_url()
        d = api.deputado(id_)
        linhas = cotas.despesas(id_, ano)
        total, por_tipo = cotas.resumo(linhas)
        return render_template("deputado.html", d=d, despesas=linhas[:200], n=len(linhas), total=total,
                               por_tipo=por_tipo, ano=ano, anos=anos_disponiveis(),
                               graf={"meses": cotas.por_mes(linhas),
                                     "tipos": [t for t, _ in por_tipo[:8]],
                                     "valores": [round(v, 2) for _, v in por_tipo[:8]]})

    @app.route("/votacoes")
    def votacoes():
        hoje = date.today()
        fim = data_url("fim", hoje)
        ini = min(data_url("ini", hoje - timedelta(days=30)), fim)
        pagina = max(request.args.get("pagina", 1, type=int), 1)
        lista, links = api.votacoes(ini.isoformat(), fim.isoformat(), pagina)
        return render_template("votacoes.html", lista=lista or [], ini=ini, fim=fim, pagina=pagina,
                               tem_prox="next" in links)

    @app.route("/votacoes/<id_>")
    def votacao(id_):
        if not re.fullmatch(r"[\w-]{1,30}", id_):
            abort(404)
        v = api.votacao(id_)
        votos = api.votacao_votos(id_)
        por_partido = api.votos_por_partido(votos)
        tipos = sorted({t for _, c, _ in por_partido for t in c})
        return render_template("votacao.html", v=v, orient=api.votacao_orientacoes(id_), n_votos=len(votos),
                               por_partido=por_partido, tipos=tipos,
                               graf={"siglas": [s for s, _, _ in por_partido], "tipos": tipos,
                                     "dados": {t: [c.get(t, 0) for _, c, _ in por_partido] for t in tipos}})

    @app.route("/proposicoes")
    def proposicoes():
        f = {"tipo": texto_url("tipo", 10).upper(), "ano": texto_url("ano", 4), "q": texto_url("q", 80),
             "partido": texto_url("partido", 10).upper(), "autor": texto_url("autor"), "uf": texto_url("uf", 2).upper()}
        pagina = max(request.args.get("pagina", 1, type=int), 1)
        filtros, aviso = {}, None
        if re.fullmatch(r"[A-Z]{1,10}", f["tipo"]):
            filtros["siglaTipo"] = f["tipo"]
        if re.fullmatch(r"\d{4}", f["ano"]):
            filtros["ano"] = f["ano"]
        if f["q"]:
            filtros["keywords"] = f["q"]
        if re.fullmatch(r"[A-Z ]{1,10}", f["partido"]):
            filtros["siglaPartidoAutor"] = f["partido"]
        if re.fullmatch(r"[A-Z]{2}", f["uf"]):
            filtros["siglaUfAutor"] = f["uf"]
        if f["autor"]:
            # o filtro 'autor=' da API dá timeout; resolvemos o nome para ids de deputados
            ids = [str(d["id"]) for d in api.buscar_deputados(f["autor"])][:20]
            if ids:
                filtros["idDeputadoAutor"] = ",".join(ids)
            else:
                aviso = "Nenhum deputado em exercício encontrado com esse nome."
        lista, links = ([], {}) if aviso else api.proposicoes(pagina, **filtros)
        return render_template("proposicoes.html", lista=lista or [], f=f, pagina=pagina, aviso=aviso,
                               tem_prox="next" in links, tipos=api.tipos_proposicao(), ufs=api.ufs())

    @app.route("/proposicao/<int:id_>")
    def proposicao(id_):
        with ThreadPoolExecutor(4) as ex:
            fs = [ex.submit(fn, id_) for fn in (api.proposicao, api.proposicao_autores,
                                                api.proposicao_tramitacoes, api.proposicao_votacoes)]
            p, autores, tram, vots = [f.result() for f in fs]
        for a in autores:
            a["dep_id"] = id_de_uri(a["uri"]) if "/deputados/" in (a.get("uri") or "") else None
        return render_template("proposicao.html", p=p, autores=autores, tram=tram[::-1][:60],
                               n_tram=len(tram), vots=vots)

    return app
