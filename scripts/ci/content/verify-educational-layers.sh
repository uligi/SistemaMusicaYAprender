#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL063_API_URL:-https://localhost:5464}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
api_pid=""

publisher_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
source_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
lyrics_revision_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
section_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
line_1_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
line_2_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
token_1_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
token_2_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
token_3_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
token_4_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
translation_revision_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
translation_newer_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
analysis_revision_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
analysis_newer_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
availability_id="$(node -e "console.log(require('node:crypto').randomUUID())")"

package_lyrics_component_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_translation_component_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
package_analysis_component_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_lyrics_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_translation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
publication_analysis_id="$(node -e "console.log(require('node:crypto').randomUUID())")"

external_ref="BL063vid001"
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

if [[ "${BL063_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-063: $1" >&2
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

DELETE FROM content.token_reading
WHERE analysis_revision_id IN (
  '$analysis_revision_id'::uuid,
  '$analysis_newer_id'::uuid
);
DELETE FROM content.linguistic_analysis_revision
WHERE analysis_revision_id IN (
  '$analysis_revision_id'::uuid,
  '$analysis_newer_id'::uuid
);
DELETE FROM content.translation_line
WHERE translation_revision_id IN (
  '$translation_revision_id'::uuid,
  '$translation_newer_id'::uuid
);
DELETE FROM content.translation_revision
WHERE translation_revision_id IN (
  '$translation_revision_id'::uuid,
  '$translation_newer_id'::uuid
);

DELETE FROM content.lyric_token
WHERE line_id IN ('$line_1_id'::uuid, '$line_2_id'::uuid);
DELETE FROM content.lyric_line
WHERE section_id = '$section_id'::uuid;
DELETE FROM content.lyric_section
WHERE section_id = '$section_id'::uuid;
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

endpoint="apps/api/Endpoints/PublicCatalog/PublicSongLearningLayersEndpoints.cs"
service="src/Modules/Content/Infrastructure/PublicPlayback/PublicSongLearningLayersService.cs"
page="apps/web/src/routes/student/EducationalPlayerPage.tsx"
karaoke="apps/web/src/routes/student/EducationalKaraoke.tsx"
test_file="tests/E2ETests/educational-karaoke-layers.spec.ts"

for file in "$endpoint" "$service" "$page" "$karaoke" "$test_file"; do
  [[ -f "$file" ]] || fail_check "falta $file"
done

grep -Fq '/api/v1/public/catalog/songs/{slug}/layers' "$endpoint" \
  || fail_check "falta contrato público de capas."
grep -Fq "PublicSongLearningLayersService" "$endpoint" \
  || fail_check "el endpoint no usa el read model de capas."

for kind in LYRICS TRANSLATION ANALYSIS; do
  grep -Fq "component_kind = '$kind'" "$service" \
    || fail_check "la lectura publicada no fija componente $kind."
done

grep -Fq "editorial.publication_component" "$service" \
  || fail_check "las capas no revalidan componentes realmente publicados."
grep -Fq "content.translation_revision" "$service" \
  || fail_check "falta compatibilidad de revisión de traducción."
grep -Fq "content.linguistic_analysis_revision" "$service" \
  || fail_check "falta compatibilidad de revisión de análisis."
grep -Fq "section.lyrics_revision_id = @lyrics_revision_id" "$service" \
  || fail_check "la lectura no está anclada a la revisión japonesa exacta."

grep -Fq 'label="Japonés"' "$karaoke" \
  && grep -Fq 'label="Furigana"' "$karaoke" \
  && grep -Fq 'label="Romaji"' "$karaoke" \
  && grep -Fq 'label="Español"' "$karaoke" \
  || fail_check "faltan los cuatro controles de capas P0."

grep -Fq 'aria-pressed={pressed}' "$karaoke" \
  || fail_check "las capas no exponen estado programático."
grep -Fq '<ruby' "$karaoke" && grep -Fq '<rt>' "$karaoke" \
  || fail_check "furigana no usa semántica ruby/rt."
grep -Fq 'lang="ja"' "$karaoke" \
  || fail_check "el japonés no declara lang=ja."
grep -Fq "romanizeApprovedReading" "$karaoke" \
  || fail_check "romaji no reutiliza el resolver local aprobado."
grep -Fq "NATURAL" "$karaoke" && grep -Fq "LITERAL" "$karaoke" \
  || fail_check "la capa española no conserva respaldo natural/literal."
grep -Fq "las capas cambian sin reiniciar el reproductor" "$test_file" \
  || fail_check "falta E2E de cambio de capa sin reinicio."

if grep -Eiq 'HttpClient|https?://|fetch\(|XMLHttpRequest|axios|openai|anthropic|gemini|deepl|google[[:space:]_-]*translate|dictionaryapi|jisho' "$service" "$karaoke"; then
  fail_check "BL063 contiene una dependencia lingüística externa no autorizada."
fi

cleanup_rows

if [[ "${BL063_SKIP_ACCESS_PREP:-false}" != "true" \
      && "${BL063_USE_DOCKER_PSQL:-false}" != "true" ]]; then
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
    'BL063 published layers work',
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
    'BL063 published layers recording',
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
    decode(repeat('63', 32), 'hex'),
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
    'Verso BL063',
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
),
(
    '$token_3_id'::uuid,
    '$line_2_id'::uuid,
    1,
    convert_from(decode('e4bd95e5baa6', 'hex'), 'UTF8'),
    convert_from(decode('e4bd95e5baa6', 'hex'), 'UTF8'),
    0,
    2
),
(
    '$token_4_id'::uuid,
    '$line_2_id'::uuid,
    2,
    convert_from(decode('e381a7e38282', 'hex'), 'UTF8'),
    convert_from(decode('e381a7e38282', 'hex'), 'UTF8'),
    2,
    4
);

INSERT INTO content.translation_revision (
    translation_revision_id,
    lyrics_revision_id,
    target_language,
    translation_type,
    revision_no,
    parent_revision_id,
    status_code,
    checksum
)
VALUES
(
    '$translation_revision_id'::uuid,
    '$lyrics_revision_id'::uuid,
    'es',
    'HUMAN',
    1,
    NULL,
    'DRAFT',
    decode(repeat('64', 32), 'hex')
),
(
    '$translation_newer_id'::uuid,
    '$lyrics_revision_id'::uuid,
    'es',
    'HUMAN',
    2,
    '$translation_revision_id'::uuid,
    'DRAFT',
    decode(repeat('65', 32), 'hex')
);

INSERT INTO content.translation_line (
    translation_line_id,
    translation_revision_id,
    line_id,
    translated_text,
    variant_code,
    display_order
)
VALUES
(
    uuidv7(),
    '$translation_revision_id'::uuid,
    '$line_1_id'::uuid,
    'Soy un monstruo.',
    'NATURAL',
    0
),
(
    uuidv7(),
    '$translation_revision_id'::uuid,
    '$line_1_id'::uuid,
    'Es un monstruo.',
    'LITERAL',
    1
),
(
    uuidv7(),
    '$translation_revision_id'::uuid,
    '$line_2_id'::uuid,
    'Una y otra vez.',
    'NATURAL',
    2
),
(
    uuidv7(),
    '$translation_newer_id'::uuid,
    '$line_1_id'::uuid,
    'NO PUBLICAR BL063',
    'NATURAL',
    0
);

INSERT INTO content.linguistic_analysis_revision (
    analysis_revision_id,
    lyrics_revision_id,
    revision_no,
    parent_revision_id,
    status_code,
    checksum
)
VALUES
(
    '$analysis_revision_id'::uuid,
    '$lyrics_revision_id'::uuid,
    1,
    NULL,
    'DRAFT',
    decode(repeat('66', 32), 'hex')
),
(
    '$analysis_newer_id'::uuid,
    '$lyrics_revision_id'::uuid,
    2,
    '$analysis_revision_id'::uuid,
    'DRAFT',
    decode(repeat('67', 32), 'hex')
);

INSERT INTO content.token_reading (
    token_reading_id,
    analysis_revision_id,
    token_id,
    reading_kana,
    furigana,
    romaji,
    reading_type
)
VALUES
(
    uuidv7(),
    '$analysis_revision_id'::uuid,
    '$token_1_id'::uuid,
    convert_from(decode('e3818be38184e38198e38285e38186', 'hex'), 'UTF8'),
    convert_from(decode('e3818be38184e38198e38285e38186', 'hex'), 'UTF8'),
    'kaijū',
    'CONTEXTUAL'
),
(
    uuidv7(),
    '$analysis_revision_id'::uuid,
    '$token_2_id'::uuid,
    convert_from(decode('e381a7e38199', 'hex'), 'UTF8'),
    NULL,
    'desu',
    'CONTEXTUAL'
),
(
    uuidv7(),
    '$analysis_revision_id'::uuid,
    '$token_3_id'::uuid,
    convert_from(decode('e381aae38293e381a9', 'hex'), 'UTF8'),
    convert_from(decode('e381aae38293e381a9', 'hex'), 'UTF8'),
    'nando',
    'CONTEXTUAL'
),
(
    uuidv7(),
    '$analysis_revision_id'::uuid,
    '$token_4_id'::uuid,
    convert_from(decode('e381a7e38282', 'hex'), 'UTF8'),
    NULL,
    'demo',
    'CONTEXTUAL'
),
(
    uuidv7(),
    '$analysis_newer_id'::uuid,
    '$token_1_id'::uuid,
    convert_from(decode('e381b5e381a4e38186', 'hex'), 'UTF8'),
    NULL,
    'futsū',
    'CONTEXTUAL'
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
    '$package_translation_component_id'::uuid,
    '$package_id'::uuid,
    'TRANSLATION',
    NULL,
    NULL,
    '$translation_revision_id'::uuid,
    NULL,
    NULL,
    decode('$component_checksum', 'hex')
),
(
    '$package_analysis_component_id'::uuid,
    '$package_id'::uuid,
    'ANALYSIS',
    NULL,
    NULL,
    NULL,
    '$analysis_revision_id'::uuid,
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
    '$publication_translation_id'::uuid,
    '$publication_id'::uuid,
    'TRANSLATION',
    '$package_translation_component_id'::uuid,
    decode('$component_checksum', 'hex'),
    1
),
(
    '$publication_analysis_id'::uuid,
    '$publication_id'::uuid,
    'ANALYSIS',
    '$package_analysis_component_id'::uuid,
    decode('$component_checksum', 'hex'),
    2
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
                'kind', 'TRANSLATION',
                'sourceComponentId', '$package_translation_component_id',
                'checksum', '$component_checksum',
                'displayOrder', 1
            ),
            jsonb_build_object(
                'kind', 'ANALYSIS',
                'sourceComponentId', '$package_analysis_component_id',
                'checksum', '$component_checksum',
                'displayOrder', 2
            )
        )
    ),
    NULL,
    1,
    CURRENT_TIMESTAMP
);

