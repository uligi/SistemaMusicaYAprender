#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL037_API_URL:-https://localhost:5452}"
work_dir="$(mktemp -d)"
editor_email="bl037-editor-$(openssl rand -hex 10)@example.test"
password="Brisa 日本語 segura 2026"
registration_key="bl037-register-$(openssl rand -hex 16)"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
editor_assignment="$(node -e "console.log(require('node:crypto').randomUUID())")"
artist_name="BL037 試験 $(openssl rand -hex 6)"
artist_sort="BL037 Test $(openssl rand -hex 6)"
artist_romaji="BL037 Artist $(openssl rand -hex 6)"
artist_kana="びーえるさんなな $(openssl rand -hex 4)"
create_key="bl037-create-$(openssl rand -hex 16)"
second_key="bl037-second-$(openssl rand -hex 16)"
api_log="$work_dir/api.log"
api_pid=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-037: $1" >&2
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

if [[ "${BL037_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

if [[ "${BL037_USE_RUNNING_API:-false}" != "true" ]]; then
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
    "$api_url/api/v1/editorial/artists?query=test"
)"
assert_equal "búsqueda sin sesión" "$unauth_status" "401"

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
    'BL-MVP-037 bootstrap técnico de prueba'
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

node - \
  "$artist_name" \
  "$artist_sort" \
  "$artist_kana" \
  "$artist_romaji" \
  >"$work_dir/artist.json" <<'NODE'
const [canonicalName, sortName, kana, romaji] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  canonicalName,
  sortName,
  artistType: 'PROJECT',
  canonicalLanguageTag: 'ja',
  canonicalScriptCode: 'JPAN',
  aliases: [
    {
      aliasText: kana,
      languageTag: 'ja',
      scriptCode: 'HIRA',
      preferred: false,
    },
    {
      aliasText: romaji,
      languageTag: 'ja',
      scriptCode: 'LATN',
      preferred: false,
    },
  ],
  acknowledgePotentialDuplicates: false,
}));
NODE

refresh_csrf "duplicates-empty"
duplicates_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/duplicates-empty.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/artist.json" \
    "$api_url/api/v1/editorial/artists/duplicates"
)"
assert_equal "revisión de duplicados inicial" "$duplicates_status" "200"
node - "$work_dir/duplicates-empty.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.requiresAcknowledgement !== false) process.exit(1);
if (!Array.isArray(value.candidates) || value.candidates.length !== 0) process.exit(1);
NODE

refresh_csrf "create"
create_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/create.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $create_key" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/artist.json" \
    "$api_url/api/v1/editorial/artists"
)"
assert_equal "alta de artista" "$create_status" "201"

artist_id="$(
  node - "$work_dir/create.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.alreadyApplied !== false) process.exit(1);
if (value.statusCode !== 'ACTIVE') process.exit(1);
if (!Array.isArray(value.aliases) || value.aliases.length !== 3) process.exit(1);
process.stdout.write(value.artistId);
NODE
)"
[[ "$artist_id" =~ ^[0-9a-f-]{36}$ ]] \
  || fail_check "La API no devolvió una identidad UUID estable."

refresh_csrf "replay"
replay_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/replay.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $create_key" \
    --data-binary "@$work_dir/artist.json" \
    "$api_url/api/v1/editorial/artists"
)"
assert_equal "reintento idempotente" "$replay_status" "200"

replay_artist_id="$(
  node - "$work_dir/replay.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.alreadyApplied !== true) process.exit(1);
process.stdout.write(value.artistId);
NODE
)"
assert_equal "identidad estable del reintento" "$replay_artist_id" "$artist_id"

refresh_csrf "duplicates-after"
duplicates_after_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/duplicates-after.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/artist.json" \
    "$api_url/api/v1/editorial/artists/duplicates"
)"
assert_equal "advertencia de duplicado" "$duplicates_after_status" "200"
node - "$work_dir/duplicates-after.json" "$artist_id" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const artistId = process.argv[3];
if (value.requiresAcknowledgement !== true) process.exit(1);
if (!value.candidates.some((candidate) => candidate.artistId === artistId)) process.exit(1);
NODE

refresh_csrf "duplicate-block"
duplicate_create_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/duplicate-block.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $second_key" \
    --data-binary "@$work_dir/artist.json" \
    "$api_url/api/v1/editorial/artists"
)"
assert_equal "bloqueo hasta revisar duplicado" "$duplicate_create_status" "409"
node - "$work_dir/duplicate-block.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.code !== 'catalog.artist.duplicate-review-required') process.exit(1);
NODE

search_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/search.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/editorial/artists?query=$(node -e "process.stdout.write(encodeURIComponent(process.argv[1]))" "$artist_romaji")"
)"
assert_equal "búsqueda por romanización" "$search_status" "200"
node - "$work_dir/search.json" "$artist_id" <<'NODE'
const fs = require('node:fs');
const values = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const artistId = process.argv[3];
if (!Array.isArray(values) || !values.some((value) => value.artistId === artistId)) {
  process.exit(1);
}
NODE

artist_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM catalog.artist
WHERE artist_id = '$artist_id'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "una identidad estable" "$artist_count" "1"

alias_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM catalog.artist_alias
WHERE artist_id = '$artist_id'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "nombre canónico + alias/lecturas" "$alias_count" "3"

second_artist_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM catalog.artist
WHERE canonical_name = '$artist_name';
" | tr -d '[:space:]'
)"
assert_equal "duplicado no creado sin confirmación" "$second_artist_count" "1"

audit_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.audit_event
WHERE actor_id = '$editor_account_id'::uuid
  AND object_type = 'ARTIST'
  AND object_id = '$artist_id'::uuid
  AND action_code = 'CATALOG.ARTIST.CREATE'
  AND correlation_id IS NOT NULL;
" | tr -d '[:space:]'
)"
assert_equal "auditoría primaria de creación" "$audit_count" "1"

pk_is_uuid="$(
  "${psql_base[@]}" --command="
SELECT data_type
FROM information_schema.columns
WHERE table_schema = 'catalog'
  AND table_name = 'artist'
  AND column_name = 'artist_id';
" | tr -d '[:space:]'
)"
assert_equal "artist_id opaco UUID" "$pk_is_uuid" "uuid"

mkdir -p artifacts/postgres
cat > artifacts/postgres/artist-administration-summary.txt <<EOF
bl_mvp=037
permission=EDITORIAL.DRAFT
module_scope=M02
stable_artist_id=verified
name_not_key=verified
canonical_alias=verified
kana_and_romaji=verified
duplicate_warning=verified
duplicate_not_auto_merged=verified
idempotent_retry=verified
audit=verified
external_search_calls=0
EOF

echo "OK: BL-MVP-037 identidad estable, alias/lecturas, advertencia de duplicados, idempotencia y auditoría verificados."
