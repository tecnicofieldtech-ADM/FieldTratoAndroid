#!/usr/bin/env bash
# Cria role + database FieldPec Online e aplica schema.sql
# Uso:
#   export PGPASSWORD='senha_do_postgres'
#   ./create-database.sh
#
# Opcional:
#   PGHOST=127.0.0.1 PGPORT=5432 PGSUPERUSER=postgres \
#   DB_NAME=fieldpec_online DB_USER=fieldpec DB_PASSWORD=fieldpec \
#   ./create-database.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SQL_DIR="$ROOT_DIR/sql"
CREATE_SQL="$SQL_DIR/create_database.sql"
SCHEMA_SQL="$SQL_DIR/schema.sql"

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGSUPERUSER="${PGSUPERUSER:-postgres}"
DB_NAME="${DB_NAME:-fieldpec_online}"
DB_USER="${DB_USER:-fieldpec}"
DB_PASSWORD="${DB_PASSWORD:-fieldpec}"

if [[ ! -f "$CREATE_SQL" ]]; then
  echo "Arquivo nao encontrado: $CREATE_SQL" >&2
  exit 1
fi
if [[ ! -f "$SCHEMA_SQL" ]]; then
  echo "Arquivo nao encontrado: $SCHEMA_SQL" >&2
  exit 1
fi
if ! command -v psql >/dev/null 2>&1; then
  echo "psql nao encontrado no PATH." >&2
  exit 1
fi

TMP_SQL="$(mktemp)"
cleanup() { rm -f "$TMP_SQL"; }
trap cleanup EXIT

# Substitui defaults se o operador passou outros nomes/senha
sed \
  -e "s/fieldpec_online/${DB_NAME}/g" \
  -e "s/PASSWORD 'fieldpec'/PASSWORD '$(printf '%s' "$DB_PASSWORD" | sed "s/'/''/g")'/g" \
  -e "s/ROLE fieldpec/ROLE ${DB_USER}/g" \
  -e "s/rolname = 'fieldpec'/rolname = '${DB_USER}'/g" \
  -e "s/CREATE ROLE fieldpec/CREATE ROLE ${DB_USER}/g" \
  -e "s/ALTER ROLE fieldpec/ALTER ROLE ${DB_USER}/g" \
  -e "s/OWNER fieldpec/OWNER ${DB_USER}/g" \
  -e "s/TO fieldpec/TO ${DB_USER}/g" \
  -e "s/role fieldpec/role ${DB_USER}/g" \
  "$CREATE_SQL" > "$TMP_SQL"

echo "[1/2] Criando role e database em ${PGHOST}:${PGPORT}..."
psql -h "$PGHOST" -p "$PGPORT" -U "$PGSUPERUSER" -d postgres -v ON_ERROR_STOP=1 -f "$TMP_SQL"

echo "[2/2] Aplicando schema em ${DB_NAME}..."
PGPASSWORD="$DB_PASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SCHEMA_SQL"

echo
echo "Concluido."
echo "DATABASE_URL=postgres://${DB_USER}:****@${PGHOST}:${PGPORT}/${DB_NAME}"
echo "Teste: PGPASSWORD=... psql -h $PGHOST -p $PGPORT -U $DB_USER -d $DB_NAME -c '\\dt'"