COMMIT;
SQL

if [[ "${BL063_USE_RUNNING_API:-false}" != "true" ]]; then
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
    fail_check "API BL063 no inició dentro del tiempo esperado."
  fi
  sleep 1
done

if [[ "${BL063_USE_RUNNING_API:-false}" != "true" ]]; then
  kill -0 "$api_pid" >/dev/null 2>&1 \
    || fail_check "el proceso API BL063 terminó; posible puerto ocupado o fallo de arranque."
fi

slug_key="$("${psql_base[@]}" --command="
SELECT substring(md5('$recording_id'::uuid::text || ':public-song-v1') from 1 for 20);
" | tr -d '[:space:]')"
[[ "$slug_key" =~ ^[0-9a-f]{20}$ ]] \
  || fail_check "No se pudo construir slug público sintético."
slug="bl063-$slug_key"

result_json="$work_dir/layers.json"
layers_status="$(curl_request \
  --output "$result_json" \
  --write-out '%{http_code}' \
  --get \
  --data-urlencode "territory=CR" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$slug/layers")"

if [[ "$layers_status" != "200" ]]; then
  echo "--- layers response ---" >&2
  cat "$result_json" >&2 || true
  fail_check "capas públicas esperaban 200 y obtuvieron $layers_status."
fi

node - "$result_json" <<'NODE' \
  || fail_check "Contrato público BL063 incorrecto o mezcló revisiones no publicadas."
