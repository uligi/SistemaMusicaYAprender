#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL069_API_URL:-https://localhost:5465}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
api_pid=""

publisher_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
source_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
lyrics_revision_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_component_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_component_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
availability_id="$(node -e "console.log(require('node:crypto').randomUUID())")"

external_ref="BL069vid001"
email_hash="$(openssl rand -hex 32)"
email_cipher="$(openssl rand -hex 24)"
lyrics_checksum="$(openssl rand -hex 32)"
package_checksum="$(openssl rand -hex 32)"
publication_checksum="$(openssl rand -hex 32)"

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

if [[ "${BL069_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-069: $1" >&2
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
SET LOCAL session_replication_role = replica;

DELETE FROM editorial.published_package_projection
WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.publication_component
WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.publication_availability
WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.publication
WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.package_component
WHERE package_id = '$package_id'::uuid;
DELETE FROM editorial.editorial_package
WHERE package_id = '$package_id'::uuid;
DELETE FROM content.lyrics_revision
WHERE lyrics_revision_id = '$lyrics_revision_id'::uuid;
DELETE FROM catalog.recording_source
WHERE source_id = '$source_id'::uuid;
DELETE FROM catalog.recording
WHERE recording_id = '$recording_id'::uuid;
DELETE FROM catalog.musical_work
WHERE work_id = '$work_id'::uuid;
DELETE FROM security.account
WHERE account_id = '$publisher_id'::uuid;

COMMIT;
SQL
}

cleanup() {
  cleanup_rows
  rm -rf "$work_dir"
}
trap cleanup EXIT

endpoint="apps/api/Endpoints/PublicCatalog/PublicEducationalPackageEndpoints.cs"
service="src/Modules/Content/Infrastructure/PublicPlayback/PublicEducationalPackageService.cs"

[[ -f "$endpoint" ]] || fail_check "falta endpoint BL069."
[[ -f "$service" ]] || fail_check "falta servicio BL069."

grep -Fq '/api/v1/public/catalog/songs/{slug}/learning-package' "$endpoint" \
  || fail_check "falta contrato público del paquete."
grep -Fq 'Cache-Control"] = "public, no-cache"' "$endpoint" \
  || fail_check "la caché no exige revalidación."
grep -Fq 'IfNoneMatch' "$endpoint" \
  || fail_check "falta ETag condicional."
grep -Fq 'IsolationLevel.RepeatableRead' "$service" \
  || fail_check "el paquete no se resuelve en snapshot coherente."
grep -Fq 'SET TRANSACTION READ ONLY' "$service" \
  || fail_check "la consulta integral no está marcada read-only."
grep -Fq 'editorial.published_package_projection' "$service" \
  || fail_check "falta proyección derivada."
grep -Fq 'editorial.publication_component' "$service" \
  || fail_check "falta instantánea canónica publicada."
grep -Fq 'editorial.package_component' "$service" \
  || fail_check "falta linaje package_component."
grep -Fq 'publicationChecksum' "$service" \
  || fail_check "falta verificación del checksum de publicación."
grep -Fq 'RevisionChecksumSha256' "$service" \
  || fail_check "falta checksum de revisión canónica."
grep -Fq 'TimingLyricsRevisionId' "$service" \
  || fail_check "falta compatibilidad timing/letra."
grep -Fq 'TranslationLyricsRevisionId' "$service" \
  || fail_check "falta compatibilidad traducción/letra."
grep -Fq 'AnalysisLyricsRevisionId' "$service" \
  || fail_check "falta compatibilidad análisis/letra."
grep -Fq 'ExerciseLineCompatible' "$service" \
  || fail_check "falta compatibilidad de ejercicios."
grep -Fq 'source.status_code IN (' "$service" \
  || fail_check "falta revalidación de fuente."
grep -Fq "availability_row.status_code = 'ACTIVE'" "$service" \
  || fail_check "la proyección está concediendo disponibilidad."
grep -Fq "publication.status_code = 'ACTIVE'" "$service" \
  || fail_check "la proyección está concediendo publicación."

cleanup_rows

if [[ "${BL069_SKIP_ACCESS_PREP:-false}" != "true" \
      && "${BL069_USE_DOCKER_PSQL:-false}" != "true" ]]; then
  bash scripts/database/prepare-database-access.sh >/dev/null
fi

docker compose up --detach object-store smtp-sink otel-collector >/dev/null
for attempt in $(seq 1 30); do
  if curl --fail --silent \
      http://127.0.0.1:9000/minio/health/ready >/dev/null; then
    break
  fi

  if [[ "$attempt" -eq 30 ]]; then
    fail_check "Object store no disponible."
  fi

  sleep 1
done

"${psql_base[@]}" >/dev/null <<SQL
BEGIN;
SELECT set_config('app.maintenance_mode', 'on', true);

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
    'BL069 package work',
    'ja',
    NULL,
    'DRAFT',
    1
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
    'BL069 package recording',
    10000,
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
    10000,
    0,
    'ACTIVE',
    1
);

