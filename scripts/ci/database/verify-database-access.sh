#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

mkdir -p artifacts/postgres

bash scripts/database/prepare-database-access.sh

psql \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname="$PGDATABASE" \
  --no-password \
  --set=ON_ERROR_STOP=1 \
  --file=database/postgresql/tests/verify_login_identities.sql

dotnet run \
  --project tools/DatabaseAccessVerifier/MusicaAprender.DatabaseAccessVerifier.csproj \
  --configuration Release \
  --no-build \
  --no-restore \
  -- \
  --host "$PGHOST" \
  --port "$PGPORT" \
  --database "$PGDATABASE" \
  --secret-directory secrets/local

{
  echo "bl_mvp=012"
  echo "database=$PGDATABASE"
  echo "login_identities=5"
  echo "functional_nologin_roles=6"
  echo "api_login=jp_login_api"
  echo "api_role=jp_app"
  echo "worker_login=jp_login_worker"
  echo "worker_role=jp_worker"
  echo "migrator_login=jp_login_migrator"
  echo "migrator_role=jp_migrator"
  echo "readonly_login=jp_login_readonly"
  echo "readonly_role=jp_readonly"
  echo "api_owner_membership=false"
  echo "api_migrator_membership=false"
  echo "runtime_superuser=false"
  echo "runtime_bypassrls=false"
} > artifacts/postgres/database-identities-summary.txt

echo "OK: BL-MVP-012 identidades y minimo privilegio verificados en CI."
