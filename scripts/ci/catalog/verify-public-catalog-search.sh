#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL042_API_URL:-https://localhost:5457}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
worker_log="$work_dir/worker.log"
api_pid=""
worker_pid=""

publisher_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
artist_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
alias_kana_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
alias_romaji_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_title_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_a="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_b="$(node -e "console.log(require('node:crypto').randomUUID())")"
source_a="$(node -e "console.log(require('node:crypto').randomUUID())")"
source_b="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_a="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_b="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_a="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_b="$(node -e "console.log(require('node:crypto').randomUUID())")"
availability_a="$(node -e "console.log(require('node:crypto').randomUUID())")"
availability_b="$(node -e "console.log(require('node:crypto').randomUUID())")"

checksum="$(openssl rand -hex 32)"
package_checksum="$(openssl rand -hex 32)"
email_hash="$(openssl rand -hex 32)"
email_cipher="$(openssl rand -hex 24)"

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

if [[ "${BL042_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(
    docker compose exec -T postgres
    psql
    --username="$PGUSER"
    --dbname="$PGDATABASE"
    --no-password
    --set=ON_ERROR_STOP=1
    --tuples-only
    --no-align
  )
else
  psql_base=(
    psql
    --host="$PGHOST"
    --port="$PGPORT"
    --username="$PGUSER"
    --dbname="$PGDATABASE"
    --no-password
    --set=ON_ERROR_STOP=1
    --tuples-only
    --no-align
  )
fi

fail_check() {
  echo "ERROR: BL-MVP-042: $1" >&2
  if [[ -s "$worker_log" ]]; then
    echo "--- worker ---" >&2
    tail -n 120 "$worker_log" >&2 || true
  fi
  if [[ -s "$api_log" ]]; then
    echo "--- api ---" >&2
    tail -n 120 "$api_log" >&2 || true
  fi
  exit 1
}

assert_equal() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail_check "$name esperaba '$expected' y obtuvo '$actual'."
  fi
}

psql_scalar() {
  "${psql_base[@]}" --command="$1" | tr -d '[:space:]'
}

curl_request() {
  curl "${curl_tls_options[@]}" --silent --show-error "$@"
}

stop_worker() {
  if [[ -n "${worker_pid:-}" ]]; then
    kill "$worker_pid" >/dev/null 2>&1 || true
    wait "$worker_pid" >/dev/null 2>&1 || true
    worker_pid=""
  fi
}

stop_api() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" >/dev/null 2>&1 || true
    wait "$api_pid" >/dev/null 2>&1 || true
    api_pid=""
  fi
}

cleanup_rows() {
  stop_worker
  stop_api

  "${psql_base[@]}" >/dev/null <<SQL || true
BEGIN;
SELECT set_config('app.maintenance_mode', 'on', true);
DELETE FROM catalog.song_search_document
WHERE recording_id IN ('$recording_a'::uuid, '$recording_b'::uuid);
DELETE FROM editorial.published_package_projection
WHERE publication_id IN ('$publication_a'::uuid, '$publication_b'::uuid);
DELETE FROM editorial.publication_availability
WHERE availability_id IN ('$availability_a'::uuid, '$availability_b'::uuid);
DELETE FROM editorial.publication
WHERE publication_id IN ('$publication_a'::uuid, '$publication_b'::uuid);
DELETE FROM editorial.editorial_package
WHERE package_id IN ('$package_a'::uuid, '$package_b'::uuid);
DELETE FROM catalog.recording_source
WHERE source_id IN ('$source_a'::uuid, '$source_b'::uuid);
DELETE FROM catalog.recording
WHERE recording_id IN ('$recording_a'::uuid, '$recording_b'::uuid);
DELETE FROM catalog.work_title
WHERE work_title_id = '$work_title_id'::uuid;
DELETE FROM catalog.artist_alias
WHERE alias_id IN ('$alias_kana_id'::uuid, '$alias_romaji_id'::uuid);
DELETE FROM catalog.work_artist
WHERE work_id = '$work_id'::uuid AND artist_id = '$artist_id'::uuid;
DELETE FROM catalog.musical_work WHERE work_id = '$work_id'::uuid;
DELETE FROM catalog.artist WHERE artist_id = '$artist_id'::uuid;
DELETE FROM security.account WHERE account_id = '$publisher_id'::uuid;
COMMIT;
SQL
}

cleanup() {
  cleanup_rows
  rm -rf "$work_dir"
}
trap cleanup EXIT

cleanup_rows

if [[ "${BL042_SKIP_ACCESS_PREP:-false}" != "true" ]]; then
  bash scripts/database/prepare-database-access.sh >/dev/null
fi

docker compose up --detach object-store smtp-sink otel-collector >/dev/null
for attempt in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:9000/minio/health/ready >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    fail_check "Object store no disponible."
  fi
  sleep 1