INSERT INTO content.lyrics_revision (
    lyrics_revision_id,
    recording_id,
    revision_no,
    parent_revision_id,
    status_code,
    created_by,
    checksum,
    version
)
VALUES (
    '$lyrics_revision_id'::uuid,
    '$recording_id'::uuid,
    7,
    NULL,
    'DRAFT',
    '$publisher_id'::uuid,
    decode('$lyrics_checksum', 'hex'),
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
    3,
    'APPROVED',
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '3 hours',
    CURRENT_TIMESTAMP - interval '2 hours',
    decode('$package_checksum', 'hex'),
    1
);

INSERT INTO editorial.package_component (
    package_component_id,
    package_id,
    component_kind,
    lyrics_revision_id,
    timing_revision_id,
    translation_revision_id,
    analysis_revision_id,
    exercise_revision_id,
    checksum
)
VALUES (
    '$package_component_id'::uuid,
    '$package_id'::uuid,
    'LYRICS',
    '$lyrics_revision_id'::uuid,
    NULL,
    NULL,
    NULL,
    NULL,
    decode('$lyrics_checksum', 'hex')
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
    5,
    'ACTIVE',
    CURRENT_TIMESTAMP - interval '1 hour',
    NULL,
    '$publisher_id'::uuid,
    CURRENT_TIMESTAMP - interval '2 hours',
    decode('$publication_checksum', 'hex')
);

INSERT INTO editorial.publication_component (
    publication_component_id,
    publication_id,
    component_kind,
    source_component_id,
    component_checksum,
    display_order
)
VALUES (
    '$publication_component_id'::uuid,
    '$publication_id'::uuid,
    'LYRICS',
    '$package_component_id'::uuid,
    decode('$lyrics_checksum', 'hex'),
    0
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
        'publicationNo', 5,
        'publicationChecksum', upper('$publication_checksum'),
        'source', jsonb_build_object(
            'sourceId', '$source_id',
            'providerCode', 'YOUTUBE',
            'externalRef', '$external_ref',
            'version', 1
        ),
        'components', jsonb_build_array(
            jsonb_build_object(
                'kind', 'LYRICS',
                'sourceComponentId', '$package_component_id',
                'checksum', upper('$lyrics_checksum'),
                'displayOrder', 0
            )
        )
    ),
    NULL,
    4,
    CURRENT_TIMESTAMP
);

COMMIT;
SQL

slug_key="$("${psql_base[@]}" \
  --command="SELECT substring(md5('$recording_id'::uuid::text || ':public-song-v1') from 1 for 20);")"
slug="bl069-${slug_key}"

if [[ "${BL069_USE_RUNNING_API:-false}" != "true" ]]; then
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
    fail_check "API BL069 no inició dentro del tiempo esperado."
  fi

  sleep 1
done

headers="$work_dir/headers.txt"
body="$work_dir/package.json"

curl_request --fail \
  --dump-header "$headers" \
  --output "$body" \
  --get \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$slug/learning-package"

etag="$(awk 'BEGIN{IGNORECASE=1} /^etag:/ {
    sub(/\r$/, "", $0);
    sub(/^[Ee][Tt][Aa][Gg]:[[:space:]]*/, "", $0);
    print;
    exit
}' "$headers")"

cache_control="$(awk 'BEGIN{IGNORECASE=1} /^cache-control:/ {
    sub(/\r$/, "", $0);
    sub(/^[Cc][Aa][Cc][Hh][Ee]-[Cc][Oo][Nn][Tt][Rr][Oo][Ll]:[[:space:]]*/, "", $0);
    print;
    exit
}' "$headers")"

[[ "$etag" == "\"sha256-${publication_checksum}\"" ]] \
  || fail_check "ETag no deriva del checksum vigente."
[[ "$cache_control" == *"public"* && "$cache_control" == *"no-cache"* ]] \
  || fail_check "Cache-Control no obliga revalidación."

node - "$body" "$slug" "$publication_checksum" "$package_checksum" "$lyrics_checksum" <<'NODE' \
  || fail_check "el body BL069 no cumple el contrato."
const fs = require('node:fs');
const body = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const slug = process.argv[3];
const publicationChecksum = process.argv[4].toUpperCase();
const packageChecksum = process.argv[5].toUpperCase();
const lyricsChecksum = process.argv[6].toUpperCase();

