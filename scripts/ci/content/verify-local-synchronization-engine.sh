#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL059_API_URL:-https://localhost:5463}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
api_pid=""

publisher_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
artist_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
source_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
lyrics_revision_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
section_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
line_1_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
line_2_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
token_1_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
token_2_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
timing_revision_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
availability_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_lyrics_component_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_timing_component_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_lyrics_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_timing_id="$(node -e "console.log(require('node:crypto').randomUUID())")"

external_ref="BL059vid001"
email_hash="$(openssl rand -hex 32)"
email_cipher="$(openssl rand -hex 24)"
package_checksum="$(openssl rand -hex 32)"
publication_checksum="$(openssl rand -hex 32)"
component_checksum="$(openssl rand -hex 32)"

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

if [[ "${BL059_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-059: $1" >&2
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
DELETE FROM editorial.published_package_projection WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.publication_component WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.publication_availability WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.publication WHERE publication_id = '$publication_id'::uuid;
DELETE FROM editorial.package_component WHERE package_id = '$package_id'::uuid;
DELETE FROM editorial.editorial_package WHERE package_id = '$package_id'::uuid;
DELETE FROM content.timing_segment WHERE timing_revision_id = '$timing_revision_id'::uuid;
DELETE FROM content.timing_revision WHERE timing_revision_id = '$timing_revision_id'::uuid;
DELETE FROM content.lyric_token WHERE line_id IN ('$line_1_id'::uuid, '$line_2_id'::uuid);
DELETE FROM content.lyric_line WHERE section_id = '$section_id'::uuid;
DELETE FROM content.lyric_section WHERE section_id = '$section_id'::uuid;
DELETE FROM content.lyrics_revision WHERE lyrics_revision_id = '$lyrics_revision_id'::uuid;
DELETE FROM catalog.recording_source WHERE source_id = '$source_id'::uuid;
DELETE FROM catalog.recording WHERE recording_id = '$recording_id'::uuid;
DELETE FROM catalog.work_artist
WHERE work_id = '$work_id'::uuid
  AND artist_id = '$artist_id'::uuid;
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

for marker in \
  'while (low <= high)' \
  'prefixMaximumEndMs' \
  "playbackPollMs = 100" \
  "pausedPollMs = 250" \
  "level: 'TOKEN'" \
  "level: 'LINE'" \
  "level: 'NONE'"; do
  grep -Fq "$marker" \
    apps/web/src/features/player/synchronization/LocalSynchronizationEngine.ts \
    apps/web/src/features/player/synchronization/SynchronizedYouTubePreview.tsx \
    || fail_check "falta marcador del motor local: $marker"
done

grep -Fq '/synchronization' \
  apps/api/Endpoints/PublicCatalog/PublicSongSynchronizationEndpoints.cs \
  || fail_check "falta endpoint público de sincronización."

grep -Fq "component ->> 'kind' = 'TIMING'" \
  src/Modules/Content/Infrastructure/PublicPlayback/PublicSongSynchronizationService.cs \
  || fail_check "el servicio público no fija la revisión TIMING publicada."

grep -Fq "lyrics_component ->> 'kind' = 'LYRICS'" \
  src/Modules/Content/Infrastructure/PublicPlayback/PublicSongSynchronizationService.cs \
  || fail_check "el servicio público no revalida compatibilidad con LYRICS."

grep -Fq 'editorial.package_component AS package_component' \
  src/Modules/Content/Infrastructure/PublicPlayback/PublicSongSynchronizationService.cs \
  || fail_check "TIMING no se resuelve desde el package_component publicado."

grep -Fq 'published_component.source_component_id' \
  src/Modules/Content/Infrastructure/PublicPlayback/PublicSongSynchronizationService.cs \
  || fail_check "la proyección no se revalida contra publication_component."

for marker in \
  'data-editorial-sync-workspace' \
  'Línea que estás editando' \
  'Avanzar automáticamente a la siguiente línea' \
  'Marcar inicio línea' \
  'Marcar fin línea'; do
  grep -Fq "$marker" \
    apps/web/src/routes/editorial/SynchronizationStructurePage.tsx \
    apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx \
    || fail_check "falta marcador UX BL059E: $marker"
done

grep -Fq 'position: sticky' \
  apps/web/src/routes/editorial/synchronization-structure.css \
  || fail_check "el video editorial no conserva preview sticky en desktop."

grep -Fq 'onControllerReady?:' \
  apps/web/src/features/player/synchronization/SynchronizedYouTubePreview.tsx \
  || fail_check "el preview sincronizado no expone controller al editor editorial."

if grep -R -E 'youtube/v3|googleapis\.com/youtube|download.*(audio|video)' \
  apps/web/src/features/player/synchronization \
  src/Modules/Content/Infrastructure/PublicPlayback \
  apps/api/Endpoints/PublicCatalog/PublicSongSynchronizationEndpoints.cs >/dev/null; then
  fail_check "BL059 introdujo dependencia prohibida de Data API/descarga."
fi

cleanup_rows

if [[ "${BL059_SKIP_ACCESS_PREP:-false}" != "true" \
      && "${BL059_USE_DOCKER_PSQL:-false}" != "true" ]]; then
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
    convert_from(decode('e382b5e382abe3838ae382afe382b7e383a7e383b3', 'hex'), 'UTF8'),
    'Sakanaction BL059',
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
    'BL059 synchronization work',
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
    'BL059 synchronization recording',
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
    1,
    NULL,
    'DRAFT',
    '$publisher_id'::uuid,
    decode(repeat('59', 32), 'hex'),
    1
);

INSERT INTO content.lyric_section (
    section_id,
    lyrics_revision_id,
    section_type,
    label,
    display_order
)
VALUES (
    '$section_id'::uuid,
    '$lyrics_revision_id'::uuid,
    'VERSE',
    'Verso BL059',
    0
);

INSERT INTO content.lyric_line (
    line_id,
    section_id,
    line_no,
    japanese_text,
    normalized_text,
    speaker_label
)
VALUES
(
    '$line_1_id'::uuid,
    '$section_id'::uuid,
    1,
    convert_from(decode('e680aae78da3e381a7e38199', 'hex'), 'UTF8'),
    convert_from(decode('e680aae78da3e381a7e38199', 'hex'), 'UTF8'),
    'voz principal'
),
(
    '$line_2_id'::uuid,
    '$section_id'::uuid,
    2,
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    NULL
);

INSERT INTO content.lyric_token (
    token_id,
    line_id,
    token_no,
    surface,
    normalized_surface,
    start_offset,
    end_offset
)
VALUES
(
    '$token_1_id'::uuid,
    '$line_1_id'::uuid,
    1,
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    0,
    2
),
(
    '$token_2_id'::uuid,
    '$line_1_id'::uuid,
    2,
    convert_from(decode('e381a7e38199', 'hex'), 'UTF8'),
    convert_from(decode('e381a7e38199', 'hex'), 'UTF8'),
    2,
    4
);

INSERT INTO content.timing_revision (
    timing_revision_id,
    lyrics_revision_id,
    source_id,
    revision_no,
    offset_ms,
    status_code,
    checksum
)
VALUES (
    '$timing_revision_id'::uuid,
    '$lyrics_revision_id'::uuid,
    '$source_id'::uuid,
    1,
    100,
    'DRAFT',
    decode(repeat('5a', 32), 'hex')
);

INSERT INTO content.timing_segment (
    segment_id,
    timing_revision_id,
    line_id,
    start_ms,
    end_ms,
    display_order
)
VALUES
(
    uuidv7(),
    '$timing_revision_id'::uuid,
    '$line_1_id'::uuid,
    1000,
    1500,
    0
),
(
    uuidv7(),
    '$timing_revision_id'::uuid,
    '$line_1_id'::uuid,
    1700,
    2200,
    1
),
(
    uuidv7(),
    '$timing_revision_id'::uuid,
    '$line_2_id'::uuid,
    2500,
    4200,
    2
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
VALUES
(
    '$package_lyrics_component_id'::uuid,
    '$package_id'::uuid,
    'LYRICS',
    '$lyrics_revision_id'::uuid,
    NULL,
    NULL,
    NULL,
    NULL,
    decode('$component_checksum', 'hex')
),
(
    '$package_timing_component_id'::uuid,
    '$package_id'::uuid,
    'TIMING',
    NULL,
    '$timing_revision_id'::uuid,
    NULL,
    NULL,
    NULL,
    decode('$component_checksum', 'hex')
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
    decode('$publication_checksum', 'hex')
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

INSERT INTO editorial.publication_component (
    publication_component_id,
    publication_id,
    component_kind,
    source_component_id,
    component_checksum,
    display_order
)
VALUES
(
    '$publication_lyrics_id'::uuid,
    '$publication_id'::uuid,
    'LYRICS',
    '$package_lyrics_component_id'::uuid,
    decode('$component_checksum', 'hex'),
    0
),
(
    '$publication_timing_id'::uuid,
    '$publication_id'::uuid,
    'TIMING',
    '$package_timing_component_id'::uuid,
    decode('$component_checksum', 'hex'),
    1
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
            jsonb_build_object(
                'kind', 'LYRICS',
                'sourceComponentId', '$package_lyrics_component_id',
                'checksum', '$component_checksum',
                'displayOrder', 0
            ),
            jsonb_build_object(
                'kind', 'TIMING',
                'sourceComponentId', '$package_timing_component_id',
                'checksum', '$component_checksum',
                'displayOrder', 1
            )
        )
    ),
    NULL,
    1,
    CURRENT_TIMESTAMP
);

COMMIT;
SQL

eligible_rows="$("${psql_base[@]}" --command="
SELECT count(*)
FROM editorial.published_package_projection AS projection
INNER JOIN editorial.publication AS publication
  ON publication.publication_id = projection.publication_id
 AND publication.recording_id = projection.recording_id
INNER JOIN catalog.recording AS recording
  ON recording.recording_id = publication.recording_id
INNER JOIN catalog.recording_source AS source
  ON source.source_id = NULLIF(projection.component_versions #>> '{source,sourceId}', '')::uuid
 AND source.recording_id = recording.recording_id
INNER JOIN editorial.publication_availability AS availability
  ON availability.publication_id = publication.publication_id
WHERE recording.recording_id = '$recording_id'::uuid
  AND publication.status_code = 'ACTIVE'
  AND publication.active_from <= CURRENT_TIMESTAMP
  AND (publication.active_to IS NULL OR publication.active_to > CURRENT_TIMESTAMP)
  AND availability.territory_code = 'CR'
  AND availability.language_tag = 'es'
  AND availability.audience_code = 'PUBLIC'
  AND availability.status_code = 'ACTIVE'
  AND availability.valid_from <= CURRENT_TIMESTAMP
  AND (availability.valid_to IS NULL OR availability.valid_to > CURRENT_TIMESTAMP)
  AND source.provider_code = 'YOUTUBE'
  AND source.status_code IN ('ACTIVE', 'PUBLISHED')
  AND source.external_ref ~ '^[A-Za-z0-9_-]{11}$';
" | tr -d '[:space:]')"

[[ "$eligible_rows" == "1" ]]   || fail_check "fixture pública BL059 esperaba 1 fila elegible y obtuvo '$eligible_rows'."

if [[ "${BL059_USE_RUNNING_API:-false}" != "true" ]]; then
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
    fail_check "API BL059 no inició dentro del tiempo esperado."
  fi
  sleep 1
done

if [[ "${BL059_USE_RUNNING_API:-false}" != "true" ]]; then
  kill -0 "$api_pid" >/dev/null 2>&1     || fail_check "el proceso API iniciado por BL059 terminó; posible puerto ocupado o fallo de arranque."
fi

route_probe_status="$(curl_request   --output /dev/null   --write-out '%{http_code}'   --get   --data-urlencode "territory=CR"   "$api_url/api/v1/public/catalog/songs/slug-invalido/synchronization")"

[[ "$route_probe_status" == "400" ]]   || fail_check "la ruta BL059 no respondió como endpoint activo; slug inválido esperaba 400 y obtuvo $route_probe_status."

slug_key="$("${psql_base[@]}" --command="SELECT substring(md5('$recording_id'::uuid::text || ':public-song-v1') from 1 for 20);" | tr -d '[:space:]')"
[[ "$slug_key" =~ ^[0-9a-f]{20}$ ]] || fail_check "No se pudo construir slug público sintético."
slug="bl059-$slug_key"

public_detail_status="$(curl_request \
  --output "$work_dir/public-detail.json" \
  --write-out '%{http_code}' \
  --get \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$slug")"

[[ "$public_detail_status" == "200" ]] \
  || fail_check "la fixture BL059 no es una canción pública válida; detalle esperaba 200 y obtuvo $public_detail_status."

result_json="$work_dir/synchronization.json"
synchronization_status="$(curl_request \
  --output "$result_json" \
  --write-out '%{http_code}' \
  --get \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$slug/synchronization")"

