#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL043_API_URL:-https://localhost:5458}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
api_pid=""

publisher_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
artist_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
source_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
availability_id="$(node -e "console.log(require('node:crypto').randomUUID())")"

external_ref="BL043A00001"
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

if [[ "${BL043_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-043: $1" >&2
  if [[ -s "$api_log" ]]; then
    echo "--- api ---" >&2
    tail -n 120 "$api_log" >&2 || true
  fi
  exit 1
}

curl_request() {
  curl "${curl_tls_options[@]}" --silent --show-error "$@"
}

stop_api() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" >/dev/null 2>&1 || true
    wait "$api_pid" >/dev/null 2>&1 || true
    api_pid=""
  fi
}

cleanup_rows() {
  stop_api
  "${psql_base[@]}" >/dev/null <<SQL || true
BEGIN;
SELECT set_config('app.maintenance_mode', 'on', true);
DELETE FROM catalog.song_search_document WHERE recording_id = '$recording_id'::uuid;
DELETE FROM editorial.published_package_projection WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.publication_availability WHERE availability_id = '$availability_id'::uuid;
DELETE FROM editorial.publication WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.editorial_package WHERE package_id = '$package_id'::uuid;
DELETE FROM catalog.recording_source WHERE source_id = '$source_id'::uuid;
DELETE FROM catalog.recording WHERE recording_id = '$recording_id'::uuid;
DELETE FROM catalog.work_artist WHERE work_id = '$work_id'::uuid AND artist_id = '$artist_id'::uuid;
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

if [[ "${BL043_SKIP_ACCESS_PREP:-false}" != "true" ]]; then
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
VALUES (
    '$recording_id'::uuid,
    '$work_id'::uuid,
    'Album version',
    241000,
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
VALUES (
    '$source_id'::uuid,
    '$recording_id'::uuid,
    'YOUTUBE',
    '$external_ref',
    241000,
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
VALUES (
    '$package_id'::uuid,
    '$recording_id'::uuid,
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
VALUES (
    '$publication_id'::uuid,
    '$recording_id'::uuid,
    '$package_id'::uuid,
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
VALUES (
    '$availability_id'::uuid,
    '$publication_id'::uuid,
    'CR',
    'es',
    'PUBLIC',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    'ACTIVE'
);

INSERT INTO editorial.published_package_projection (
    publication_id,
    recording_id,
    component_versions,
    payload_ref,
    projection_version,
    built_at
)
VALUES (
    '$publication_id'::uuid,
    '$recording_id'::uuid,
    jsonb_build_object(
        'schemaVersion', 1,
        'source', jsonb_build_object(
            'sourceId', '$source_id',
            'providerCode', 'YOUTUBE',
            'externalRef', '$external_ref',
            'version', 1
        ),
        'components', jsonb_build_array(
            jsonb_build_object('kind', 'CATALOG', 'displayOrder', 0)
        )
    ),
    NULL,
    1,
    CURRENT_TIMESTAMP
);

INSERT INTO catalog.song_search_document (
    recording_id,
    publication_id,
    normalized_terms,
    eligibility_version,
    indexed_at
)
VALUES (
    '$recording_id'::uuid,
    '$publication_id'::uuid,
    '怪獣 サカナクション kaijuu',
    1,
    CURRENT_TIMESTAMP
);
COMMIT;
SQL

if [[ "${BL043_USE_RUNNING_API:-false}" != "true" ]]; then
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
  OpenTelemetry__OtlpEndpoint=http://127.0.0.1:4317 \
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

for attempt in $(seq 1 40); do
  if curl_request --fail "$api_url/health/live" >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" -eq 40 ]]; then
    fail_check "API BL043 no inicio dentro del tiempo esperado."
  fi
  sleep 1
done

search_json="$work_dir/search.json"
curl_request --fail --get \
  --data-urlencode "query=kaijuu" \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  --data-urlencode "pageSize=10" \
  "$api_url/api/v1/public/catalog/search" \
  >"$search_json"

slug="$({
  node - "$search_json" <<'NODE'
const fs = require('node:fs');
const page = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!Array.isArray(page.items) || page.items.length !== 1) process.exit(1);
const item = page.items[0];
if (item.canonicalTitle !== '怪獣') process.exit(1);
if (item.artistName !== 'サカナクション') process.exit(1);
if (item.recordingTitle !== 'Album version') process.exit(1);
if (typeof item.slug !== 'string' || !/-[0-9a-f]{20}$/.test(item.slug)) process.exit(1);
const forbidden = Object.keys(item).filter((key) => /Id$/.test(key) || key === 'externalRef');
if (forbidden.length !== 0) process.exit(1);
process.stdout.write(item.slug);
NODE
} || fail_check "La busqueda publica no devolvio contrato seguro con slug.")"

encoded_slug="$(node -e "process.stdout.write(encodeURIComponent(process.argv[1]))" "$slug")"
detail_json="$work_dir/detail.json"
curl_request --fail --get \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$encoded_slug" \
  >"$detail_json"

node - "$detail_json" "$slug" <<'NODE' || fail_check "La ficha publica no cumple el contrato seguro."
const fs = require('node:fs');
const detail = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const slug = process.argv[3];
if (detail.slug !== slug) process.exit(1);
if (detail.canonicalTitle !== '怪獣') process.exit(1);
if (detail.artistName !== 'サカナクション') process.exit(1);
if (detail.recordingTitle !== 'Album version') process.exit(1);
if (detail.providerCode !== 'YOUTUBE') process.exit(1);
if (detail.territoryCode !== 'CR' || detail.languageTag !== 'es') process.exit(1);
if (!Array.isArray(detail.availableComponents) || !detail.availableComponents.includes('CATALOG')) process.exit(1);
const forbidden = Object.keys(detail).filter((key) => /Id$/.test(key) || key === 'externalRef' || /checksum/i.test(key));
if (forbidden.length !== 0) process.exit(1);
NODE

wrong_territory_status="$(curl_request --output /dev/null --write-out '%{http_code}' --get \
  --data-urlencode "territory=US" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$encoded_slug")"
if [[ "$wrong_territory_status" != "404" ]]; then
  fail_check "territorio no autorizado esperaba 404 y obtuvo $wrong_territory_status."
fi

malformed_status="$(curl_request --output /dev/null --write-out '%{http_code}' --get \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/slug-invalido")"
if [[ "$malformed_status" != "400" ]]; then
  fail_check "slug invalido esperaba 400 y obtuvo $malformed_status."
fi

"${psql_base[@]}" >/dev/null <<SQL
UPDATE catalog.recording_source
SET status_code = 'RETIRED', version = version + 1
WHERE source_id = '$source_id'::uuid;
SQL

retired_status="$(curl_request --output /dev/null --write-out '%{http_code}' --get \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$encoded_slug")"
if [[ "$retired_status" != "404" ]]; then
  fail_check "fuente retirada esperaba 404 inmediato y obtuvo $retired_status."
fi

mkdir -p artifacts/postgres
{
  echo "BL-MVP-043"
  echo "slug=$slug"
  echo "public_contract=no_internal_ids"
  echo "territory_revalidation=pass"
  echo "source_revalidation=pass"
  echo "youtube_network_dependency=none"
} > artifacts/postgres/bl-mvp-043-public-song-detail.txt

stop_api

echo "OK: BL-MVP-043 ficha publica por slug, contrato minimo, territorio y revalidacion verificados."
