#!/usr/bin/env bash
set -euo pipefail

check_hash() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"

  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: hash inesperado para $file" >&2
    echo "esperado=$expected" >&2
    echo "actual=$actual" >&2
    exit 1
  fi
}

check_hash database/postgresql/master/MVP_PostgreSQL_18_Master.sql da46cc9637c5b564f600f05b1c3dc4f16b6fc9ce161bf1f2943c2f9eb4929efa
check_hash database/postgresql/migrations/sql/01_initial_schema.sql bbd1e1500bdae63fee91028b37f9d23a2880cde1325d346e8f7a390d3c8f4ab8
check_hash database/postgresql/migrations/sql/02_seed_mvp.sql d031be0126447ac52474e5f86694c4c21e909514f981f679fa44d13fbcc59193

echo "OK: SQL fisico autoritativo BL-MVP-011 conserva los hashes aprobados."