const fs = require('node:fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

if (data.available !== true) process.exit(1);
if (data.targetLanguage.toLowerCase() !== 'es') process.exit(1);
if (data.hasFurigana !== true || data.hasRomaji !== true || data.hasSpanish !== true) process.exit(1);
if (!Array.isArray(data.lines) || data.lines.length !== 2) process.exit(1);

const first = data.lines[0];
if (first.japaneseText !== '怪獣です') process.exit(1);
if (!Array.isArray(first.tokens) || first.tokens.length !== 2) process.exit(1);
if (first.tokens[0].surface !== '怪獣') process.exit(1);
if (first.tokens[0].startOffset !== 0 || first.tokens[0].endOffset !== 2) process.exit(1);
if (first.tokens[0].readings?.[0]?.readingKana !== 'かいじゅう') process.exit(1);
if (first.tokens[0].readings?.[0]?.romaji !== 'kaijū') process.exit(1);

const natural = first.translations.find((item) => item.variantCode === 'NATURAL');
const literal = first.translations.find((item) => item.variantCode === 'LITERAL');
if (natural?.translatedText !== 'Soy un monstruo.') process.exit(1);
if (literal?.translatedText !== 'Es un monstruo.') process.exit(1);

const serialized = JSON.stringify(data);
if (serialized.includes('NO PUBLICAR BL063')) process.exit(1);
if (serialized.includes('futsū')) process.exit(1);

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

wrong_territory_status="$(curl_request \
  --output /dev/null \
  --write-out '%{http_code}' \
  --get \
  --data-urlencode "territory=US" \
  --data-urlencode "language=es" \
  "$api_url/api/v1/public/catalog/songs/$slug/layers")"
[[ "$wrong_territory_status" == "404" ]] \
  || fail_check "territorio no autorizado esperaba 404 y obtuvo $wrong_territory_status."

mkdir -p artifacts/postgres
{
  echo "BL-MVP-063 real PostgreSQL/API smoke"
  echo "recording_id=$recording_id"
  echo "published_translation_revision=$translation_revision_id"
  echo "unpublished_translation_revision=$translation_newer_id"
  echo "published_analysis_revision=$analysis_revision_id"
  echo "unpublished_analysis_revision=$analysis_newer_id"
  echo "layers_status=$layers_status"
  echo "wrong_territory_status=$wrong_territory_status"
  echo "exact_published_revision=true"
  echo "unpublished_newer_revision_excluded=true"
  echo "raw_ids_exposed=false"
} > artifacts/postgres/bl-mvp-063-public-learning-layers.txt

echo "bl=BL-MVP-063"
echo "ui=UI-MVP-009"
echo "layers=japanese,furigana,romaji,spanish"
echo "japanese_lang=true"
echo "ruby_rt=true"
echo "romaji_separate=true"
echo "toggle_restarts_playback=false"
echo "published_revision_compatibility=true"
echo "real_postgresql_api_smoke=true"
echo "external_linguistic_api=false"
echo "OK: BL-MVP-063 capas publicadas exactas y controles de presentación verificados."
