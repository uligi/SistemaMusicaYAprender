#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL038_API_URL:-https://localhost:5453}"
work_dir="$(mktemp -d)"
editor_email="bl038-editor-$(openssl rand -hex 10)@example.test"
password="Brisa 日本語 segura 2026"
registration_key="bl038-register-$(openssl rand -hex 16)"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
editor_assignment="$(node -e "console.log(require('node:crypto').randomUUID())")"
artist_name="BL038 試験 $(openssl rand -hex 6)"
artist_sort="BL038 Test $(openssl rand -hex 6)"
artist_key="bl038-artist-$(openssl rand -hex 16)"
song_key="bl038-song-$(openssl rand -hex 16)"
conflict_key="bl038-conflict-$(openssl rand -hex 16)"
source_conflict_key="bl038-source-conflict-$(openssl rand -hex 16)"
video_id="B38$(openssl rand -hex 4)"
second_video_id="C38$(openssl rand -hex 4)"
api_log="$work_dir/api.log"
api_pid=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-038: $1" >&2
  if [[ -s "$api_log" ]]; then
    tail -n 100 "$api_log" >&2 || true
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

if [[ "${BL038_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

cleanup() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" >/dev/null 2>&1 || true
    wait "$api_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

curl_request() {
  curl "${curl_tls_options[@]}" --silent --show-error "$@"
}

if grep -Eq \
  'HttpClient|youtube\.googleapis|googleapis\.com/youtube|YouTubeData' \
  src/Modules/Catalog/Infrastructure/Administration/SongDraftAdministrationService.cs; then
  fail_check "La administración de BL038 no debe consultar una API externa de YouTube."
fi

if [[ "${BL038_USE_RUNNING_API:-false}" != "true" ]]; then
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

unauth_status="$(
  curl_request \
    --output "$work_dir/unauth.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/editorial/song-drafts/11111111-1111-4111-8111-111111111111"
)"
assert_equal "expediente sin sesión" "$unauth_status" "401"

curl_request \
  --fail \
  --output "$work_dir/consents.json" \
  "$api_url/api/v1/auth/registration-consents"

mapfile -t notice_versions < <(
  node - "$work_dir/consents.json" <<'NODE'
const fs = require('node:fs');
const catalog = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const purpose of ['TERMS_OF_USE', 'PRIVACY_POLICY']) {
  const notice = catalog.notices?.find((candidate) => candidate.purposeCode === purpose);
  if (!notice?.required || typeof notice.noticeVersion !== 'string') process.exit(1);
  process.stdout.write(`${notice.noticeVersion}\n`);
}
NODE
)

node - \
  "$editor_email" \
  "$password" \
  "${notice_versions[0]}" \
  "${notice_versions[1]}" \
  >"$work_dir/register.json" <<'NODE'
const [email, password, terms, privacy] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  email,
  password,
  consents: [
    { purposeCode: 'TERMS_OF_USE', noticeVersion: terms, decision: true },
    { purposeCode: 'PRIVACY_POLICY', noticeVersion: privacy, decision: true },
  ],
}));
NODE

register_status="$(
  curl_request \
    --output "$work_dir/register-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $registration_key" \
    --data-binary "@$work_dir/register.json" \
    "$api_url/api/v1/auth/register"
)"
assert_equal "registro editor sintético" "$register_status" "202"

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
email_hash="$(
  printf '%s' "${editor_email^^}" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$lookup_key_hex" -binary \
    | od -An -vtx1 \
    | tr -d ' \n'
)"

"${psql_base[@]}" --command="
UPDATE security.account
SET status_code = 'ACTIVE',
    verified_at = CURRENT_TIMESTAMP
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';

INSERT INTO security.role_assignment (
    assignment_id,
    account_id,
    role_id,
    scope_id,
    valid_from,
    valid_to,
    reason
)
SELECT
    '$editor_assignment'::uuid,
    a.account_id,
    r.role_id,
    NULL,
    CURRENT_TIMESTAMP - INTERVAL '2 minutes',
    CURRENT_TIMESTAMP + INTERVAL '1 hour',
    'BL-MVP-038 bootstrap técnico de prueba'
