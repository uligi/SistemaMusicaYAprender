#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGDATABASE:?PGDATABASE is required}"

if [[ ! "$PGDATABASE" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]]; then
  echo "ERROR: PGDATABASE no cumple el formato seguro esperado." >&2
  exit 1
fi

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
WHERE schemaname IN (
  'identity','security','catalog','content','learning',
  'progress','editorial','configuration','ops'
);
" | tr -d '[:space:]')"

if [[ "$before_count" != "0" ]]; then
  echo "ERROR: la base de CI no esta vacia antes de InitialPhysicalSchema. Tablas: $before_count." >&2
  exit 1
fi

# El SQL físico hace SET LOCAL ROLE jp_owner antes de CREATE SCHEMA.
# El bootstrap crea el rol, pero CREATE es un privilegio a nivel de base.
psql \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname=postgres \
  --no-password \
  --set=ON_ERROR_STOP=1 \
  --command="GRANT CREATE ON DATABASE \"$PGDATABASE\" TO jp_owner;"

password_file="${RUNNER_TEMP:-/tmp}/musica-aprender-bl-mvp-011-password"
umask 077
printf '%s' "$PGPASSWORD" > "$password_file"

cleanup() {
  rm -f "$password_file"
}
trap cleanup EXIT

dotnet run \
  --project tools/DatabaseMigrator/MusicaAprender.DatabaseMigrator.csproj \
  --configuration Release \
  --no-build \
  --no-restore \
  -- \
  --host "$PGHOST" \
  --port "$PGPORT" \
  --database "$PGDATABASE" \
  --username "$PGUSER" \
  --password-file "$password_file"

psql \
  --host="$PGHOST" \
  --port="$PGPORT" \
  --username="$PGUSER" \
  --dbname="$PGDATABASE" \
  --no-password \
  --set=ON_ERROR_STOP=1 \
  --file=database/postgresql/tests/verify_initial_migration.sql

table_count="$("${psql_base[@]}" --command="
SELECT count(*)
FROM pg_catalog.pg_tables
WHERE schemaname IN (
  'identity','security','catalog','content','learning',
  'progress','editorial','configuration','ops'
);
" | tr -d '[:space:]')"

role_count="$("${psql_base[@]}" --command="SELECT count(*) FROM security.role;" | tr -d '[:space:]')"
permission_count="$("${psql_base[@]}" --command="SELECT count(*) FROM security.permission;" | tr -d '[:space:]')"
catalog_entry_count="$("${psql_base[@]}" --command="SELECT count(*) FROM configuration.catalog_entry;" | tr -d '[:space:]')"

{
  echo "bl_mvp=011"
  echo "postgres_server_version_num=$server_version_num"
  echo "initial_application_table_count=$before_count"
  echo "final_application_table_count=$table_count"
  echo "seed_security_role_count=$role_count"
  echo "seed_security_permission_count=$permission_count"
  echo "seed_catalog_entry_count=$catalog_entry_count"
  echo "migration_id=202608080001_InitialPhysicalSchema"
  sha256sum database/postgresql/master/MVP_PostgreSQL_18_Master.sql \
    | awk '{print "master_sql_sha256="$1}'
  sha256sum database/postgresql/migrations/sql/01_initial_schema.sql \
    | awk '{print "initial_schema_sha256="$1}'
  sha256sum database/postgresql/migrations/sql/02_seed_mvp.sql \
    | awk '{print "seed_sha256="$1}'
} > artifacts/postgres/initial-migration-summary.txt

echo "OK: BL-MVP-011 aplico la migracion EF Core embebida sobre una base PostgreSQL 18 vacia."
