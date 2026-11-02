#!/usr/bin/env bash
# Instalação completa do painel em Ubuntu: Apache + gunicorn + HTTPS (Let's Encrypt) na porta 443.
#
# Uso:    sudo "./deploy/install ubuntu server/install.sh"            (pergunta o que for necessário)
#         sudo DOMINIO=painel.exemplo.com.br EMAIL=voce@exemplo.com.br "./deploy/install ubuntu server/install.sh" -y
# Variáveis aceitas (ambiente): DOMINIO, EMAIL, INSTALL_DIR, PORTA_APP, STAGING (s/n), UFW (s/n),
#                              FAIL2BAN (s/n), EVASIVE (s/n), IGNOREIP (IPs que o fail2ban nunca bloqueia)
# Pode ser executado de novo para atualizar o código (é idempotente).
set -Eeuo pipefail

DEPLOY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # esta pasta (apache/, systemd/, fail2ban/)
ORIGEM="$(cd "$DEPLOY/../.." && pwd)"                       # raiz do projeto
NAO_INTERATIVO=n

uso() { sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }
log()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m[aviso]\033[0m %s\n' "$*" >&2; }
erro() { printf '\033[1;31m[erro]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'erro "Falhou na linha $LINENO. Corrija e rode o script de novo (ele é idempotente)."' ERR

for a in "$@"; do
  case "$a" in
    -y|--yes) NAO_INTERATIVO=s ;;
    -h|--help) uso ;;
    *) erro "Opção desconhecida: $a" ;;
  esac
done

# pergunta VAR "texto" "padrão" "regex de validação" "mensagem de erro"
pergunta() {
  local var=$1 texto=$2 padrao=${3:-} regex=${4:-.} msg=${5:-Valor inválido.} valor
  valor=${!var:-}
  while true; do
    if [[ -z $valor ]]; then
      if [[ $NAO_INTERATIVO == s ]]; then
        [[ -n $padrao ]] && valor=$padrao || erro "Variável $var é obrigatória no modo -y."
      else
        read -r -p "$texto${padrao:+ [$padrao]}: " valor
        valor=${valor:-$padrao}
      fi
    fi
    if [[ $valor =~ $regex ]]; then printf -v "$var" '%s' "$valor"; return; fi
    [[ $NAO_INTERATIVO == s ]] && erro "$var inválido: $valor ($msg)"
    aviso "$msg"; valor=""
  done
}

sim_nao() { # sim_nao VAR "texto" padrao(s|n)
  local var=$1 texto=$2 padrao=$3 r=${!var:-}
  if [[ -z $r ]]; then
    if [[ $NAO_INTERATIVO == s ]]; then r=$padrao
    else read -r -p "$texto [$padrao]: " r; r=${r:-$padrao}; fi
  fi
  case "${r,,}" in s|sim|y|yes) printf -v "$var" s ;; *) printf -v "$var" n ;; esac
}

# ---------------------------------------------------------------- verificações
[[ $EUID -eq 0 ]] || erro "Execute como root: sudo $0"
[[ -f $ORIGEM/wsgi.py && -d $ORIGEM/app ]] || erro "Não encontrei o projeto em $ORIGEM (wsgi.py/app)."
command -v apt-get >/dev/null || erro "Este script é para Ubuntu/Debian (apt)."
if ! grep -qi ubuntu /etc/os-release; then aviso "Sistema não é Ubuntu; os pacotes podem diferir."; fi

# Usuário fixo do serviço (gunicorn). Se não existir no servidor, é criado mais adiante.
USUARIO=plenario-aberto

# ---------------------------------------------------------------- variáveis
echo "Configuração da instalação (Enter aceita o valor entre colchetes)."
pergunta DOMINIO "Domínio do painel (o DNS já deve apontar para este servidor)" "" \
  '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$' "Informe um domínio válido, ex.: painel.exemplo.com.br"
DOMINIO=${DOMINIO,,}
pergunta EMAIL "E-mail para avisos do Let's Encrypt" "" '^[^@ ]+@[^@ ]+\.[^@ ]+$' "Informe um e-mail válido."
pergunta INSTALL_DIR "Diretório de instalação" "/opt/plenario-aberto" '^/[A-Za-z0-9._/-]+$' "Use um caminho absoluto sem espaços."
pergunta PORTA_APP "Porta local do gunicorn (só 127.0.0.1)" "8000" '^[0-9]{2,5}$' "Informe uma porta numérica."
sim_nao STAGING "Usar o ambiente de TESTE do Let's Encrypt (certificado não confiável, sem limite de tentativas)?" n
sim_nao UFW "Configurar o firewall UFW (libera OpenSSH, 80 e 443 e ativa)?" s
sim_nao FAIL2BAN "Instalar o fail2ban (bloqueia IPs com tentativas de SSH, robôs e varreduras)?" s
sim_nao EVASIVE "Instalar o mod_evasive (limita requisições por IP, contra abuso/DoS simples)?" s
if [[ $FAIL2BAN == s && -z ${IGNOREIP:-} && $NAO_INTERATIVO != s ]]; then
  read -r -p "IPs que o fail2ban NUNCA deve bloquear, ex.: o seu IP fixo (separados por espaço, opcional): " IGNOREIP
