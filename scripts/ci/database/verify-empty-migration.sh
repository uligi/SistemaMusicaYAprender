#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGDATABASE:?PGDATABASE is required}"

mkdir -p artifacts/postgres

psql_base=(
  psql
  --host="$PGHOST"
  --port="$PGPORT"
  --username="$PGUSER"
  --dbname="$PGDATABASE"
  --no-password
  --tuples-only
  --no-align
  --set=ON_ERROR_STOP=1
)

server_version_num="$("${psql_base[@]}" --command="SHOW server_version_num;" | tr -d '[:space:]')"
server_major=$((server_version_num / 10000))

if [[ "$server_major" -ne 18 ]]; then
  echo "ERROR: CI requiere PostgreSQL 18. Encontrado server_version_num=$server_version_num." >&2
  exit 1
fi

before_count="$("${psql_base[@]}" --command="
SELECT count(*)
FROM pg_catalog.pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema');
" | tr -d '[:space:]')"

if [[ "$before_count" != "0" ]]; then
  echo "ERROR: la base de CI no esta vacia antes de la prueba. Tablas encontradas: $before_count." >&2
  exit 1
fi

# BL-MVP-004 only verifies that a controlled migration can execute against an empty
# PostgreSQL 18 database without leaving partial state. BL-MVP-010/011 will replace
# this probe with the real bootstrap and embedded initial migration.
psql \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname="$PGDATABASE" \
  --no-password \
  --set=ON_ERROR_STOP=1 <<'SQL'
BEGIN;

CREATE SCHEMA ci_migration_probe;

CREATE TABLE ci_migration_probe.migration_probe (
    probe_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    marker text NOT NULL CHECK (length(marker) > 0)
);

INSERT INTO ci_migration_probe.migration_probe (marker)
VALUES ('BL-MVP-004');

DO $block$
BEGIN
    IF (SELECT count(*) FROM ci_migration_probe.migration_probe) <> 1 THEN
        RAISE EXCEPTION 'La prueba de migracion vacia no produjo el estado esperado.';
    END IF;
END;
$block$;

ROLLBACK;
SQL

after_count="$("${psql_base[@]}" --command="
SELECT count(*)
FROM pg_catalog.pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema');
" | tr -d '[:space:]')"

if [[ "$after_count" != "0" ]]; then
  echo "ERROR: la prueba dejo estado parcial. Tablas restantes: $after_count." >&2
  exit 1
fi

master_sql=""
for candidate in \
  "database/postgresql/master/MVP_PostgreSQL_18_Master.sql" \
  "sistema de musica/MVP_PostgreSQL_18_Master.sql"
do
  if [[ -f "$candidate" ]]; then
    master_sql="$candidate"
    break
  fi
done

{
  echo "bl_mvp=004"
  echo "postgres_server_version_num=$server_version_num"
  echo "initial_user_table_count=$before_count"
  echo "final_user_table_count=$after_count"
  echo "probe_transaction=rollback_clean"
  if [[ -n "$master_sql" ]]; then
    echo "master_sql_path=$master_sql"
    sha256sum "$master_sql" | awk '{print "master_sql_sha256="$1}'
  else
    echo "master_sql_path=not-found-yet"
  fi
} > artifacts/postgres/empty-migration-summary.txt

echo "OK: PostgreSQL 18 acepto la migracion de prueba sobre una base vacia y no quedo estado parcial."