FROM security.account a
CROSS JOIN security.role r
WHERE encode(a.email_lookup_hash, 'hex') = '$email_hash'
  AND r.role_code = 'EDITOR';
" >/dev/null

editor_account_id="$(
  "${psql_base[@]}" --command="
SELECT account_id
FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
" | tr -d '[:space:]'
)"
[[ "$editor_account_id" =~ ^[0-9a-f-]{36}$ ]] \
  || fail_check "No se resolvió la cuenta editorial sintética."

curl_request \
  --cookie-jar "$work_dir/cookies.txt" \
  --output "$work_dir/csrf-login.json" \
  "$api_url/api/v1/auth/csrf"

mapfile -t csrf < <(
  node - "$work_dir/csrf-login.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.requestToken || !value.headerName) process.exit(1);
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

node - "$editor_email" "$password" >"$work_dir/login.json" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE

login_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/login-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/login.json" \
    "$api_url/api/v1/auth/login"
)"
assert_equal "login editor sintético" "$login_status" "200"

refresh_csrf() {
  local phase="$1"
  local file="$work_dir/csrf-$phase.json"
  local status

  status="$(
    curl_request \
      --cookie "$work_dir/cookies.txt" \
      --cookie-jar "$work_dir/cookies.txt" \
      --output "$file" \
      --write-out '%{http_code}' \
      "$api_url/api/v1/auth/csrf"
  )"
  assert_equal "CSRF $phase" "$status" "200"

  mapfile -t csrf < <(
    node - "$file" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.requestToken || !value.headerName) process.exit(1);
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
  )
}

node - "$artist_name" "$artist_sort" >"$work_dir/artist.json" <<'NODE'
const [canonicalName, sortName] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  canonicalName,
  sortName,
  artistType: 'PROJECT',
  canonicalLanguageTag: 'ja',
  canonicalScriptCode: 'JPAN',
  aliases: [],
  acknowledgePotentialDuplicates: false,
}));
NODE

refresh_csrf "artist-duplicates"
artist_duplicates_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/artist-duplicates-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/artist.json" \
    "$api_url/api/v1/editorial/artists/duplicates"
)"
assert_equal "duplicados artista" "$artist_duplicates_status" "200"

refresh_csrf "artist-create"
artist_create_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/artist-create-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $artist_key" \
    --data-binary "@$work_dir/artist.json" \
    "$api_url/api/v1/editorial/artists"
)"
assert_equal "alta artista base" "$artist_create_status" "201"

artist_id="$(
  node - "$work_dir/artist-create-response.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.artistId) process.exit(1);
process.stdout.write(value.artistId);
NODE
)"
[[ "$artist_id" =~ ^[0-9a-f-]{36}$ ]] \
  || fail_check "El alta de artista no devolvió UUID."

node - \
  "$artist_id" \
  "$video_id" \
  >"$work_dir/song.json" <<'NODE'
const [artistId, videoId] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  artistId,
  canonicalTitle: 'BL038 怪獣',
  languageTag: 'ja',
  recordingTitle: 'BL038 怪獣 studio',
  recordingDurationMs: 241125,
  youtubeReference: `https://www.youtube.com/watch?v=${videoId}&list=BL038`,
  sourceDurationMs: 245000,
  offsetMs: 2500,
  exactRecordingConfirmed: true,
  acknowledgePotentialDuplicates: false,
}));
NODE

refresh_csrf "song-duplicates"
duplicates_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/song-duplicates-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/song.json" \
    "$api_url/api/v1/editorial/song-drafts/duplicates"
)"
assert_equal "duplicados iniciales de canción" "$duplicates_status" "200"

node - "$work_dir/song-duplicates-response.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.hasExactSourceConflict !== false) process.exit(1);
if (value.requiresAcknowledgement !== false) process.exit(1);
if (!Array.isArray(value.candidates) || value.candidates.length !== 0) process.exit(1);
NODE