fi
IGNOREIP=${IGNOREIP:-}
[[ $IGNOREIP =~ ^[0-9a-fA-F:./\ ]*$ ]] || erro "IGNOREIP inválido: use apenas IPs/CIDRs separados por espaço."

ARQ_CONF="plenario-aberto-$DOMINIO"   # nome dos arquivos de site do Apache
echo
echo "  Domínio:     $DOMINIO"
echo "  E-mail:      $EMAIL"
echo "  Instalação:  $INSTALL_DIR (usuário $USUARIO, gunicorn em 127.0.0.1:$PORTA_APP)"
echo "  Let's Encrypt: $([[ $STAGING == s ]] && echo 'TESTE (staging)' || echo 'PRODUÇÃO')"
echo "  UFW:         $([[ $UFW == s ]] && echo sim || echo não)"
echo "  fail2ban:    $([[ $FAIL2BAN == s ]] && echo "sim${IGNOREIP:+ (ignora: $IGNOREIP)}" || echo não)"
echo "  mod_evasive: $([[ $EVASIVE == s ]] && echo sim || echo não)"
if [[ $NAO_INTERATIVO != s ]]; then
  read -r -p "Continuar? [s/N]: " ok; [[ ${ok,,} == s* ]] || erro "Cancelado."
fi

# DNS: o certbot só funciona se o domínio apontar para este servidor
IP_DNS=$(getent ahostsv4 "$DOMINIO" | awk '{print $1; exit}' || true)
IPS_LOCAIS=$(hostname -I 2>/dev/null || true)
if [[ -z $IP_DNS ]]; then
  aviso "O domínio $DOMINIO não resolve no DNS. O certbot vai falhar até o DNS apontar para este servidor."
  [[ $NAO_INTERATIVO == s ]] || { read -r -p "Continuar mesmo assim? [s/N]: " ok; [[ ${ok,,} == s* ]] || erro "Cancelado."; }
elif [[ " $IPS_LOCAIS " != *" $IP_DNS "* ]]; then
  aviso "$DOMINIO aponta para $IP_DNS, que não está entre os IPs desta máquina ($IPS_LOCAIS)."
  aviso "Se houver NAT/proxy (IP público diferente) isso é normal; senão o certbot vai falhar."
fi

# ---------------------------------------------------------------- pacotes
log "Instalando pacotes"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 python3 python3-venv python3-pip certbot rsync curl ufw ca-certificates

log "Habilitando módulos do Apache"
a2enmod ssl proxy proxy_http headers rewrite >/dev/null

# ---------------------------------------------------------------- usuário e código
log "Preparando o usuário do serviço ($USUARIO) e copiando o código para $INSTALL_DIR"
if id "$USUARIO" >/dev/null 2>&1; then
  echo "Usuário $USUARIO já existe; será reaproveitado."
  getent group "$USUARIO" >/dev/null || erro "O usuário $USUARIO existe, mas o grupo $USUARIO não. Crie o grupo ou ajuste o usuário."
else
  useradd --system --user-group --home-dir "$INSTALL_DIR" --no-create-home --shell /usr/sbin/nologin "$USUARIO"
  echo "Usuário $USUARIO criado (sistema, sem shell de login)."
fi
mkdir -p "$INSTALL_DIR"
if [[ "$(realpath "$ORIGEM")" != "$(realpath "$INSTALL_DIR")" ]]; then
  rsync -a --delete \
    --exclude '.venv' --exclude '.git' --exclude '__pycache__' --exclude '.claude' \
    --include 'cache/index.html' --exclude 'cache/*' \
    "$ORIGEM"/ "$INSTALL_DIR"/
else
  aviso "Origem e destino são o mesmo diretório; nada a copiar."
fi
mkdir -p "$INSTALL_DIR/cache" "$INSTALL_DIR/public"
[[ -f $INSTALL_DIR/public/index.html ]] || : > "$INSTALL_DIR/public/index.html"

