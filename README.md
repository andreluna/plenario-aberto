# Plenário Aberto

Painel web (Flask) para consultar deputados, votações, proposições e despesas da Câmara dos Deputados, a partir da [API de Dados Abertos da Câmara](https://dadosabertos.camara.leg.br).

> Projeto independente e **não oficial**: não é mantido nem endossado pela Câmara dos Deputados. Os dados vêm da API pública da Câmara.

## ▶️ Rodar localmente (início rápido)

```bash
cd /caminho/para/plenario-aberto
source .venv/bin/activate
flask --app wsgi run --debug
```

Abra **http://127.0.0.1:5000**. Para parar: `Ctrl+C`. Primeira vez? Veja [Instalação local](#instalação-local).

### Instalação automática (macOS e Windows 11)

Os instaladores em [deploy/install macos/](<deploy/install macos/>) e [deploy/install windows/](<deploy/install windows/>) servem **apenas para uso local (localhost)**: o painel roda no seu computador em `http://127.0.0.1:5000`, acessível só por você. Não configuram domínio, HTTPS, Apache nem serviço em segundo plano; para publicar na internet use o [deploy em Ubuntu](#deploy-em-ubuntu-apache--https-lets-encrypt-porta-443).

Os dois fazem os mesmos passos e podem ser executados de novo quando quiser (atualizam as dependências sem estragar nada). **Não precisam de administrador/sudo.**

| Passo | O que o script faz |
|---|---|
| 1 | Verifica se existe **Python 3.10 ou mais novo**. Se não existir, instala (Homebrew no Mac, `winget` no Windows) ou mostra onde baixar. |
| 2 | Cria o ambiente virtual `.venv` na pasta do projeto (se o `.venv` for de outro sistema, apaga e recria). |
| 3 | Instala as dependências do `requirements.txt` (no Windows troca o `gunicorn` por `waitress`, pois o gunicorn não roda no Windows). |
| 4 | Cria a pasta `cache/` e pergunta se deve **iniciar o painel agora** (abre o navegador sozinho). |

#### macOS (MacBook)

1. Obtenha a pasta do projeto (`git clone` ou copie) e abra o **Terminal**.
2. Entre na pasta e execute:

   ```bash
   cd /caminho/para/plenario-aberto
   ./deploy/install\ macos/install.sh
   ```

   Se aparecer "permission denied": `chmod +x "deploy/install macos/install.sh"` e rode de novo (ou `bash "deploy/install macos/install.sh"`).
3. Responda `S` (ou Enter) a "Iniciar o painel agora?". O navegador abre em **http://127.0.0.1:5000**. Para parar: `Ctrl+C` no Terminal.

Opções: `--run` (instala e inicia sem perguntar) e `--no-run` (só instala).

- **Sem Python e sem Homebrew:** o script para e indica https://www.python.org/downloads/macos/ ou https://brew.sh. Instale um dos dois e rode de novo.
- **Python recém-instalado não encontrado:** feche e abra o Terminal e rode de novo.
- **Não use `sudo`:** o script recusa, para o `.venv` não ficar com dono errado.

#### Windows 11

1. Obtenha a pasta do projeto (`git clone`, ou baixe o ZIP e extraia) e abra o **PowerShell** (menu Iniciar > "PowerShell").
2. Entre na pasta e execute:

   ```powershell
   cd C:\caminho\para\plenario-aberto
   powershell -ExecutionPolicy Bypass -File ".\deploy\install windows\install.ps1"
   ```

   O `-ExecutionPolicy Bypass` vale só para esta execução e evita o erro "a execução de scripts foi desabilitada", sem mudar a configuração do Windows.
3. O script **verifica se o Python 3.10+ já está instalado** (comandos `py`, `python` e `python3`; o atalho falso da Microsoft Store é ignorado). Se não houver, instala o Python 3.12 com `winget` (para o seu usuário, sem administrador).
4. Responda `S` (ou Enter) a "Iniciar o painel agora?". O navegador abre em **http://127.0.0.1:5000**. Para parar: `Ctrl+C` no PowerShell.

Parâmetros: `-Run` (instala e inicia sem perguntar) e `-NoRun` (só instala).

- **`winget` indisponível:** instale o Python 3.12 em https://www.python.org/downloads/windows/ marcando **"Add python.exe to PATH"** e rode de novo.
- **Python instalado mas "não está no PATH":** feche e abra o PowerShell e rode de novo.
- **Firewall do Windows** pode perguntar sobre o Python; como o painel escuta só em 127.0.0.1, pode negar o acesso a redes.

#### Depois de instalado: iniciar de novo

Não precisa rodar o instalador toda vez. Basta ativar o `.venv` e iniciar:

```bash
# macOS
cd /caminho/para/plenario-aberto && source .venv/bin/activate && flask --app wsgi run --debug
```

```powershell
# Windows (PowerShell)
cd C:\caminho\para\plenario-aberto; .venv\Scripts\Activate.ps1; flask --app wsgi run --debug
```

Para atualizar o projeto (novo código ou dependências), substitua os arquivos e rode o instalador de novo.

### Windows 11 (PowerShell, manual)

```powershell
cd C:\caminho\para\plenario-aberto
.venv\Scripts\Activate.ps1
flask --app wsgi run --debug
```

Abra **http://127.0.0.1:5000**. Para parar: `Ctrl+C`.

Primeira vez no Windows (a pasta `.venv` do macOS/Linux não funciona no Windows, crie outra):

```powershell
winget install Python.Python.3.12        # se ainda não tiver Python 3.10+ (reabra o terminal depois)
cd C:\caminho\para\plenario-aberto
py -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

- **Erro "a execução de scripts foi desabilitada"** ao ativar o venv: rode uma vez `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` e tente de novo. Alternativa sem mudar a política: use o Prompt de Comando (`cmd`) com `.venv\Scripts\activate.bat`.
- **Não copie a pasta `.venv`** de outro sistema; apague-a e recrie como acima.
- **`gunicorn` não roda no Windows.** Use o `flask run` acima, ou `pip install waitress` e `waitress-serve --listen=127.0.0.1:8000 wsgi:app`.

## O que o projeto faz

- **Painel inicial:** deputados em exercício agrupados por partido, com nome, ID, UF, total de deputados e gasto da cota parlamentar por partido (em tabelas e gráficos).
- **Busca:** por nome com curinga `%` (`%marina%`, `ana%`, `%silva`; ignora acentos e maiúsculas), por partido (`PT,PL`), por UF e por ano.
- **Perfil do deputado:** dados cadastrais e despesas do ano (total, por mês, por tipo e lançamentos com link para a nota).
- **Votações:** lista por período; o detalhe mostra placar, resultado, proposições afetadas, votos por partido (gráfico e tabela) e a orientação das lideranças.
- **Proposições:** busca por palavra-chave, tipo, ano, partido, UF e deputado autor; o detalhe mostra ementa, situação, autores, votações e linha do tempo da tramitação.
- **Tema claro/escuro:** botão no topo; sem escolha, segue o tema do sistema.

### Observação sobre as despesas

Limitações da API para votações e proposições estão em [docs/api-votacoes-proposicoes.md](docs/api-votacoes-proposicoes.md).

O endpoint `/deputados/{id}/despesas` da API retorna sempre lista vazia (verificado em 30/10/2026). Por isso as despesas vêm dos arquivos anuais oficiais `https://www.camara.leg.br/cotas/Ano-AAAA.csv.zip`, baixados sob demanda para `cache/`:

- anos passados nunca expiram; o ano corrente é renovado a cada 24 h;
- o primeiro acesso a cada ano baixa de 4 a 7 MB e leva alguns segundos.

## API de Dados Abertos da Câmara (referência)

O painel consome a API pública da Câmara; o cliente fica em [app/camara_api.py](app/camara_api.py). Referências oficiais:

- **Tutoriais:** https://dadosabertos.camara.leg.br/howtouse/central-tutoriais.html
- **Swagger (interface interativa):** https://dadosabertos.camara.leg.br/swagger/api.html
- **Especificação OpenAPI (JSON):** https://dadosabertos.camara.leg.br/api/v2/api-docs
- **Base:** `https://dadosabertos.camara.leg.br/api/v2` (somente `GET`, sem autenticação)

Exemplos de requisição:

```
GET /api/v2/deputados?ordem=ASC&ordenarPor=nome
GET /api/v2/partidos/36779
```

Paginação: parâmetros `pagina` e `itens`; a resposta traz `dados` e `links` (`next`, `last`). O cliente do projeto percorre as páginas e trata erros e timeouts.

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
| Referências | `/referencias/...` (UFs, tipos, situações, temas, tipos de despesa etc.) |

Limitações conhecidas (votos sem paginação, `autor=` com timeout, despesas vazias na API etc.): [docs/api-votacoes-proposicoes.md](docs/api-votacoes-proposicoes.md). As despesas vêm dos CSVs anuais (ver "Observação sobre as despesas").

## Estrutura

```
├── wsgi.py              # entrada do gunicorn (wsgi:app)
├── requirements.txt     # flask, requests, gunicorn
├── app/
│   ├── __init__.py      # create_app(): rotas, filtros, cabeçalhos de segurança
│   ├── camara_api.py    # cliente da API, cache, busca com %, agrupamento por partido
│   ├── cotas.py         # despesas a partir dos CSVs anuais
│   ├── templates/       # base, index (painel), deputado, erro
│   └── static/
├── cache/               # CSVs baixados (ignorado no git)
├── public/              # DocumentRoot do Apache (só um index.html vazio)
├── deploy/
│   ├── install ubuntu server/   # install.sh + apache/, systemd/, fail2ban/ (servidor)
│   ├── install macos/           # install.sh (MacBook)
│   └── install windows/         # install.ps1 (Windows 11)
└── docs/infos.md        # links e exemplos da API
```

Cada diretório tem um `index.html` vazio para impedir listagem de arquivos caso algum seja exposto por engano. A exceção é `app/templates/index.html`, que é o template real do painel e não deve ser esvaziado.

## Instalação local

Requisitos: Python 3.10+. (No Windows 11, veja o passo a passo no início deste README.)

```bash
git clone <repositório> plenario-aberto && cd plenario-aberto   # ou copie a pasta
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Uso

Desenvolvimento (recarrega ao salvar):

```bash
flask --app wsgi run --debug        # http://127.0.0.1:5000
```

Produção local, sem Apache:

```bash
gunicorn --workers 1 --threads 8 --timeout 180 --bind 127.0.0.1:8000 wsgi:app
```

Rotas:

| Rota | Descrição |
|---|---|
| `/` | Painel. Parâmetros: `nome`, `partido`, `uf`, `ano` |
| `/deputado/<id>?ano=2025` | Perfil e despesas |
| `/votacoes` | Votações por período. Parâmetros: `ini`, `fim`, `pagina` |
| `/votacoes/<id>` | Placar, votos por partido e orientações |
| `/proposicoes` | Busca. Parâmetros: `q`, `tipo`, `ano`, `partido`, `autor`, `uf`, `pagina` |
| `/proposicao/<id>` | Detalhe, autores, votações e tramitação |

---

## Deploy em Ubuntu (Apache + HTTPS Let's Encrypt, porta 443)

Arquitetura: **Apache** (80/443, TLS) → proxy reverso → **gunicorn** em `127.0.0.1:8000` (só local) → Flask. O Flask nunca fica exposto diretamente.

### Instalação automática (recomendado)

O script [deploy/install ubuntu server/install.sh](<deploy/install ubuntu server/install.sh>) faz todos os passos abaixo (pacotes, usuário, venv, systemd, Apache, firewall e certificado Let's Encrypt) e pergunta as variáveis necessárias: domínio, e-mail, diretório de instalação, porta local, uso do ambiente de teste do Let's Encrypt, UFW, fail2ban (com IPs que nunca devem ser bloqueados) e mod_evasive.

```bash
sudo "./deploy/install ubuntu server/install.sh"
# ou, sem perguntas:
sudo DOMINIO=painel.exemplo.com.br EMAIL=voce@exemplo.com.br "./deploy/install ubuntu server/install.sh" -y
```

O usuário do serviço é fixo (`plenario-aberto`): se não existir no servidor, o script o cria (usuário de sistema, sem shell de login); se já existir, é reaproveitado. Antes de rodar, o DNS do domínio já deve apontar para o servidor e as portas 80 e 443 devem estar liberadas (inclusive no firewall do provedor). Para testar sem esgotar o limite do Let's Encrypt, responda "sim" à pergunta do ambiente de teste (ou use `STAGING=s`). O script pode ser executado de novo para atualizar o código. O passo a passo manual está abaixo.

Os exemplos usam o domínio `painel.exemplo.com.br` e a pasta `/opt/plenario-aberto`. Troque pelos seus. Pré-requisito: o DNS do domínio já aponta para o IP do servidor.

### 1. Pacotes e firewall

```bash
sudo apt update && sudo apt install -y apache2 python3-venv python3-pip certbot ufw rsync
sudo a2enmod ssl proxy proxy_http headers rewrite
sudo ufw allow OpenSSH && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable
```

A porta 8000 não é aberta no firewall: o gunicorn escuta só em `127.0.0.1`.

### 2. Usuário e código

```bash
sudo useradd --system --home /opt/plenario-aberto --shell /usr/sbin/nologin plenario-aberto
sudo mkdir -p /opt/plenario-aberto
sudo rsync -a --exclude .venv --exclude cache/'*.zip' --exclude .claude ./ /opt/plenario-aberto/
sudo python3 -m venv /opt/plenario-aberto/.venv
sudo /opt/plenario-aberto/.venv/bin/pip install -r /opt/plenario-aberto/requirements.txt

# código somente leitura para o serviço; só cache/ é gravável
sudo chown -R root:plenario-aberto /opt/plenario-aberto
sudo chmod -R o-rwx /opt/plenario-aberto
sudo chown -R plenario-aberto:plenario-aberto /opt/plenario-aberto/cache
sudo chmod 750 /opt/plenario-aberto/cache
sudo chmod 755 /opt/plenario-aberto /opt/plenario-aberto/public && sudo chmod 644 /opt/plenario-aberto/public/index.html
```

O Apache (`www-data`) só precisa ler `public/`, que contém apenas o `index.html` vazio e o desafio do Let's Encrypt. O código fica fora do DocumentRoot.

### 3. Serviço systemd (gunicorn)

```bash
sudo cp "/opt/plenario-aberto/deploy/install ubuntu server/systemd/plenario-aberto.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now plenario-aberto
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/     # esperado: 200
```

O arquivo [deploy/install ubuntu server/systemd/plenario-aberto.service](<deploy/install ubuntu server/systemd/plenario-aberto.service>) roda com usuário sem privilégios e com sandbox (`ProtectSystem=strict`, `NoNewPrivileges`, escrita só em `cache/`). Usa 1 worker com 8 threads porque o índice de despesas fica em memória e é compartilhado entre as threads (cada ano carregado ocupa algumas centenas de MB).

### 4. Apache: HTTP e certificado

Edite o domínio nos três arquivos de [deploy/install ubuntu server/apache/](<deploy/install ubuntu server/apache/>) e instale:

```bash
sudo cp "/opt/plenario-aberto/deploy/install ubuntu server/apache/plenario-aberto-http.conf" /etc/apache2/sites-available/
sudo cp "/opt/plenario-aberto/deploy/install ubuntu server/apache/plenario-aberto-ssl.conf"  /etc/apache2/sites-available/
sudo cp "/opt/plenario-aberto/deploy/install ubuntu server/apache/seguranca.conf"   /etc/apache2/conf-available/

sudo a2dissite 000-default
sudo a2enconf seguranca
sudo a2ensite plenario-aberto-http            # só o HTTP por enquanto: o certificado ainda não existe
sudo apache2ctl configtest && sudo systemctl reload apache2

sudo certbot certonly --webroot -w /opt/plenario-aberto/public -d painel.exemplo.com.br \
  -m voce@exemplo.com.br --agree-tos --no-eff-email
```

### 5. Apache: HTTPS na porta 443

```bash
sudo a2ensite plenario-aberto-ssl
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI https://painel.exemplo.com.br/ | head -20
```

Renovação automática: o pacote `certbot` instala um timer systemd. Teste com:

```bash
sudo certbot renew --dry-run
echo -e '#!/bin/sh\nsystemctl reload apache2' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/apache-reload.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/apache-reload.sh
```

### Exemplo de vhost (resumo)

Os arquivos completos e comentados estão em [deploy/install ubuntu server/apache/](<deploy/install ubuntu server/apache/>). O essencial do vhost 443:

```apache
<VirtualHost *:443>
    ServerName painel.exemplo.com.br
    DocumentRoot /opt/plenario-aberto/public

    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/painel.exemplo.com.br/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/painel.exemplo.com.br/privkey.pem
    SSLProtocol -all +TLSv1.2 +TLSv1.3

    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"

    ProxyRequests Off
    ProxyPreserveHost On
    ProxyPass        /.well-known/ !
    ProxyPass        / http://127.0.0.1:8000/ timeout=180
    ProxyPassReverse / http://127.0.0.1:8000/
    RequestHeader set X-Forwarded-Proto "https"
</VirtualHost>
```

### Proteções incluídas

**Apache** ([plenario-aberto-ssl.conf](<deploy/install ubuntu server/apache/plenario-aberto-ssl.conf>), [seguranca.conf](<deploy/install ubuntu server/apache/seguranca.conf>)):
- TLS 1.2/1.3 apenas, OCSP stapling, HSTS e redirecionamento 80 → 443.
- `ServerTokens Prod`, `ServerSignature Off`, `TraceEnable Off`: não revelam versões.
- Só métodos `GET` e `HEAD` (a aplicação é somente leitura).
- Limites de corpo, linha e cabeçalhos e `RequestReadTimeout` (mitiga slowloris).
- `Options -Indexes`, `AllowOverride None`, bloqueio de `.git`, `.venv`, `.py`, `.env`, `.log`, `.zip` etc.
- `ProxyRequests Off`: não funciona como proxy aberto.
- DocumentRoot separado do código.

**Flask** ([app/__init__.py](app/__init__.py)):
- `Content-Security-Policy` com nonce por requisição (scripts inline só com nonce; externos só de `cdnjs.cloudflare.com`; imagens só de `www.camara.leg.br`), `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`.
- Autoescape do Jinja em todos os templates; sem banco de dados, sessões nem segredos.
- O parâmetro `ano` é limitado a 2009 até o ano atual (impede downloads de anos arbitrários).
- A página de erro não vaza detalhes: o erro vai apenas para o log.

**Sistema** ([plenario-aberto.service](<deploy/install ubuntu server/systemd/plenario-aberto.service>)):
- Usuário `plenario-aberto` sem shell, `NoNewPrivileges`, `ProtectSystem=strict`, escrita só em `cache/`, gunicorn só em `127.0.0.1`.
- UFW liberando apenas SSH, 80 e 443.

**Instaladas pelo `install.sh`** (cada uma com pergunta de confirmação):
- **mod_evasive** ([evasive.conf](<deploy/install ubuntu server/apache/evasive.conf>)): limita requisições por IP (mais de 10 na mesma página em 2 s, ou 60 no site em 2 s, geram 403 por 120 s). Escolhido no lugar do mod_security, que é mais pesado, gera falsos positivos e traria pouco ganho para uma aplicação somente leitura que já valida a entrada.
- **fail2ban** ([jail.plenario-aberto.local](<deploy/install ubuntu server/fail2ban/jail.plenario-aberto.local>) e [plenario-aberto-http-erros.conf](<deploy/install ubuntu server/fail2ban/filter.d/plenario-aberto-http-erros.conf>)): bloqueia no firewall, por 1 h, IPs com tentativas de login SSH, robôs conhecidos, requisições malformadas e varreduras (30 respostas 400/403/404/405 em 60 s, o que inclui quem estoura o mod_evasive).
- Informe o seu IP fixo em "IPs que o fail2ban nunca deve bloquear" para não se bloquear por engano.

Comandos úteis:
```bash
sudo fail2ban-client status                       # jails ativas
sudo fail2ban-client status plenario-aberto-http-erros     # IPs bloqueados nessa jail
sudo fail2ban-client set plenario-aberto-http-erros unbanip 203.0.113.7
```

**Recomendado adicionalmente** (não incluído no script):
```bash
sudo apt install -y unattended-upgrades           # atualizações automáticas de segurança
```
Endurecer o SSH (sem login de root nem por senha) também é recomendável, mas deve ser feito manualmente para não perder o acesso.

### Operação

```bash
sudo systemctl status plenario-aberto           # estado do serviço
sudo journalctl -u plenario-aberto -f           # logs da aplicação
sudo tail -f /var/log/apache2/plenario-aberto-error.log
sudo systemctl restart plenario-aberto          # após atualizar o código
sudo rm /opt/plenario-aberto/cache/*.zip        # força novo download dos CSVs
```

Atualizar o código: `rsync` novamente (passo 2), reinstalar dependências se `requirements.txt` mudou, e `sudo systemctl restart plenario-aberto`.

### Problemas comuns

| Sintoma | Causa provável |
|---|---|
| 502/503 no Apache | `plenario-aberto.service` parado: `systemctl status plenario-aberto` |
| Painel lento no primeiro acesso | Download e leitura do CSV do ano (normal, depois fica em cache) |
| Página de erro 502 do Flask | A API da Câmara está fora do ar; tente de novo |
| Certbot falha | DNS não aponta para o servidor, ou a porta 80 está bloqueada |
| Gráficos não aparecem | O navegador não alcança `cdnjs.cloudflare.com` |