done

"${psql_base[@]}" >/dev/null <<SQL
BEGIN;
INSERT INTO security.account (
    account_id,
    email_lookup_hash,
    email_cipher,
    status_code,
    verified_at,
    created_at,
    version
)
VALUES (
    '$publisher_id'::uuid,
    decode('$email_hash', 'hex'),
    decode('$email_cipher', 'hex'),
    'ACTIVE',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
);

INSERT INTO catalog.artist (
    artist_id,
    canonical_name,
    sort_name,
    artist_type,
    status_code,
    version
)
VALUES (
    '$artist_id'::uuid,
    'サカナクション',
    'Sakanaction',
    'GROUP',
    'ACTIVE',
    1
);

INSERT INTO catalog.artist_alias (
    alias_id,
    artist_id,
    alias_text,
    normalized_text,
    language_tag,
    script_code,
    preferred
)
VALUES
(
    '$alias_kana_id'::uuid,
    '$artist_id'::uuid,
    'かいじゅう',
    'かいじゅう',
    'ja',
    'HIRA',
    false
),
(
    '$alias_romaji_id'::uuid,
    '$artist_id'::uuid,
    'kaijuu',
    'kaijuu',
    'ja-Latn',
    'LATN',
    false
);

INSERT INTO catalog.musical_work (
    work_id,
    canonical_title,
    language_tag,
    release_date,
    status_code,
    version
)
VALUES (
    '$work_id'::uuid,
    '怪獣',
    'ja',
    NULL,
    'DRAFT',
    1
);

INSERT INTO catalog.work_title (
    work_title_id,
    work_id,
    title_text,
    normalized_text,
    language_tag,
    title_type,
    preferred
)
VALUES (
    '$work_title_id'::uuid,
    '$work_id'::uuid,
    'Kaiju',
    'kaiju',
    'ja-Latn',
    'ROMANIZED',
    false
);

INSERT INTO catalog.work_artist (
    work_id,
    artist_id,
    role_code,
    display_order
)
VALUES (
    '$work_id'::uuid,
    '$artist_id'::uuid,
    'PRIMARY',
    0
);

INSERT INTO catalog.recording (
    recording_id,
    work_id,
    recording_title,
    duration_ms,
    release_date,
    status_code,
    version
)
VALUES
(
    '$recording_a'::uuid,
    '$work_id'::uuid,
    'Album version',
    241000,
    NULL,
    'DRAFT',
    1
),
(
    '$recording_b'::uuid,
    '$work_id'::uuid,
    'Live version',
    245000,
    NULL,
    'DRAFT',
    1
);

INSERT INTO catalog.recording_source (
    source_id,
    recording_id,
    provider_code,
    external_ref,
    duration_ms,
    offset_ms,
    status_code,
    version
)
VALUES
(
    '$source_a'::uuid,
    '$recording_a'::uuid,
    'YOUTUBE',
    'BL042A00001',
    241000,
    0,
    'ACTIVE',
    1
),
(
    '$source_b'::uuid,
    '$recording_b'::uuid,
    'YOUTUBE',
    'BL042B00002',
    245000,
    0,
    'ACTIVE',
    1
);

INSERT INTO editorial.editorial_package (
    package_id,
    recording_id,
    package_no,
    status_code,
    created_by,
    created_at,
    frozen_at,
    checksum,
    version
)
VALUES
(
    '$package_a'::uuid,
    '$recording_a'::uuid,
    1,
    'APPROVED',
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '3 hours',
    CURRENT_TIMESTAMP - interval '2 hours',
    decode('$package_checksum', 'hex'),
    1
),
(
    '$package_b'::uuid,
    '$recording_b'::uuid,
    1,
    'APPROVED',
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '3 hours',
    CURRENT_TIMESTAMP - interval '2 hours',
    decode('$package_checksum', 'hex'),
    1
);

INSERT INTO editorial.publication (
    publication_id,
    recording_id,
    package_id,
    publication_no,
    status_code,
    active_from,
    active_to,
    published_by,
    published_at,
    checksum
)
VALUES
(
    '$publication_a'::uuid,
    '$recording_a'::uuid,
    '$package_a'::uuid,
    1,
    'ACTIVE',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '2 hours',
    decode('$checksum', 'hex')
),
(
    '$publication_b'::uuid,
    '$recording_b'::uuid,
    '$package_b'::uuid,
    1,
    'ACTIVE',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '2 hours',
    decode('$checksum', 'hex')
);

