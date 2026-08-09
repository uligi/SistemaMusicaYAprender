#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

echo "Probando idempotencia del bootstrap en CI..."
bash scripts/database/apply-bootstrap.sh

psql \
  -v ON_ERROR_STOP=1 \
  -f database/postgresql/tests/verify_bootstrap.sql

echo "OK: BL-MVP-010 verificado en PostgreSQL."
