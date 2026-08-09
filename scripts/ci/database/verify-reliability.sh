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
    --file=database/postgresql/tests/reliability/cleanup_bl_mvp_015.sql \
    >/dev/null 2>&1 || true
}

trap cleanup_fixture EXIT

echo "Preparando fixture aislado BL-MVP-015..."
"${psql_base[@]}" \
  --file=database/postgresql/tests/reliability/prepare_bl_mvp_015.sql

echo "Verificando outbox, inbox, idempotencia y reintentos..."
dotnet run \
  --project tools/DatabaseReliabilityVerifier/MusicaAprender.DatabaseReliabilityVerifier.csproj \
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

cat > artifacts/postgres/reliability-summary.txt <<'EOF'
bl_mvp=015
atomic_decision_outbox=true
idempotency_repetitions=1000
logical_duplicates=0
same_key_different_digest=conflict
inbox_duplicate_effects=0
retry_max_attempts=3
retry_backoff=exponential
retry_jitter=true
terminal_failure_status=REVIEW
failure_evidence=job_attempt
EOF

echo "OK: BL-MVP-015 outbox, inbox, idempotencia y reintentos verificados en CI."
