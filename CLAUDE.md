# CLAUDE.md — Plenário Aberto

## Objetivo do projeto

**Plenário Aberto** (`plenario-aberto`) é um projeto independente e não oficial: um painel web (Flask) para **consultar e visualizar os dados abertos da Câmara dos Deputados** a partir da [API pública](https://dadosabertos.camara.leg.br), sem exigir que o usuário conheça a API. Escopo atual:

- **Deputados:** painel por partido, busca (nome com `%`, partido, UF, ano) e perfil com despesas da cota parlamentar.
- **Votações e proposições:** lista, detalhe, votos por partido, orientações e tramitação.
- **Somente leitura:** a API aceita apenas `GET` e o painel não grava dados (só o cache de CSVs em `cache/`).

Públicos e formas de uso: uso local (macOS/Windows, `localhost`) e servidor Ubuntu com Apache + HTTPS. Os instaladores ficam em `deploy/`.

Princípios ao evoluir o projeto:
- Começar simples (script/CLI) e usar Flask só quando a interface for necessária.
- Toda chamada à API passa pelo cliente em `app/camara_api.py`; nada de requisições soltas nas rotas.
- A API tem limitações (despesas vazias, votos sem paginação, timeouts); preferir a fonte alternativa já adotada (CSVs anuais) e consultar [docs/api-votacoes-proposicoes.md](docs/api-votacoes-proposicoes.md) antes de assumir que um endpoint funciona.

### Referências da API

Detalhes e exemplos também estão no [README](README.md#api-de-dados-abertos-da-câmara-referência) e em [docs/infos.md](docs/infos.md):
- Tutoriais: https://dadosabertos.camara.leg.br/howtouse/central-tutoriais.html
- Swagger (UI): https://dadosabertos.camara.leg.br/swagger/api.html
- Especificação OpenAPI (JSON): https://dadosabertos.camara.leg.br/api/v2/api-docs
- Base da API: `https://dadosabertos.camara.leg.br/api/v2` (somente `GET`, sem autenticação)

## Rodar localmente

```bash
source .venv/bin/activate
flask --app wsgi run --debug    # http://127.0.0.1:5000
```

## Regras de trabalho

- Usar **Python em ambiente virtual (venv)** para todos os scripts:
  ```bash
  python3 -m venv .venv && source .venv/bin/activate
  pip install -r requirements.txt
  ```
- Interface web com **Flask**, apenas quando necessário (scripts/CLI primeiro se bastarem).
- Dependências em `requirements.txt` (ex.: `flask`, `requests`).
- Cliente da API isolado em um módulo próprio (ex.: `camara_api.py`), reutilizado por scripts e pelo Flask.
- Respeitar paginação da API (`pagina`, `itens`, `links` com `next`/`last`) e tratar erros/timeouts.
- Responder em português.
- Arquivos temporários ficam fora do projeto (scratchpad); não versionar `.venv`.

## Estrutura

```
plenario-aberto/
├── CLAUDE.md
├── README.md
├── wsgi.py              # entrada do gunicorn (wsgi:app)
├── requirements.txt
├── app/
│   ├── __init__.py      # create_app(): rotas, filtros, cabeçalhos de segurança
│   ├── camara_api.py    # cliente da API (cache, busca com %, agrupamento por partido)
│   ├── cotas.py         # despesas a partir dos CSVs anuais (a API de despesas retorna vazio)
│   ├── templates/       # base, index (painel), deputado, erro
│   └── static/
├── cache/               # CSVs de cota baixados (ignorado no git)
├── public/              # DocumentRoot do Apache (só index.html vazio)
├── deploy/              # install ubuntu server/ (apache, systemd, fail2ban), install macos/, install windows/
└── docs/infos.md        # links e exemplos da API
```

Os `index.html` vazios em cada diretório evitam listagem de diretórios. Exceção: `app/templates/index.html` é o template real do painel; não sobrescrever.

Limitações conhecidas de votações/proposições (votos sem paginação, `autor=` com timeout, etc.): [docs/api-votacoes-proposicoes.md](docs/api-votacoes-proposicoes.md).

## Recursos da API (resumo do OpenAPI)

| Grupo | Endpoints principais |
|---|---|
| Deputados | `/deputados`, `/{id}`, `/despesas`, `/discursos`, `/eventos`, `/frentes`, `/historico`, `/mandatosExternos`, `/ocupacoes`, `/orgaos`, `/profissoes` |
| Partidos | `/partidos`, `/{id}`, `/lideres`, `/membros` |
| Blocos | `/blocos`, `/{id}`, `/{id}/partidos` |
| Proposições | `/proposicoes`, `/{id}`, `/autores`, `/relacionadas`, `/temas`, `/tramitacoes`, `/votacoes` |
| Votações | `/votacoes`, `/{id}`, `/orientacoes`, `/votos` |
| Eventos | `/eventos`, `/{id}`, `/deputados`, `/orgaos`, `/pauta`, `/votacoes` |
| Órgãos | `/orgaos`, `/{id}`, `/eventos`, `/membros`, `/votacoes` |
| Frentes | `/frentes`, `/{id}`, `/membros` |
| Grupos | `/grupos`, `/{id}`, `/historico`, `/membros` |
| Legislaturas | `/legislaturas`, `/{id}`, `/{id}/lideres`, `/{id}/mesa` |
| Referências | `/referencias/...` (UFs, tipos, situações, temas, tipos de despesa etc.) para popular filtros |