log "Criando o ambiente virtual e instalando dependências"
[[ -x $INSTALL_DIR/.venv/bin/python ]] || python3 -m venv "$INSTALL_DIR/.venv"
"$INSTALL_DIR/.venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/.venv/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"

log "Ajustando permissões (código somente leitura; só cache/ gravável)"
chown -R root:"$USUARIO" "$INSTALL_DIR"
chmod -R o-rwx "$INSTALL_DIR"
chmod -R g-w "$INSTALL_DIR"
chown -R "$USUARIO":"$USUARIO" "$INSTALL_DIR/cache"
chmod 750 "$INSTALL_DIR/cache"
# o Apache (www-data) só precisa atravessar o diretório e ler public/
chmod 755 "$INSTALL_DIR" "$INSTALL_DIR/public"
chmod 644 "$INSTALL_DIR/public/index.html"

# ---------------------------------------------------------------- gunicorn (systemd)
log "Configurando o serviço systemd"
sed -e "s#/opt/plenario-aberto#$INSTALL_DIR#g" \
    -e "s#^User=.*#User=$USUARIO#" -e "s#^Group=.*#Group=$USUARIO#" \
    -e "s#127\.0\.0\.1:8000#127.0.0.1:$PORTA_APP#g" \
    "$DEPLOY/systemd/plenario-aberto.service" > /etc/systemd/system/plenario-aberto.service
systemctl daemon-reload
systemctl enable plenario-aberto >/dev/null
systemctl restart plenario-aberto

for _ in $(seq 1 20); do
  curl -fsS -o /dev/null "http://127.0.0.1:$PORTA_APP/" 2>/dev/null && break
  sleep 1
done
curl -fsS -o /dev/null "http://127.0.0.1:$PORTA_APP/" \
  || { journalctl -u plenario-aberto -n 30 --no-pager; erro "O gunicorn não respondeu em 127.0.0.1:$PORTA_APP."; }
echo "gunicorn respondendo."

# ---------------------------------------------------------------- Apache (HTTP) + certificado
renderiza_apache() { # renderiza_apache arquivo_origem arquivo_destino
  sed -e "s#painel\.exemplo\.com\.br#$DOMINIO#g" \
      -e "s#/opt/plenario-aberto#$INSTALL_DIR#g" \
      -e "s#127\.0\.0\.1:8000#127.0.0.1:$PORTA_APP#g" \
      -e "s#plenario-aberto-http-#$ARQ_CONF-http-#g" -e "s#plenario-aberto-error\.log#$ARQ_CONF-error.log#" \
      -e "s#plenario-aberto-access\.log#$ARQ_CONF-access.log#" "$1" > "$2"
}

log "Configurando o Apache (porta 80) para o desafio do Let's Encrypt"
cp "$DEPLOY/apache/seguranca.conf" /etc/apache2/conf-available/seguranca.conf
a2enconf seguranca >/dev/null
a2dissite 000-default >/dev/null 2>&1 || true
renderiza_apache "$DEPLOY/apache/plenario-aberto-http.conf" "/etc/apache2/sites-available/$ARQ_CONF-http.conf"
a2ensite "$ARQ_CONF-http" >/dev/null
# se o vhost 443 de uma execução anterior existir mas o certificado ainda não, ele impediria o reload
[[ -f /etc/letsencrypt/live/$DOMINIO/fullchain.pem ]] || a2dissite "$ARQ_CONF-ssl" >/dev/null 2>&1 || true
apache2ctl configtest
systemctl enable apache2 >/dev/null
systemctl reload apache2 2>/dev/null || systemctl restart apache2

if [[ $UFW == s ]]; then
  log "Configurando o firewall (UFW)"
  ufw allow OpenSSH >/dev/null   # antes de ativar, para não perder o acesso SSH
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null
  ufw status | sed 's/^/   /'
fi

log "Obtendo o certificado Let's Encrypt para $DOMINIO"
CERTBOT=(certbot certonly --webroot -w "$INSTALL_DIR/public" -d "$DOMINIO"
         -m "$EMAIL" --agree-tos --no-eff-email --non-interactive --keep-until-expiring)
[[ $STAGING == s ]] && CERTBOT+=(--staging)
if ! "${CERTBOT[@]}"; then
  erro "O certbot falhou. Confira: DNS de $DOMINIO apontando para este servidor, portas 80/443 abertas (inclusive no firewall do provedor) e os logs em /var/log/letsencrypt/. O site HTTP segue configurado; rode o script de novo depois de corrigir."
