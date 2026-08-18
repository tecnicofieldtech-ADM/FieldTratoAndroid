#!/usr/bin/env bash
# Instala a API FieldPec Online no servidor Linux (Node deps + .env + opcional systemd).
# Uso (na raiz do pacote extraído):
#   sudo bash deploy/linux/install-api.sh
#   sudo bash deploy/linux/install-api.sh --port 3001 --token 'MeuToken' \
#        --database-url 'postgres://fieldpec:Senha@127.0.0.1:5432/fieldpec_online'

set -euo pipefail

PORT=3001
DATABASE_URL="postgres://fieldpec:fieldpec@127.0.0.1:5432/fieldpec_online"
ADMIN_TOKEN="change-me-admin-token"
INSTALL_SYSTEMD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --database-url) DATABASE_URL="$2"; shift 2 ;;
    --token) ADMIN_TOKEN="$2"; shift 2 ;;
    --no-systemd) INSTALL_SYSTEMD=0; shift ;;
    *) echo "Arg desconhecido: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API_DIR="$ROOT/api"
ENV_FILE="$API_DIR/.env"
UNIT_SRC="$SCRIPT_DIR/fieldpec-online-api.service"
UNIT_DST="/etc/systemd/system/fieldpec-online-api.service"

if [[ ! -d "$API_DIR" ]]; then
  echo "Pasta api nao encontrada em $ROOT" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js/npm nao encontrados. Instale Node 18+." >&2
  exit 1
fi

echo "Node: $(node -v)  npm: $(npm -v)"
echo "Instalando em: $API_DIR"

cd "$API_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example "$ENV_FILE"
  else
    touch "$ENV_FILE"
  fi
fi

upsert_env() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

upsert_env PORT "$PORT"
upsert_env HOST "0.0.0.0"
upsert_env DATABASE_URL "$DATABASE_URL"
upsert_env ADMIN_TOKEN "$ADMIN_TOKEN"

npm install --omit=dev
npm run db:init || echo "AVISO: db:init falhou — confira DATABASE_URL."

mkdir -p "$API_DIR/logs"

if [[ "$INSTALL_SYSTEMD" -eq 1 ]]; then
  if [[ $EUID -ne 0 ]]; then
    echo "AVISO: rode com sudo para instalar o systemd. Pulando servico."
  elif [[ -f "$UNIT_SRC" ]]; then
    sed "s|__API_DIR__|$API_DIR|g" "$UNIT_SRC" > "$UNIT_DST"
    systemctl daemon-reload
    systemctl enable fieldpec-online-api
    systemctl restart fieldpec-online-api
    systemctl --no-pager status fieldpec-online-api || true
  fi
fi

echo
echo "Instalacao concluida."
echo "  .env    : $ENV_FILE"
echo "  start   : cd $API_DIR && npm start"
echo "  systemd : systemctl status fieldpec-online-api"
echo "  health  : curl http://127.0.0.1:${PORT}/GetTeste"
