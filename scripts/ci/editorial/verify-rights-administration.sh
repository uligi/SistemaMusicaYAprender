#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL040_API_URL:-https://localhost:5455}"
work_dir="$(mktemp -d)"
editor_email="bl040-editor-$(openssl rand -hex 10)@example.test"
password="Brisa 日本語 segura 2026"
registration_key="bl040-register-$(openssl rand -hex 16)"
rights_key="bl040-rights-$(openssl rand -hex 16)"
replacement_key="bl040-rights-replacement-$(openssl rand -hex 16)"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
editor_assignment="$(node -e "console.log(require('node:crypto').randomUUID())")"
artist_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
work_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recording_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
credit_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
source_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
provenance_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
api_log="$work_dir/api.log"
api_pid=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-040: $1" >&2
  if [[ -s "$api_log" ]]; then
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

if [[ "${BL040_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

docker compose up --detach object-store >/dev/null
for attempt in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:9000/minio/health/ready >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    fail_check "Object store no disponible."
  fi
  sleep 1
done

if [[ "${BL040_USE_RUNNING_API:-false}" != "true" ]]; then
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
    "$api_url/api/v1/editorial/song-drafts/$recording_id/rights"
)"
assert_equal "derechos sin sesion" "$unauth_status" "401"

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
    assignment_id, account_id, role_id, scope_id, valid_from, valid_to, reason
)
SELECT
    '$editor_assignment'::uuid,
    a.account_id,
    r.role_id,
    NULL,
    CURRENT_TIMESTAMP - INTERVAL '2 minutes',
    CURRENT_TIMESTAMP + INTERVAL '1 hour',
    'BL-MVP-040 bootstrap tecnico de prueba'
FROM security.account a
CROSS JOIN security.role r
WHERE encode(a.email_lookup_hash, 'hex') = '$email_hash'
  AND r.role_code = 'EDITOR';

INSERT INTO catalog.artist (
    artist_id, canonical_name, sort_name, artist_type, status_code, version
) VALUES (
    '$artist_id'::uuid, 'BL040 synthetic artist', 'BL040 synthetic artist',
    'PERSON', 'ACTIVE', 1
);

INSERT INTO catalog.musical_work (
    work_id, canonical_title, language_tag, release_date, status_code, version
) VALUES (
    '$work_id'::uuid, 'BL040 synthetic work', 'ja', NULL, 'DRAFT', 1
);

INSERT INTO catalog.work_artist (
    work_id, artist_id, role_code, display_order
) VALUES (
    '$work_id'::uuid, '$artist_id'::uuid, 'PRIMARY', 0
);

INSERT INTO catalog.recording (
    recording_id, work_id, recording_title, duration_ms, release_date, status_code, version
) VALUES (
    '$recording_id'::uuid, '$work_id'::uuid, 'BL040 synthetic recording',
    180000, NULL, 'DRAFT', 1
);

INSERT INTO catalog.recording_credit (
    credit_id, recording_id, artist_id, display_name, role_code, display_order
) VALUES (
    '$credit_id'::uuid, '$recording_id'::uuid, '$artist_id'::uuid,
    'BL040 synthetic artist', 'PERFORMER', 0
);

INSERT INTO catalog.source_reference (
    source_reference_id, source_type, citation, locator, retrieved_at
) VALUES (
    '$source_id'::uuid, 'OFFICIAL_CREDIT',
    'BL040 synthetic provenance', NULL, CURRENT_TIMESTAMP
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

"${psql_base[@]}" --command="
INSERT INTO editorial.provenance_record (
    provenance_id, object_type, object_id, source_reference_id,
    contribution_type, recorded_by, recorded_at
) VALUES (
    '$provenance_id'::uuid, 'RECORDING_CREDIT', '$credit_id'::uuid,
    '$source_id'::uuid, 'CREDIT_VERIFIED', '$editor_account_id'::uuid,
    CURRENT_TIMESTAMP
);
" >/dev/null

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

evidence_b64="$(printf '%s' 'BL040 evidence authorization contract' | base64 | tr -d '\r\n')"

node - "$evidence_b64" >"$work_dir/rights.json" <<'NODE'
const [evidence] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  holderType: 'ORGANIZATION',
  holderDisplayName: 'BL040 rights holder',
  basisCode: 'AUTHORIZATION',
  validFrom: '2026-08-01T00:00:00Z',
  validTo: '2027-08-01T00:00:00Z',
  evidenceFileName: 'authorization.txt',
  evidenceMediaType: 'text/plain',
  evidenceBase64: evidence,
  scopes: [{
    territoryCode: 'CR',
    languageTag: 'es',
    channelCode: 'WEB',
    useCode: 'DISPLAY',
  }],
  reason: 'BL040 synthetic rights verification',
  supersedesRightsRecordId: null,
}));
NODE