refresh_csrf "song-create"
create_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/song-create-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $song_key" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/song.json" \
    "$api_url/api/v1/editorial/song-drafts"
)"
assert_equal "alta obra/grabación/fuente" "$create_status" "201"

mapfile -t created_ids < <(
  node - "$work_dir/song-create-response.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const key of ['workId', 'recordingId', 'sourceId']) {
  if (typeof value[key] !== 'string') process.exit(1);
  process.stdout.write(`${value[key]}\n`);
}
if (value.providerCode !== 'YOUTUBE') process.exit(1);
if (value.statusCode !== 'DRAFT') process.exit(1);
if (value.alreadyApplied !== false) process.exit(1);
NODE
)

work_id="${created_ids[0]}"
recording_id="${created_ids[1]}"
source_id="${created_ids[2]}"

[[ "$work_id" != "$recording_id" && "$recording_id" != "$source_id" && "$work_id" != "$source_id" ]] \
  || fail_check "Obra, grabación y fuente deben conservar UUID distintos."

refresh_csrf "song-replay"
replay_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/song-replay-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $song_key" \
    --data-binary "@$work_dir/song.json" \
    "$api_url/api/v1/editorial/song-drafts"
)"
assert_equal "replay idempotente" "$replay_status" "200"

node - \
  "$work_dir/song-create-response.json" \
  "$work_dir/song-replay-response.json" <<'NODE'
const fs = require('node:fs');
const first = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const replay = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
for (const key of ['workId', 'recordingId', 'sourceId', 'externalRef']) {
  if (first[key] !== replay[key]) process.exit(1);
}
if (replay.alreadyApplied !== true) process.exit(1);
NODE

node - "$work_dir/song.json" >"$work_dir/song-idempotency-conflict.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
value.recordingTitle = 'contenido distinto para la misma clave';
process.stdout.write(JSON.stringify(value));
NODE

refresh_csrf "song-idempotency-conflict"
idempotency_conflict_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/song-idempotency-conflict-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $song_key" \
    --data-binary "@$work_dir/song-idempotency-conflict.json" \
    "$api_url/api/v1/editorial/song-drafts"
)"
assert_equal "conflicto de idempotencia" "$idempotency_conflict_status" "409"

node - "$work_dir/song.json" >"$work_dir/song-invalid-youtube.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
value.youtubeReference = 'https://example.com/watch?v=abcdefghijk';
process.stdout.write(JSON.stringify(value));
NODE

refresh_csrf "invalid-youtube"
invalid_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/song-invalid-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $conflict_key" \
    --data-binary "@$work_dir/song-invalid-youtube.json" \
    "$api_url/api/v1/editorial/song-drafts"
)"
assert_equal "YouTube inválido" "$invalid_status" "400"

node - "$work_dir/song.json" >"$work_dir/song-source-conflict.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
value.canonicalTitle = 'BL038 otra obra';
value.recordingTitle = 'BL038 otra grabación';
value.acknowledgePotentialDuplicates = true;
process.stdout.write(JSON.stringify(value));
NODE

refresh_csrf "source-conflict"
source_conflict_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/song-source-conflict-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $source_conflict_key" \
    --data-binary "@$work_dir/song-source-conflict.json" \
    "$api_url/api/v1/editorial/song-drafts"
)"
assert_equal "fuente exacta duplicada" "$source_conflict_status" "409"

node - \
  "$artist_id" \
  "$second_video_id" \
  >"$work_dir/song-title-duplicate.json" <<'NODE'
const [artistId, videoId] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  artistId,
  canonicalTitle: 'BL038 怪獣',
  languageTag: 'ja',
  recordingTitle: 'BL038 live version',
  recordingDurationMs: 242000,
  youtubeReference: `https://youtu.be/${videoId}`,
  sourceDurationMs: 246000,
  offsetMs: 0,
  exactRecordingConfirmed: true,
  acknowledgePotentialDuplicates: false,
}));
NODE

