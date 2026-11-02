# API da Câmara: votações e proposições

Verificado contra a especificação (`/api/v2/api-docs`) e com chamadas reais em 30/10/2026.

## Proposições

| Endpoint | Situação |
|---|---|
| `GET /proposicoes` | Funciona. Filtros: `id`, `siglaTipo`, `codTipo`, `numero`, `ano`, `idDeputadoAutor`, `siglaPartidoAutor`, `idPartidoAutor`, `siglaUfAutor`, `keywords`, `codSituacao`, `codTema`, `tramitacaoSenado`, `dataInicio/dataFim` (tramitação), `dataApresentacaoInicio/Fim`, `pagina`, `itens`, `ordem`, `ordenarPor` (`id`, `codTipo`, `siglaTipo`, `numero`, `ano`) |
| `GET /proposicoes/{id}` | Funciona. Traz ementa, ementa detalhada, keywords, `statusProposicao` (situação atual), `urlInteiroTeor`, `uriAutores` |
| `/proposicoes/{id}/autores` | Funciona. Lista de autores com `ordemAssinatura` e `proponente` |
| `/proposicoes/{id}/tramitacoes` | Funciona. Ordem cronológica (mais antiga primeiro); aceita `dataInicio/dataFim`. Pode ter centenas de itens (162 num PL de exemplo) |
| `/proposicoes/{id}/votacoes` | Funciona, mas vem vazio para proposições que nunca foram votadas |
| `/proposicoes/{id}/temas`, `/relacionadas` | Funcionam, mas muitas proposições retornam lista vazia |

**Problemas:**
- **`autor=` dá timeout (504)**, de forma consistente (~15 s). A busca por nome de autor da proposição não é utilizável. Alternativa: achar o deputado por `/deputados?nome=...` e filtrar por `idDeputadoAutor`.
- O filtro `autor` exige o nome entre aspas, segundo a especificação.
- A ordenação de `/proposicoes` não cobre data de apresentação. Para "as mais recentes", usar `ordenarPor=id&ordem=DESC`.
- Há proposições com `ano: 0` (ex.: Redação Final).

## Votações

| Endpoint | Situação |
|---|---|
| `GET /votacoes` | Funciona. Filtros: `id`, `idProposicao`, `idEvento`, `idOrgao`, `dataInicio`, `dataFim`, `pagina`, `itens`, `ordem`, `ordenarPor` (`id`, `idOrgao`, `siglaOrgao`, `idEvento`, `idProposicao`, `data`, `dataHoraRegistro`, `titulo`...) |
| `GET /votacoes/{id}` | Funciona. `id` é **texto** (ex.: `2442848-47`). Traz `descricao` (com o placar), `aprovacao` (0/1), `proposicoesAfetadas`, `objetosPossiveis`, `efeitosRegistrados` |
| `GET /votacoes/{id}/votos` | Funciona só para votações **nominais**. Retorna todos os votos de uma vez |
| `GET /votacoes/{id}/orientacoes` | Funciona. Orientação por partido, bloco ou governo/maioria/minoria. Vazia em votações sem orientação registrada |
| `/orgaos/{id}/votacoes`, `/eventos/{id}/votacoes` | Funcionam (mesmos filtros de data) |

**Problemas:**
- **`/votos` não aceita paginação:** qualquer `itens` ou `pagina` devolve **HTTP 400**. Não enviar esses parâmetros.
- **Muitas votações têm 0 votos:** são votações simbólicas, sem voto individual. Das 12 testadas em março/2025, 7 tinham 0 votos. Não é erro.
- **O campo do deputado em cada voto chama-se `deputado_`** (com underscore no final), e não `deputado`. O `tipoVoto` pode ser `Sim`, `Não`, `Abstenção`, `Obstrução` ou `Artigo 17`.
- **Não existe endpoint de votos por deputado** (`/deputados/{id}/votacoes` retorna 405). Para saber como um deputado votou, é preciso buscar `/votacoes/{id}/votos` de cada votação e filtrar. É 1 chamada por votação.
- Alguns ids vêm como texto (`idOrgao`, `idEvento`) e outros como número.

## O que dá para construir

- **Proposições:** busca por tipo, ano, tema, situação, partido, UF ou deputado autor, com detalhe, autores e linha do tempo da tramitação.
- **Votações:** lista por período, placar, aprovada ou rejeitada, votos por partido (agrupando `/votos` por `siglaPartido`) e orientação das lideranças contra o voto real (quem seguiu ou desobedeceu a orientação).
- **Cruzamentos:** proposições de um deputado e de um partido, e votações de uma proposição.
- **Não dá, ou é inviável:** busca por nome de autor de proposição (`autor=`) e histórico de votos de um deputado sem varrer votação por votação.
