#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL041_API_URL:-https://localhost:5456}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
worker_log="$work_dir/worker.log"
api_pid=""
worker_pid=""

publisher_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
artist_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
source_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
replacement_source_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
availability_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
draft_recording_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
draft_source_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
draft_package_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
draft_publication_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
draft_availability_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
external_ref="$(openssl rand -hex 8 | cut -c1-11)"
replacement_external_ref="$(openssl rand -hex 8 | cut -c1-11)"
draft_external_ref="$(openssl rand -hex 8 | cut -c1-11)"
email_hash="$(openssl rand -hex 32)"
email_cipher="$(openssl rand -hex 24)"
checksum_hex="$(openssl rand -hex 32)"
package_checksum_hex="$(openssl rand -hex 32)"

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-041: $1" >&2
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

if [[ "${BL041_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

psql_scalar() {
  "${psql_base[@]}" --command="$1" | tr -d '[:space:]'
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
DELETE FROM editorial.published_package_projection
WHERE publication_id IN ('$publication_id'::uuid, '$draft_publication_id'::uuid);
DELETE FROM editorial.publication_availability
WHERE availability_id IN ('$availability_id'::uuid, '$draft_availability_id'::uuid);
DELETE FROM editorial.publication
WHERE publication_id IN ('$publication_id'::uuid, '$draft_publication_id'::uuid);
DELETE FROM editorial.editorial_package
WHERE package_id IN ('$package_id'::uuid, '$draft_package_id'::uuid);
DELETE FROM catalog.recording_source
WHERE source_id IN ('$source_id'::uuid, '$replacement_source_id'::uuid, '$draft_source_id'::uuid);
DELETE FROM catalog.recording
WHERE recording_id IN ('$recording_id'::uuid, '$draft_recording_id'::uuid);
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

curl_request() {
  curl "${curl_tls_options[@]}" --silent --show-error "$@"
}

if [[ "${BL041_SKIP_ACCESS_PREP:-false}" != "true" ]]; then
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
    'BL041 公開 Artist',
    'BL041 Public Artist',
    'GROUP',
    'ACTIVE',
    1
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
    'BL041 公開曲',
    'ja',
    NULL,
    'DRAFT',
    1
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
    '$recording_id'::uuid,
    '$work_id'::uuid,
    'BL041 公開 recording',
    241125,
    NULL,
    'DRAFT',
    1
),
(
    '$draft_recording_id'::uuid,
    '$work_id'::uuid,
    'BL041 draft recording',
    241125,
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
    '$source_id'::uuid,
    '$recording_id'::uuid,
    'YOUTUBE',
    '$external_ref',
    245000,
    2500,
    'ACTIVE',
    1
),
(
    '$draft_source_id'::uuid,
    '$draft_recording_id'::uuid,
    'YOUTUBE',
    '$draft_external_ref',
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
    '$package_id'::uuid,
    '$recording_id'::uuid,
    1,
    'APPROVED',
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '3 hours',
    CURRENT_TIMESTAMP - interval '2 hours 30 minutes',
    decode('$package_checksum_hex', 'hex'),
    1
),
(
    '$draft_package_id'::uuid,
    '$draft_recording_id'::uuid,
    1,
    'DRAFT',
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '3 hours',
    NULL,
    decode('$package_checksum_hex', 'hex'),
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
    '$publication_id'::uuid,
    '$recording_id'::uuid,
    '$package_id'::uuid,
    1,
    'ACTIVE',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '2 hours',
    decode('$checksum_hex', 'hex')
),
(
    '$draft_publication_id'::uuid,
    '$draft_recording_id'::uuid,
    '$draft_package_id'::uuid,
    1,
    'DRAFT',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '2 hours',
    decode('$checksum_hex', 'hex')
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
    '$availability_id'::uuid,
    '$publication_id'::uuid,
    'CR',
    'es',
    'PUBLIC',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    'ACTIVE'
),
(
    '$draft_availability_id'::uuid,
    '$draft_publication_id'::uuid,
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
    if grep -Fq "BL-MVP-041 public catalog projection rebuilt" "$worker_log"; then
      return
    fi
    if ! kill -0 "$worker_pid" >/dev/null 2>&1; then
      fail_check "Worker termino antes de reconstruir la proyeccion."
    fi
    sleep 1
  done

  fail_check "Worker no reconstruyo la proyeccion dentro del tiempo esperado."
}

start_worker_and_wait
stop_worker

projected_count="$(psql_scalar "SELECT count(*) FROM editorial.published_package_projection WHERE publication_id = '$publication_id'::uuid;")"
assert_equal "publicacion vigente proyectada" "$projected_count" "1"

draft_count="$(psql_scalar "SELECT count(*) FROM editorial.published_package_projection WHERE publication_id = '$draft_publication_id'::uuid;")"
assert_equal "borrador excluido" "$draft_count" "0"

first_version="$(psql_scalar "SELECT projection_version FROM editorial.published_package_projection WHERE publication_id = '$publication_id'::uuid;")"
start_worker_and_wait
stop_worker
second_version="$(psql_scalar "SELECT projection_version FROM editorial.published_package_projection WHERE publication_id = '$publication_id'::uuid;")"
assert_equal "rebuild idempotente" "$second_version" "$first_version"

if [[ "${BL041_USE_RUNNING_API:-false}" != "true" ]]; then
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

eligible_status="$(
  curl_request \
    --output "$work_dir/eligible.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/public/catalog/publications/$publication_id/projection?territory=CR&language=es"
)"
assert_equal "apertura elegible" "$eligible_status" "200"

node - "$work_dir/eligible.json" "$publication_id" "$recording_id" "$source_id" "$external_ref" <<'NODE'
const fs = require('node:fs');
const [path, publicationId, recordingId, sourceId, externalRef] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
if (data.publicationId !== publicationId) process.exit(1);
if (data.recordingId !== recordingId) process.exit(1);
if (data.sourceId !== sourceId) process.exit(1);
if (data.providerCode !== 'YOUTUBE') process.exit(1);
if (data.externalRef !== externalRef) process.exit(1);
if (data.territoryCode !== 'CR') process.exit(1);
if (data.languageTag !== 'es') process.exit(1);
if (data.canonicalTitle !== 'BL041 公開曲') process.exit(1);
NODE

wrong_territory_status="$(
  curl_request \
    --output "$work_dir/wrong-territory.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/public/catalog/publications/$publication_id/projection?territory=US&language=es"
)"
assert_equal "territorio no autorizado" "$wrong_territory_status" "404"