INSERT INTO editorial.publication_availability (
    availability_id,
    publication_id,
    territory_code,
    language_tag,
    audience_code,
    valid_from,
    valid_to,
    status_code
)
VALUES
(
    '$availability_a'::uuid,
    '$publication_a'::uuid,
    'CR',
    'es',
    'PUBLIC',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    'ACTIVE'
),
(
    '$availability_b'::uuid,
    '$publication_b'::uuid,
    'CR',
    'es',
    'PUBLIC',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    'ACTIVE'
);
COMMIT;
SQL

start_worker_and_wait() {
  : >"$worker_log"

  Secrets__Directory="$ROOT/secrets/local" \
  Secrets__RequireExternal=true \
  Database__Host="$PGHOST" \
  Database__Port="$PGPORT" \
  Database__Name="$PGDATABASE" \
  Database__Username=jp_login_worker \
  Database__PasswordSecret=postgres_worker_password \
  ObjectStore__Endpoint=http://127.0.0.1:9000 \
  ObjectStore__Bucket=musica-aprender-private \
  ObjectStore__EncryptionKeyReference=local-secret://object_store_encryption_key/v1 \
  Smtp__Host=127.0.0.1 \
  Smtp__Port=1025 \
  Smtp__FromAddress=no-reply@musica-aprender.local \
  Smtp__FromDisplayName="Musica y Aprender" \
  Smtp__Security=None \
  OpenTelemetry__OtlpEndpoint=http://127.0.0.1:4317 \
  dotnet run \
    --no-launch-profile \
    --project apps/worker/MusicaAprender.Worker.csproj \
    --configuration Release \
    --no-build \
    --no-restore \
    >"$worker_log" 2>&1 &
  worker_pid=$!

  for attempt in $(seq 1 30); do
    if grep -Fq "BL-MVP-042 public catalog search index rebuilt" "$worker_log"; then
      return
    fi
    if ! kill -0 "$worker_pid" >/dev/null 2>&1; then
      fail_check "Worker termino antes de reconstruir el indice de busqueda."
    fi
    sleep 1
  done

  fail_check "Worker no reconstruyo el indice dentro del tiempo esperado."
}

start_worker_and_wait
stop_worker

search_count="$(psql_scalar "SELECT count(*) FROM catalog.song_search_document WHERE recording_id IN ('$recording_a'::uuid, '$recording_b'::uuid);")"
assert_equal "dos grabaciones indexadas" "$search_count" "2"

kana_count="$(psql_scalar "SELECT count(*) FROM catalog.song_search_document WHERE recording_id IN ('$recording_a'::uuid, '$recording_b'::uuid) AND position('かいじゅう' in normalized_terms) > 0;")"
assert_equal "lectura kana indexada" "$kana_count" "2"

romaji_count="$(psql_scalar "SELECT count(*) FROM catalog.song_search_document WHERE recording_id IN ('$recording_a'::uuid, '$recording_b'::uuid) AND position('kaijuu' in normalized_terms) > 0;")"
assert_equal "lectura romaji indexada" "$romaji_count" "2"

mkdir -p artifacts/postgres
{
  echo "BL-MVP-042"
  echo "search_documents=$search_count"
  echo "kana_documents=$kana_count"
  echo "romaji_documents=$romaji_count"
  echo
  echo "EXPLAIN tsvector:"
  "${psql_base[@]}" --command="SET enable_seqscan=off; EXPLAIN SELECT recording_id FROM catalog.song_search_document WHERE search_vector @@ plainto_tsquery('simple'::regconfig, 'kaijuu');"
  echo
  echo "EXPLAIN pg_trgm:"
  "${psql_base[@]}" --command="SET enable_seqscan=off; EXPLAIN SELECT recording_id FROM catalog.song_search_document WHERE normalized_terms % 'kaijuu';"
} > artifacts/postgres/bl-mvp-042-public-search.txt

grep -Fq "ix_song_search_vector" artifacts/postgres/bl-mvp-042-public-search.txt \
  || fail_check "EXPLAIN no utilizo el indice GIN tsvector."
grep -Fq "ix_song_search_terms_trgm" artifacts/postgres/bl-mvp-042-public-search.txt \
  || fail_check "EXPLAIN no utilizo el indice GIN pg_trgm."

if grep -Eq 'HttpClient|WebClient|https?://' \
  src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs \
  apps/api/Endpoints/PublicCatalog/PublicCatalogSearchEndpoints.cs; then
  fail_check "La busqueda publica no debe depender de un servicio HTTP externo."
fi