if [[ "$synchronization_status" != "200" ]]; then
  echo "--- synchronization response ---" >&2
  cat "$result_json" >&2 || true
  fail_check "sincronización pública esperaba 200 y obtuvo $synchronization_status."
fi

node - "$result_json" <<'NODE' || fail_check "Contrato público BL059 incorrecto."
const fs = require('node:fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

if (data.available !== true) process.exit(1);
if (data.maximumPrecision !== 'TOKEN') process.exit(1);
if (data.offsetMs !== 100) process.exit(1);
if (!Array.isArray(data.lines) || data.lines.length !== 2) process.exit(1);
if (data.lines[0].lineNo !== 1 || data.lines[0].precisionCode !== 'TOKEN') process.exit(1);
if (!Array.isArray(data.lines[0].tokens) || data.lines[0].tokens.length !== 2) process.exit(1);
if (data.lines[0].tokens[0].startMs !== 1000 || data.lines[0].tokens[1].endMs !== 2200) process.exit(1);
if (data.lines[1].lineNo !== 2 || data.lines[1].precisionCode !== 'LINE') process.exit(1);

const forbidden = [];
const visit = (value) => {
  if (Array.isArray(value)) return value.forEach(visit);
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if (/Id$/.test(key) || /checksum/i.test(key) || key === 'externalRef') forbidden.push(key);
    visit(child);
  }
};
visit(data);
if (forbidden.length !== 0) process.exit(1);
NODE