refresh_csrf "title-duplicate"
title_duplicate_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/song-title-duplicate-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/song-title-duplicate.json" \
    "$api_url/api/v1/editorial/song-drafts/duplicates"
)"
assert_equal "advertencia de título duplicado" "$title_duplicate_status" "200"

node - "$work_dir/song-title-duplicate-response.json" "$recording_id" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const recordingId = process.argv[3];
if (value.hasExactSourceConflict !== false) process.exit(1);
if (value.requiresAcknowledgement !== true) process.exit(1);
if (!value.candidates?.some((candidate) => candidate.recordingId === recordingId)) process.exit(1);
NODE

detail_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/song-detail-response.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/editorial/song-drafts/$recording_id"
)"
assert_equal "expediente UI-MVP-019" "$detail_status" "200"

node - \
  "$work_dir/song-detail-response.json" \
  "$work_id" \
  "$recording_id" \
  "$source_id" \
  "$video_id" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const [workId, recordingId, sourceId, videoId] = process.argv.slice(3);
if (value.workId !== workId) process.exit(1);
if (value.recordingId !== recordingId) process.exit(1);
if (value.sourceId !== sourceId) process.exit(1);
if (value.providerCode !== 'YOUTUBE') process.exit(1);
if (value.externalRef !== videoId) process.exit(1);
if (value.recordingDurationMs !== 241125) process.exit(1);
if (value.sourceDurationMs !== 245000) process.exit(1);
if (value.offsetMs !== 2500) process.exit(1);
if (value.workStatusCode !== 'DRAFT') process.exit(1);
if (value.recordingStatusCode !== 'DRAFT') process.exit(1);
if (value.sourceStatusCode !== 'DRAFT') process.exit(1);
NODE

db_state="$(
  "${psql_base[@]}" --command="
SELECT
    w.status_code || '|' ||
    r.status_code || '|' ||
    rs.status_code || '|' ||
    rs.provider_code || '|' ||
    rs.external_ref || '|' ||
    COALESCE(r.duration_ms::text, '') || '|' ||
    COALESCE(rs.duration_ms::text, '') || '|' ||
    rs.offset_ms::text
FROM catalog.musical_work w
JOIN catalog.recording r
  ON r.work_id = w.work_id
JOIN catalog.recording_source rs
  ON rs.recording_id = r.recording_id
JOIN catalog.work_artist wa
  ON wa.work_id = w.work_id
WHERE w.work_id = '$work_id'::uuid
  AND r.recording_id = '$recording_id'::uuid
  AND rs.source_id = '$source_id'::uuid
  AND wa.artist_id = '$artist_id'::uuid
  AND wa.role_code = 'PRIMARY'
  AND wa.display_order = 0;
" | tr -d '\r' | sed '/^[[:space:]]*$/d'
)"
assert_equal \
  "persistencia separada" \
  "$db_state" \
  "DRAFT|DRAFT|DRAFT|YOUTUBE|$video_id|241125|245000|2500"

work_title_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM catalog.work_title
WHERE work_id = '$work_id'::uuid
  AND title_type = 'ORIGINAL'
  AND preferred = true;
" | tr -d '[:space:]'
)"
assert_equal "título original preferido" "$work_title_count" "1"

audit_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.audit_event
WHERE object_type = 'RECORDING'
  AND object_id = '$recording_id'::uuid
  AND action_code = 'CATALOG.SONG_DRAFT.CREATE'
  AND actor_id = '$editor_account_id'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "auditoría de alta" "$audit_count" "1"

source_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM catalog.recording_source
WHERE external_ref = '$video_id';
" | tr -d '[:space:]'
)"
assert_equal "una sola fuente exacta" "$source_count" "1"

echo "OK: BL-MVP-038 obra, grabación y fuente YouTube separadas; validación local, correspondencia, duplicados, idempotencia y auditoría verificadas."