if [[ "${BL042_USE_RUNNING_API:-false}" != "true" ]]; then
  Secrets__Directory="$ROOT/secrets/local" \
  Secrets__RequireExternal=true \
  Database__Host="$PGHOST" \
  Database__Port="$PGPORT" \
  Database__Name="$PGDATABASE" \
  Database__Username=jp_login_api \
  Database__PasswordSecret=postgres_api_password \
  ObjectStore__Endpoint=http://127.0.0.1:9000 \
  ObjectStore__Bucket=musica-aprender-private \
  ObjectStore__EncryptionKeyReference=local-secret://object_store_encryption_key/v1 \
  Smtp__Host=127.0.0.1 \
  Smtp__Port=1025 \
  Smtp__FromAddress=no-reply@musica-aprender.local \
  Smtp__FromDisplayName="Musica y Aprender" \
  Smtp__Security=None \
  Kestrel__Certificates__Default__Path="$ROOT/secrets/local/aspnetcore_local_https.pem" \
  Kestrel__Certificates__Default__KeyPath="$ROOT/secrets/local/aspnetcore_local_https.key" \
  ASPNETCORE_URLS="$api_url" \
  dotnet run \
    --no-launch-profile \
    --project apps/api/MusicaAprender.Api.csproj \
    --configuration Release \
    --no-build \
    --no-restore \
    >"$api_log" 2>&1 &
  api_pid=$!
fi

for attempt in $(seq 1 30); do
  if curl_request --fail "$api_url/health/live" >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    fail_check "API no disponible."
  fi
  sleep 1
done

first_page="$work_dir/first.json"
curl_request --fail --get \
  --data-urlencode "query=kaijuu" \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  --data-urlencode "pageSize=1" \
  "$api_url/api/v1/public/catalog/search" \
  >"$first_page"

mapfile -t first_values < <(
  node - "$first_page" <<'NODE'
const fs = require('node:fs');
const page = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!Array.isArray(page.items) || page.items.length !== 1) process.exit(1);
if (!page.hasMore || typeof page.nextCursor !== 'string' || page.nextCursor.length < 10) process.exit(1);
const item = page.items[0];
if (item.canonicalTitle !== '怪獣') process.exit(1);
if (item.artistName !== 'サカナクション') process.exit(1);
process.stdout.write(`${item.recordingId}\n${page.nextCursor}\n`);
NODE
)

first_recording="${first_values[0]}"
cursor="${first_values[1]}"

second_page="$work_dir/second.json"
curl_request --fail --get \
  --data-urlencode "query=kaijuu" \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  --data-urlencode "pageSize=1" \
  --data-urlencode "cursor=$cursor" \
  "$api_url/api/v1/public/catalog/search" \
  >"$second_page"

second_recording="$(
  node - "$second_page" <<'NODE'
const fs = require('node:fs');
const page = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!Array.isArray(page.items) || page.items.length !== 1) process.exit(1);
if (page.hasMore || page.nextCursor !== null) process.exit(1);
process.stdout.write(page.items[0].recordingId);
NODE
)"

if [[ "$first_recording" == "$second_recording" ]]; then
  fail_check "La paginacion estable repitio la misma grabacion."
fi

# En Git Bash sobre Windows, pasar caracteres japoneses como argumento a
# curl.exe puede degradarlos a '?' según la conversión MSYS/Windows. La URL
# usa exclusivamente ASCII con UTF-8 percent-encoded para probar el mismo
# valor Unicode sin depender de la página de códigos del host.
japanese_count="$(
  curl_request --fail \
    "$api_url/api/v1/public/catalog/search?query=%E6%80%AA%E7%8D%A3&territory=CR&language=es&pageSize=10" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(s).items.length)))"
)"
assert_equal "busqueda Unicode japonesa" "$japanese_count" "2"

wrong_territory_count="$(
  curl_request --fail --get \
    --data-urlencode "query=kaijuu" \
    --data-urlencode "territory=JP" \
    --data-urlencode "language=es" \
    --data-urlencode "pageSize=10" \
    "$api_url/api/v1/public/catalog/search" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(s).items.length)))"
)"
assert_equal "territorio no autorizado" "$wrong_territory_count" "0"

"${psql_base[@]}" >/dev/null <<SQL
UPDATE editorial.publication_availability
SET status_code = 'WITHDRAWN'
WHERE availability_id = '$availability_a'::uuid;
SQL

stale_index_count="$(psql_scalar "SELECT count(*) FROM catalog.song_search_document WHERE recording_id = '$recording_a'::uuid;")"
assert_equal "documento derivado aun presente antes del refresh" "$stale_index_count" "1"

post_withdrawal="$(
  curl_request --fail --get \
    --data-urlencode "query=kaijuu" \
    --data-urlencode "territory=CR" \
    --data-urlencode "language=es" \
    --data-urlencode "pageSize=10" \
    "$api_url/api/v1/public/catalog/search" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(s).items.length)))"
)"
assert_equal "indice no autoriza tras retiro" "$post_withdrawal" "1"

echo "OK: BL-MVP-042 titulo, alias, artista, lectura, tsvector, pg_trgm, paginacion estable y revalidacion verificadas."