wrong_territory_status="$(curl_request --output /dev/null --write-out '%{http_code}' --get \
  --data-urlencode "territory=US" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$slug/synchronization")"
[[ "$wrong_territory_status" == "404" ]] \
  || fail_check "territorio no autorizado esperaba 404 y obtuvo $wrong_territory_status."

# El mismo paquete sin TIMING sigue siendo elegible, pero el motor debe degradar a NONE.
"${psql_base[@]}" >/dev/null <<SQL
UPDATE editorial.published_package_projection
SET component_versions = jsonb_set(
    component_versions,
    '{components}',
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'LYRICS',
            'sourceComponentId', '$package_lyrics_component_id',
            'checksum', '$component_checksum',
            'displayOrder', 0
        )
    )
)
WHERE publication_id = '$publication_id'::uuid;
SQL

degraded_json="$work_dir/degraded.json"
degraded_status="$(curl_request \
  --output "$degraded_json" \
  --write-out '%{http_code}' \
  --get \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$slug/synchronization")"

[[ "$degraded_status" == "200" ]] \
  || fail_check "degradación sin TIMING esperaba 200 y obtuvo $degraded_status."

node - "$degraded_json" <<'NODE' || fail_check "La degradación sin TIMING no fue segura."
const fs = require('node:fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (data.available !== false) process.exit(1);
if (data.maximumPrecision !== 'NONE') process.exit(1);
if (data.offsetMs !== 0) process.exit(1);
if (!Array.isArray(data.lines) || data.lines.length !== 0) process.exit(1);
NODE

mkdir -p artifacts/postgres
{
  echo "bl=BL-MVP-059"
  echo "public_timing_contract=true"
  echo "exact_published_timing=true"
  echo "package_component_lineage=true"
  echo "canonical_public_song_fixture=true"
  echo "stale_api_guard=true"
  echo "editorial_workspace=side_by_side_sticky"
  echo "line_navigation=true"
  echo "real_player_marking=true"
  echo "auto_advance=true"
  echo "lyrics_compatibility=true"
  echo "binary_search=true"
  echo "playing_poll_interval_ms=100"
  echo "paused_poll_interval_ms=250"
  echo "desync_target_p95_ms=250"
  echo "resync_target_p95_ms=300"
  echo "degrade_levels=TOKEN,LINE,NONE"
  echo "wrong_territory=404"
  echo "public_ids=false"
  echo "data_api=false"
  echo "media_download=false"
  echo "publishes=false"
} > artifacts/postgres/bl-mvp-059-local-synchronization.txt

cat artifacts/postgres/bl-mvp-059-local-synchronization.txt
echo "OK: BL-MVP-059 índice temporal local, contrato publicado exacto, degradación y límites de sincronización verificados."
