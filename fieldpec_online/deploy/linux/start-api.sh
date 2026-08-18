#!/usr/bin/env bash
# Inicia a API em foreground (sem systemd).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT/api"
[[ -f .env ]] || { echo "Falta api/.env — rode install-api.sh"; exit 1; }
exec npm start
