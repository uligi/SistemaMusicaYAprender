#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

mkdir -p database/postgresql/ef-model

psql \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname="$PGDATABASE" \
  --no-password \
  --set=ON_ERROR_STOP=1 \
  --no-align \
  --tuples-only \
  --file=database/postgresql/ef-model/query_cross_schema_foreign_keys.sql \
  > database/postgresql/ef-model/cross-schema-foreign-keys.json

node -e "
const fs=require('fs');
const p='database/postgresql/ef-model/cross-schema-foreign-keys.json';
const value=JSON.parse(fs.readFileSync(p,'utf8'));
if(value.backlogItem!=='BL-MVP-014') throw new Error('Manifest BL-MVP-014 invalido');
fs.writeFileSync(p, JSON.stringify(value,null,2)+'\n');
"

echo "OK: manifiesto de FK transversales generado."
