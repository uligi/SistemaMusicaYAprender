#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

psql \
  -v ON_ERROR_STOP=1 \
  -f database/postgresql/bootstrap/roles/00_bootstrap_roles_extensions.sql

echo "OK: bootstrap PostgreSQL aplicado."