fi

# ---------------------------------------------------------------- Apache (HTTPS)
log "Ativando o site HTTPS (porta 443)"
renderiza_apache "$DEPLOY/apache/plenario-aberto-ssl.conf" "/etc/apache2/sites-available/$ARQ_CONF-ssl.conf"
a2ensite "$ARQ_CONF-ssl" >/dev/null
apache2ctl configtest
systemctl reload apache2

# renovação automática: o timer do certbot já existe; o hook recarrega o Apache após renovar
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nsystemctl reload apache2\n' > /etc/letsencrypt/renewal-hooks/deploy/apache-reload.sh
chmod +x /etc/letsencrypt/renewal-hooks/deploy/apache-reload.sh
certbot renew --dry-run --quiet >/dev/null 2>&1 \
  && echo "Renovação automática testada com sucesso." \
  || aviso "O teste de renovação (certbot renew --dry-run) falhou; verifique depois."

# ---------------------------------------------------------------- proteções extras
if [[ $EVASIVE == s ]]; then
  log "Instalando e configurando o mod_evasive (limite de requisições por IP)"
  if apt-get install -y libapache2-mod-evasive; then
    mkdir -p /var/log/mod_evasive && chown www-data:www-data /var/log/mod_evasive && chmod 750 /var/log/mod_evasive
    cp "$DEPLOY/apache/evasive.conf" /etc/apache2/mods-available/evasive.conf
    a2enmod evasive >/dev/null
    apache2ctl configtest
    systemctl restart apache2
    echo "mod_evasive ativo (10 pedidos/2s na mesma página, 60/2s no site; bloqueio de 120s)."
  else
    aviso "Não foi possível instalar libapache2-mod-evasive (repositório 'universe' habilitado?). Etapa ignorada."
  fi
fi

if [[ $FAIL2BAN == s ]]; then
  log "Instalando e configurando o fail2ban"
  if apt-get install -y fail2ban; then
    mkdir -p /etc/fail2ban/jail.d /etc/fail2ban/filter.d
    cp "$DEPLOY/fail2ban/filter.d/plenario-aberto-http-erros.conf" /etc/fail2ban/filter.d/plenario-aberto-http-erros.conf
    sed "s#__IGNOREIP__#$IGNOREIP#" "$DEPLOY/fail2ban/jail.plenario-aberto.local" > /etc/fail2ban/jail.d/plenario-aberto.local
    if fail2ban-client -t >/dev/null 2>&1; then
      systemctl enable fail2ban >/dev/null
      systemctl restart fail2ban
      sleep 2
      fail2ban-client status 2>/dev/null | sed 's/^/   /' || true
    else
      aviso "A configuração do fail2ban é inválida; veja: fail2ban-client -t"
    fi
  else
    aviso "Não foi possível instalar o fail2ban. Etapa ignorada."
  fi
fi

# ---------------------------------------------------------------- verificação final
log "Verificando"
CURL_OPTS=(-sS -o /dev/null -w '%{http_code}' --max-time 60 --resolve "$DOMINIO:443:127.0.0.1")
[[ $STAGING == s ]] && CURL_OPTS+=(-k)
COD=$(curl "${CURL_OPTS[@]}" "https://$DOMINIO/" || true)
COD80=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 --resolve "$DOMINIO:80:127.0.0.1" "http://$DOMINIO/" || true)
echo "  https://$DOMINIO/ -> HTTP $COD (esperado 200)"
echo "  http://$DOMINIO/  -> HTTP $COD80 (esperado 301)"
[[ $COD == 200 ]] || aviso "A página não respondeu 200. Veja: journalctl -u plenario-aberto -n 50 e /var/log/apache2/$ARQ_CONF-error.log"

cat <<FIM

Instalação concluída.
  Site:        https://$DOMINIO/
  Serviço:     systemctl status plenario-aberto     |  journalctl -u plenario-aberto -f
  Logs Apache: /var/log/apache2/$ARQ_CONF-error.log
  Atualizar:   atualize o código e rode de novo: sudo $0
  Cache:       $INSTALL_DIR/cache (o 1º acesso a cada ano baixa 4-7 MB)
$([[ $FAIL2BAN == s ]] && echo "  fail2ban:    fail2ban-client status plenario-aberto-http-erros   |  desbloquear: fail2ban-client set <jail> unbanip <IP>")
$([[ $STAGING == s ]] && echo "  ATENÇÃO: certificado de TESTE. Para o definitivo, rode de novo com STAGING=n e apague antes: certbot delete --cert-name $DOMINIO")
FIM
