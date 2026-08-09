#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

secret_dir="${DATABASE_SECRET_DIRECTORY:-secrets/local}"

psql \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname="$PGDATABASE" \
  --no-password \
  --set=ON_ERROR_STOP=1 \
  --file=database/postgresql/bootstrap/roles/01_login_identities.sql

declare -A identity_secrets=(
  [jp_login_migrator]="postgres_migrator_password"
  [jp_login_api]="postgres_api_password"
  [jp_login_backoffice]="postgres_backoffice_password"
  [jp_login_worker]="postgres_worker_password"
  [jp_login_readonly]="postgres_readonly_password"
)

{
  echo "SET password_encryption = 'scram-sha-256';"

  for role_name in \
    jp_login_migrator \
    jp_login_api \
    jp_login_backoffice \
    jp_login_worker \
    jp_login_readonly; do

    secret_name="${identity_secrets[$role_name]}"
    secret_path="$secret_dir/$secret_name"

    if [[ ! -f "$secret_path" ]]; then
      echo "ERROR: falta $secret_path." >&2
      exit 1
    fi

    password="$(tr -d '\r\n' < "$secret_path")"

    if [[ ! "$password" =~ ^[A-Fa-f0-9]{48,256}$ ]]; then
      echo "ERROR: formato invalido para $secret_name." >&2
      exit 1
    fi

    printf "ALTER ROLE \"%s\" WITH PASSWORD '%s';\n" "$role_name" "$password"
  done
} | psql \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname=postgres \
  --no-password \
  --set=ON_ERROR_STOP=1 >/dev/null

echo "OK: identidades LOGIN y credenciales separadas aplicadas."
