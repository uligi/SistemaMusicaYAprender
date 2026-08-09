#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

mkdir -p artifacts/postgres

psql_base=(
  psql
  --host="$PGHOST"
  --port="$PGPORT"
  --username="$PGUSER"
  --dbname="$PGDATABASE"
  --no-password
  --set=ON_ERROR_STOP=1
)

cleanup_fixture() {
  "${psql_base[@]}" \
    --file=database/postgresql/tests/rls/cleanup_transaction_context_fixture.sql \
    >/dev/null 2>&1 || true
}

trap cleanup_fixture EXIT

echo "Preparando fixture aislado BL-MVP-013..."
"${psql_base[@]}" \
  --file=database/postgresql/tests/rls/prepare_transaction_context_fixture.sql

echo "Verificando contexto transaccional con jp_login_api..."
dotnet run \
  --project tools/DatabaseContextVerifier/MusicaAprender.DatabaseContextVerifier.csproj \
  --configuration Release \
  --no-build \
  --no-restore \
  -- \
  --host "$PGHOST" \
  --port "$PGPORT" \
  --database "$PGDATABASE" \
  --secret-directory secrets/local

cleanup_fixture
trap - EXIT

{
  echo "bl_mvp=013"
  echo "context_account=app.account_id"
  echo "context_role=app.role_code"
  echo "context_correlation=app.correlation_id"
  echo "transaction_local=true"
  echo "cross_account_read_denied=true"
  echo "cross_account_write_denied=true"
  echo "pool_max_size=1"
  echo "physical_connection_reuse_verified=true"
  echo "post_commit_context_empty=true"
  echo "post_rollback_context_empty=true"
} > artifacts/postgres/transaction-context-summary.txt

echo "OK: BL-MVP-013 contexto RLS, denegacion cruzada y limpieza de pool verificados en CI."