refresh_csrf "rights-create"
create_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/rights-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $rights_key" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/rights.json" \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/rights"
)"
assert_equal "alta derechos" "$create_status" "201"

rights_id="$(
  node - "$work_dir/rights-response.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.rights?.rightsRecordId) process.exit(1);
if (value.rights.statusCode !== 'ACTIVE') process.exit(1);
if (value.rights.scopes?.[0]?.territoryCode !== 'CR') process.exit(1);
if (!value.rights.evidenceObjectId) process.exit(1);
process.stdout.write(value.rights.rightsRecordId);
NODE
)"

refresh_csrf "rights-replay"
replay_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/replay.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $rights_key" \
    --data-binary "@$work_dir/rights.json" \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/rights"
)"
assert_equal "replay derechos" "$replay_status" "200"

node - "$work_dir/replay.json" "$rights_id" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.alreadyApplied !== true) process.exit(1);
if (value.rights?.rightsRecordId !== process.argv[3]) process.exit(1);
NODE

allowed_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/allowed.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/rights/evaluate?territoryCode=CR&languageTag=es&channelCode=WEB&useCode=DISPLAY"
)"
assert_equal "evaluacion autorizada" "$allowed_status" "200"

node - "$work_dir/allowed.json" "$rights_id" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.allowed !== true || value.code !== 'ALLOWED') process.exit(1);
if (value.rightsRecordId !== process.argv[3]) process.exit(1);
NODE

blocked_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/blocked.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/rights/evaluate?territoryCode=JP&languageTag=es&channelCode=WEB&useCode=DISPLAY"
)"
assert_equal "restriccion territorial" "$blocked_status" "200"

node - "$work_dir/blocked.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.allowed !== false) process.exit(1);
if (value.code !== 'TERRITORY_OR_USE_NOT_AUTHORIZED') process.exit(1);
NODE

node - "$evidence_b64" "$rights_id" >"$work_dir/replacement.json" <<'NODE'
const [evidence, supersedes] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  holderType: 'ORGANIZATION',
  holderDisplayName: 'BL040 rights holder corrected',
  basisCode: 'AUTHORIZATION',
  validFrom: '2026-08-01T00:00:00Z',
  validTo: '2028-08-01T00:00:00Z',
  evidenceFileName: 'authorization-corrected.txt',
  evidenceMediaType: 'text/plain',
  evidenceBase64: evidence,
  scopes: [{
    territoryCode: 'CR',
    languageTag: 'es',
    channelCode: 'WEB',
    useCode: 'DISPLAY',
  }],
  reason: 'BL040 correction without deleting history',
  supersedesRightsRecordId: supersedes,
}));
NODE

refresh_csrf "rights-replace"
replacement_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/replacement-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: $replacement_key" \
    --data-binary "@$work_dir/replacement.json" \
    "$api_url/api/v1/editorial/song-drafts/$recording_id/rights"
)"
assert_equal "sustitucion versionada" "$replacement_status" "201"

history_state="$(
  "${psql_base[@]}" --command="
SELECT status_code
FROM editorial.rights_record
WHERE object_type = 'RECORDING'
  AND object_id = '$recording_id'::uuid
ORDER BY status_code;
" | tr -d '\r' | sed '/^[[:space:]]*$/d'
)"
expected_history=$'ACTIVE\nSUPERSEDED'
assert_equal "historial de derechos" "$history_state" "$expected_history"

evidence_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM ops.stored_object e
JOIN editorial.rights_record r
  ON r.evidence_object_id = e.object_id
WHERE r.object_type = 'RECORDING'
  AND r.object_id = '$recording_id'::uuid
  AND e.owner_module = 'M15'
  AND e.purpose_code = 'RIGHTS_EVIDENCE'
  AND e.status_code = 'ACTIVE';
" | tr -d '[:space:]'
)"
assert_equal "evidencia privada persistida" "$evidence_count" "2"

audit_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.audit_event
WHERE object_type = 'RIGHTS_RECORD'
  AND action_code IN ('EDITORIAL.RIGHTS.CREATE', 'EDITORIAL.RIGHTS.REPLACE')
  AND actor_id = '$editor_account_id'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "auditoria derechos" "$audit_count" "2"

echo "OK: BL-MVP-040 alcance, evidencia, territorio, vigencia, idempotencia, sustitucion y auditoria verificados."
