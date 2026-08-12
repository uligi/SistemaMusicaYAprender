#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL039_API_URL:-https://localhost:5454}"
work_dir="$(mktemp -d)"
editor_email="bl039-editor-$(openssl rand -hex 10)@example.test"
password="Brisa 日本語 segura 2026"
registration_key="bl039-register-$(openssl rand -hex 16)"
known_credit_key="bl039-credit-known-$(openssl rand -hex 16)"
pending_credit_key="bl039-credit-pending-$(openssl rand -hex 16)"
order_conflict_key="bl039-credit-order-$(openssl rand -hex 16)"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
editor_assignment="$(node -e "console.log(require('node:crypto').randomUUID())")"
artist_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
api_log="$work_dir/api.log"
api_pid=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-039: $1" >&2
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

if [[ "${BL039_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

if [[ "${BL039_USE_RUNNING_API:-false}" != "true" ]]; then
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
    "$api_url/api/v1/editorial/song-drafts/$recording_id/credits"
)"
assert_equal "creditos sin sesion" "$unauth_status" "401"

curl_request --fail --output "$work_dir/consents.json" \
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

node - "$editor_email" "$password" "${notice_versions[0]}" "${notice_versions[1]}" \
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
assert_equal "registro editor sintetico" "$register_status" "202"

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
    'BL-MVP-039 bootstrap tecnico de prueba'
FROM security.account a
CROSS JOIN security.role r
WHERE encode(a.email_lookup_hash, 'hex') = '$email_hash'
  AND r.role_code = 'EDITOR';

INSERT INTO catalog.artist (
    artist_id, canonical_name, sort_name, artist_type, status_code, version
) VALUES (
    '$artist_id'::uuid, 'BL039 synthetic artist', 'BL039 synthetic artist',
    'PERSON', 'ACTIVE', 1
);

INSERT INTO catalog.musical_work (
    work_id, canonical_title, language_tag, release_date, status_code, version
) VALUES (
    '$work_id'::uuid, 'BL039 synthetic work', 'ja', NULL, 'DRAFT', 1
);

INSERT INTO catalog.work_artist (
    work_id, artist_id, role_code, display_order
) VALUES (
    '$work_id'::uuid, '$artist_id'::uuid, 'PRIMARY', 0
);

INSERT INTO catalog.recording (
    recording_id, work_id, recording_title, duration_ms, release_date, status_code, version
) VALUES (
    '$recording_id'::uuid, '$work_id'::uuid, 'BL039 synthetic recording',
    180000, NULL, 'DRAFT', 1
);
" >/dev/null

editor_account_id="$(
  "${psql_base[@]}" --command="
SELECT account_id
FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
" | tr -d '[:space:]'
)"
[[ "$editor_account_id" =~ ^[0-9a-f-]{36}$ ]] \
  || fail_check "No se resolvio la cuenta editorial sintetica."

curl_request --cookie-jar "$work_dir/cookies.txt" \
  --output "$work_dir/csrf-login.json" "$api_url/api/v1/auth/csrf"

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
assert_equal "login editor sintetico" "$login_status" "200"

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

node - "$artist_id" >"$work_dir/known-credit.json" <<'NODE'
const [artistId] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  artistId,
  displayName: 'BL039 credited artist',
  roleCode: 'PERFORMER',
  displayOrder: 0,
  sourceType: 'OFFICIAL_CREDIT',
  citation: 'BL039 official credits',
  locator: 'booklet p. 1',
  verificationCode: 'VERIFIED',
}));
NODE

refresh_csrf "known-credit"
known_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/known-credit-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $known_credit_key" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/known-credit.json" \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/credits"
)"
assert_equal "credito conocido" "$known_status" "201"

mapfile -t known_ids < <(
  node - "$work_dir/known-credit-response.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const key of ['creditId', 'sourceReferenceId', 'provenanceId']) {
  if (typeof value.credit?.[key] !== 'string') process.exit(1);
  process.stdout.write(`${value.credit[key]}\n`);
}
if (value.credit.artistId === null) process.exit(1);
if (value.credit.verificationCode !== 'VERIFIED') process.exit(1);
if (value.credit.displayOrder !== 0) process.exit(1);
NODE
)
credit_id="${known_ids[0]}"
source_reference_id="${known_ids[1]}"
provenance_id="${known_ids[2]}"

