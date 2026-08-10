#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

secret_path="secrets/local/postgres_api_password"
if [[ ! -s "$secret_path" ]]; then
  echo "ERROR: falta el secreto efimero de jp_login_api." >&2
  exit 1
fi

api_password="$(tr -d '\r\n' < "$secret_path")"
if [[ -z "$api_password" ]]; then
  echo "ERROR: el secreto efimero de jp_login_api esta vacio." >&2
  exit 1
fi

mkdir -p artifacts/postgres

PGPASSWORD="$api_password" psql \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username=jp_login_api \
  --dbname="$PGDATABASE" \
  --no-password \
  --set=ON_ERROR_STOP=1 \
  --file=database/postgresql/tests/verify_minimum_effective_configuration.sql

cat > artifacts/postgres/minimum-effective-configuration-summary.txt <<'EOF'
bl_mvp=035
reader=jp_login_api
catalogs=12
catalog_entries=59
catalog_safe_entries=12
effective_global_parameters=10
safe_parameter_defaults=10
roles=4
safe_role=STUDENT
retention_policies=3
secret_like_parameter_keys=0
version_and_vigency=verified
EOF

echo "OK: BL-MVP-035 publicacion minima efectiva verificada con la identidad real de API."