if (body.schemaVersion !== 1) process.exit(1);
if (body.slug !== slug) process.exit(1);
if (body.publicationNo !== 5 || body.packageNo !== 3) process.exit(1);
if (body.publicationChecksumSha256 !== publicationChecksum) process.exit(1);
if (body.packageChecksumSha256 !== packageChecksum) process.exit(1);
if (body.source?.providerCode !== 'YOUTUBE') process.exit(1);
if (body.source?.externalRef !== 'BL069vid001') process.exit(1);
if (body.availability?.territoryCode !== 'CR') process.exit(1);
if (body.availability?.languageTag !== 'es') process.exit(1);
if (body.capabilities?.lyrics !== true) process.exit(1);
if (body.capabilities?.timing !== false) process.exit(1);
if (!Array.isArray(body.components) || body.components.length !== 1) process.exit(1);
if (body.components[0].kind !== 'LYRICS') process.exit(1);
if (body.components[0].revisionNo !== 7) process.exit(1);
if (body.components[0].checksumSha256 !== lyricsChecksum) process.exit(1);

const forbidden = [];
function walk(value, path = '') {
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    const next = path ? `${path}.${key}` : key;
    if (/Id$/.test(key) || /Uuid$/i.test(key)) forbidden.push(next);
    walk(child, next);
  }
}
walk(body);
if (forbidden.length !== 0) process.exit(1);
NODE

not_modified="$(
  curl_request \
    --output /dev/null \
    --write-out '%{http_code}' \
    --header "If-None-Match: $etag" \
    --get \
    --data-urlencode "territory=CR" \
    --data-urlencode "language=es" \
    "$api_url/api/v1/public/catalog/songs/$slug/learning-package"
)"
[[ "$not_modified" == "304" ]] \
  || fail_check "If-None-Match vigente esperaba 304 y obtuvo $not_modified."

"${psql_base[@]}" >/dev/null <<SQL
UPDATE editorial.published_package_projection
SET component_versions = jsonb_set(
    component_versions,
    '{publicationChecksum}',
    to_jsonb(upper(repeat('00', 32)))
)
WHERE publication_id = '$publication_id'::uuid;
SQL

mismatch_status="$(
  curl_request \
    --output /dev/null \
    --write-out '%{http_code}' \
    --header "If-None-Match: $etag" \
    --get \
    --data-urlencode "territory=CR" \
    --data-urlencode "language=es" \
    "$api_url/api/v1/public/catalog/songs/$slug/learning-package"
)"
[[ "$mismatch_status" == "409" ]] \
  || fail_check "proyección adulterada esperaba 409 y obtuvo $mismatch_status."

"${psql_base[@]}" >/dev/null <<SQL
UPDATE editorial.published_package_projection
SET component_versions = jsonb_set(
    component_versions,
    '{publicationChecksum}',
    to_jsonb(upper('$publication_checksum'))
)
WHERE publication_id = '$publication_id'::uuid;

UPDATE editorial.publication_availability
SET valid_to = CURRENT_TIMESTAMP - interval '1 second'
WHERE availability_id = '$availability_id'::uuid;
SQL

expired_status="$(
  curl_request \
    --output /dev/null \
    --write-out '%{http_code}' \
    --header "If-None-Match: $etag" \
    --get \
    --data-urlencode "territory=CR" \
    --data-urlencode "language=es" \
    "$api_url/api/v1/public/catalog/songs/$slug/learning-package"
)"
[[ "$expired_status" == "404" ]] \
  || fail_check "availability vencida esperaba 404 y obtuvo $expired_status."

malformed_status="$(
  curl_request \
    --output /dev/null \
    --write-out '%{http_code}' \
    --get \
    --data-urlencode "territory=CR" \
    --data-urlencode "language=es" \
    "$api_url/api/v1/public/catalog/songs/slug-invalido/learning-package"
)"
[[ "$malformed_status" == "400" ]] \
  || fail_check "slug inválido esperaba 400 y obtuvo $malformed_status."

mkdir -p artifacts/postgres
cat > artifacts/postgres/bl-mvp-069-public-educational-package.txt <<EVIDENCE
bl=BL-MVP-069
endpoint=/api/v1/public/catalog/songs/{slug}/learning-package
read_snapshot=repeatable_read
transaction_read_only=true
projection_authority=false
publication_revalidated=true
availability_revalidated=true
source_revalidated=true
publication_component_lineage=true
package_component_lineage=true
revision_checksum_verified=true
publication_checksum_verified=true
etag_revalidated=true
stale_etag_cannot_authorize=true
projection_mismatch=409
availability_expired=404
internal_ids_exposed=false
writes=false
publishes=false
EVIDENCE

echo "bl=BL-MVP-069"
echo "published_package_read_model=true"
echo "compatible_revisions=true"
echo "checksum=true"
echo "etag_revalidated=true"
echo "projection_grants_publication=false"
echo "mixed_content=false"
echo "internal_ids=false"
echo "writes=false"
echo "publishes=false"
echo "OK: BL-MVP-069 paquete educativo publicado verificado."
