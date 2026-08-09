#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

bash scripts/database/prepare-database-access.sh

mkdir -p artifacts/postgres

dotnet run \
  --project tools/DatabaseModelVerifier/MusicaAprender.DatabaseModelVerifier.csproj \
  --configuration Release \
  --no-build \
  --no-restore \
  -- \
  --host "$PGHOST" \
  --port "$PGPORT" \
  --database "$PGDATABASE" \
  --secret-directory secrets/local \
  --repository-root "$ROOT" \
  --summary artifacts/postgres/ef-model-summary.txt

echo "OK: BL-MVP-014 modelos EF Core verificados en CI."