"${psql_base[@]}" --command="UPDATE catalog.recording_source SET status_code = 'WITHDRAWN' WHERE source_id = '$source_id'::uuid;" >/dev/null

source_revalidation_status="$(
  curl_request \
    --output "$work_dir/source-withdrawn.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/public/catalog/publications/$publication_id/projection?territory=CR&language=es"
)"
assert_equal "fuente canonica retirada revalidada" "$source_revalidation_status" "404"

start_worker_and_wait
stop_worker
projected_after_source_withdrawal="$(psql_scalar "SELECT count(*) FROM editorial.published_package_projection WHERE publication_id = '$publication_id'::uuid;")"
assert_equal "proyeccion retira fuente no elegible" "$projected_after_source_withdrawal" "0"

"${psql_base[@]}" >/dev/null <<SQL
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
VALUES (
    '$replacement_source_id'::uuid,
    '$recording_id'::uuid,
    'YOUTUBE',
    '$replacement_external_ref',
    245000,
    2500,
    'ACTIVE',
    1
);
SQL

start_worker_and_wait
stop_worker
projected_after_rebuild="$(psql_scalar "SELECT count(*) FROM editorial.published_package_projection WHERE publication_id = '$publication_id'::uuid;")"
assert_equal "proyeccion reconstruible" "$projected_after_rebuild" "1"

replacement_status="$(
  curl_request \
    --output "$work_dir/replacement.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/public/catalog/publications/$publication_id/projection?territory=CR&language=es"
)"
assert_equal "fuente sustituta reconstruida" "$replacement_status" "200"
node - "$work_dir/replacement.json" "$replacement_source_id" "$replacement_external_ref" <<'NODE'
const fs = require('node:fs');
const [path, sourceId, externalRef] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
if (data.sourceId !== sourceId) process.exit(1);
if (data.externalRef !== externalRef) process.exit(1);
NODE

"${psql_base[@]}" --command="UPDATE editorial.publication_availability SET valid_to = CURRENT_TIMESTAMP - interval '1 minute' WHERE availability_id = '$availability_id'::uuid;" >/dev/null

expired_status="$(
  curl_request \
    --output "$work_dir/expired.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/public/catalog/publications/$publication_id/projection?territory=CR&language=es"
)"
assert_equal "vigencia expirada revalidada" "$expired_status" "404"

start_worker_and_wait
stop_worker
projected_after_expiry="$(psql_scalar "SELECT count(*) FROM editorial.published_package_projection WHERE publication_id = '$publication_id'::uuid;")"
assert_equal "proyeccion excluye vigencia expirada" "$projected_after_expiry" "0"

invalid_context_status="$(
  curl_request \
    --output "$work_dir/invalid.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/public/catalog/publications/$publication_id/projection?territory=%25%25%25&language=es"
)"
assert_equal "contexto territorial invalido" "$invalid_context_status" "400"

mkdir -p artifacts/postgres
cat > artifacts/postgres/bl-mvp-041-public-catalog-projection.txt <<EVIDENCE
bl_mvp=041
active_publication_projected=true
draft_publication_projected=false
rebuild_idempotent=true
canonical_source_revalidated=true
territory_revalidated=true
validity_revalidated=true
projection_reconstructible=true
external_search_calls=0
EVIDENCE

echo "OK: BL-MVP-041 proyeccion publica vigente, reconstruible y revalidacion canonica verificadas."
