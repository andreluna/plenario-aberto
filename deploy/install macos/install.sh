#!/usr/bin/env bash
# Instalação simples do painel em um MacBook (macOS): cria o .venv, instala as dependências e inicia o painel.
#
# Uso:    ./deploy/install\ macos/install.sh            (instala e pergunta se deve iniciar)
#         ./deploy/install\ macos/install.sh --run      (instala e já inicia, sem perguntar)
#         ./deploy/install\ macos/install.sh --no-run   (só instala)
# Pode ser executado de novo (é idempotente). Não precisa de sudo.
set -Eeuo pipefail

ORIGEM="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PY_MIN_MINOR=10   # Python 3.10+
INICIAR=""

log()   { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m[aviso]\033[0m %s\n' "$*" >&2; }
erro()  { printf '\033[1;31m[erro]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'erro "Falhou na linha $LINENO. Corrija e rode o script de novo (ele é idempotente)."' ERR

for a in "$@"; do
  case "$a" in
    --run) INICIAR=s ;;
    --no-run) INICIAR=n ;;
    -h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) erro "Opção desconhecida: $a" ;;
  esac
done

[[ $(uname -s) == Darwin ]] || erro "Este script é para macOS. No Ubuntu use 'install ubuntu server'; no Windows, 'install windows'."
[[ $EUID -ne 0 ]] || erro "Não execute com sudo; o ambiente virtual deve pertencer ao seu usuário."
[[ -f $ORIGEM/wsgi.py && -f $ORIGEM/requirements.txt ]] || erro "Não encontrei o projeto em $ORIGEM (wsgi.py/requirements.txt)."

# Retorna o caminho de um python3 >= 3.10, se houver
acha_python() {
  local c v
  for c in python3.13 python3.12 python3.11 python3.10 python3 \
           /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    command -v "$c" >/dev/null 2>&1 || continue
    c=$(command -v "$c")
    v=$("$c" -c 'import sys; print(sys.version_info[0]*100+sys.version_info[1])' 2>/dev/null || echo 0)
    if (( v >= 300 + PY_MIN_MINOR )); then echo "$c"; return 0; fi
  done
  return 1
}

# ---------------------------------------------------------------- Python
log "Verificando o Python (3.$PY_MIN_MINOR ou mais novo)"
if PYTHON=$(acha_python); then
  echo "Encontrado: $PYTHON ($("$PYTHON" --version))"
else
  aviso "Python 3.$PY_MIN_MINOR+ não encontrado."
  if ! command -v brew >/dev/null 2>&1 && [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  if command -v brew >/dev/null 2>&1; then
    log "Instalando o Python com o Homebrew"
    brew install python
    PYTHON=$(acha_python) || erro "O Python foi instalado, mas não foi localizado. Abra um novo Terminal e rode de novo."
  else
    erro "Instale o Python 3 e rode de novo: https://www.python.org/downloads/macos/  (ou instale o Homebrew em https://brew.sh e rode este script outra vez; ele instalará o Python)."
  fi
fi

# ---------------------------------------------------------------- venv + dependências
cd "$ORIGEM"
# .venv de outro sistema (ex.: copiado do Windows/Linux) não funciona aqui
if [[ -d .venv && ! -x .venv/bin/python ]]; then
  aviso "A pasta .venv existente não é deste sistema; será recriada."
  rm -rf .venv
fi
log "Criando o ambiente virtual (.venv)"
[[ -x .venv/bin/python ]] || "$PYTHON" -m venv .venv
log "Instalando as dependências (requirements.txt)"
.venv/bin/python -m pip install --quiet --upgrade pip
.venv/bin/python -m pip install --quiet -r requirements.txt
mkdir -p cache

# ---------------------------------------------------------------- iniciar
cat <<FIM

Instalação concluída.
  Para iniciar depois:
      cd "$ORIGEM"
      source .venv/bin/activate
      flask --app wsgi run --debug
  Abra: http://127.0.0.1:5000   (parar: Ctrl+C)
  Cache: $ORIGEM/cache (o 1º acesso a cada ano baixa 4-7 MB)
FIM

if [[ -z $INICIAR ]]; then
  read -r -p "Iniciar o painel agora? [S/n]: " r
  case "${r:-s}" in [nN]*) INICIAR=n ;; *) INICIAR=s ;; esac
fi
if [[ $INICIAR == s ]]; then
  log "Iniciando em http://127.0.0.1:5000 (Ctrl+C para parar)"
  trap - ERR
  # abre o navegador assim que o servidor responder
  ( for _ in $(seq 1 30); do curl -fsS -o /dev/null http://127.0.0.1:5000/ 2>/dev/null && { open http://127.0.0.1:5000; break; }; sleep 1; done ) &
  exec .venv/bin/flask --app wsgi run
fi