refresh_csrf "known-replay"
replay_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/known-replay-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $known_credit_key" \
    --data-binary "@$work_dir/known-credit.json" \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/credits"
)"
assert_equal "replay credito" "$replay_status" "200"

node - "$work_dir/known-replay-response.json" "$credit_id" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.alreadyApplied !== true) process.exit(1);
if (value.credit?.creditId !== process.argv[3]) process.exit(1);
NODE

cat >"$work_dir/pending-credit.json" <<'JSON'
{
  "artistId": null,
  "displayName": "BL039 participante pendiente",
  "roleCode": "LYRICIST",
  "displayOrder": 1,
  "sourceType": "BOOKLET",
  "citation": "BL039 booklet pending identity",
  "locator": null,
  "verificationCode": "PENDING_IDENTITY"
}
JSON

refresh_csrf "pending-credit"
pending_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/pending-credit-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $pending_credit_key" \
    --data-binary "@$work_dir/pending-credit.json" \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/credits"
)"
assert_equal "credito identidad pendiente" "$pending_status" "201"

node - "$work_dir/pending-credit-response.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.credit.artistId !== null) process.exit(1);
if (value.credit.pendingIdentity !== true) process.exit(1);
if (value.credit.verificationCode !== 'PENDING_IDENTITY') process.exit(1);
NODE

cat >"$work_dir/order-conflict.json" <<JSON
{
  "artistId": "$artist_id",
  "displayName": "BL039 order conflict",
  "roleCode": "COMPOSER",
  "displayOrder": 0,
  "sourceType": "OFFICIAL_CREDIT",
  "citation": "conflict",
  "locator": null,
  "verificationCode": "VERIFIED"
}
JSON

refresh_csrf "order-conflict"
order_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/order-conflict-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $order_conflict_key" \
    --data-binary "@$work_dir/order-conflict.json" \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/credits"
)"
assert_equal "orden duplicado" "$order_status" "409"

read_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/credits-response.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/credits"
)"
assert_equal "lectura creditos" "$read_status" "200"

node - "$work_dir/credits-response.json" "$credit_id" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!Array.isArray(value) || value.length !== 2) process.exit(1);
if (value[0].creditId !== process.argv[3] || value[0].displayOrder !== 0) process.exit(1);
if (value[1].verificationCode !== 'PENDING_IDENTITY' || value[1].artistId !== null) process.exit(1);
NODE

db_state="$(
  "${psql_base[@]}" --command="
SELECT
  c.role_code || '|' ||
  c.display_order::text || '|' ||
  CASE WHEN c.artist_id IS NULL THEN 'NULL' ELSE 'KNOWN' END || '|' ||
  sr.source_type || '|' ||
  pr.contribution_type
FROM catalog.recording_credit c
JOIN editorial.provenance_record pr
  ON pr.object_type = 'RECORDING_CREDIT'
 AND pr.object_id = c.credit_id
JOIN catalog.source_reference sr
  ON sr.source_reference_id = pr.source_reference_id
WHERE c.recording_id = '$recording_id'::uuid
ORDER BY c.display_order;
" | tr -d '\r' | sed '/^[[:space:]]*$/d'
)"
expected_state=$'PERFORMER|0|KNOWN|OFFICIAL_CREDIT|CREDIT_VERIFIED\nLYRICIST|1|NULL|BOOKLET|CREDIT_PENDING_IDENTITY'
assert_equal "persistencia creditos/procedencia" "$db_state" "$expected_state"

reference_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM catalog.source_reference
WHERE source_reference_id = '$source_reference_id'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "fuente conservada" "$reference_count" "1"

provenance_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM editorial.provenance_record
WHERE provenance_id = '$provenance_id'::uuid
  AND object_type = 'RECORDING_CREDIT'
  AND object_id = '$credit_id'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "procedencia enlazada" "$provenance_count" "1"

audit_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.audit_event
WHERE object_type = 'RECORDING_CREDIT'
  AND object_id = '$credit_id'::uuid
  AND action_code = 'CATALOG.RECORDING_CREDIT.CREATE'
  AND actor_id = '$editor_account_id'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "auditoria credito" "$audit_count" "1"

echo "OK: BL-MVP-039 roles, orden, fuente, verificacion e identidades pendientes verificados."
