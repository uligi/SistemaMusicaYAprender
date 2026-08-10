#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

mkdir -p artifacts/postgres artifacts/test-results

api_url="${BL027_API_URL:-https://localhost:5080}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
: > "$api_log"

email="bl027-$(openssl rand -hex 12)@example.test"
password="Cierre 日本語 seguro 2026"
registration_key="bl027-$(openssl rand -hex 16)"

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

curl_request() {
  curl "${curl_tls_options[@]}" "$@"
}

fail_check() {
  local message="$1"
  echo "ERROR: BL-MVP-027: $message" >&2
  exit 1
}

assert_equal() {
  local check_name="$1"
  local actual="$2"
  local expected="$3"

  if [[ "$actual" != "$expected" ]]; then
    fail_check "$check_name esperaba '$expected' y obtuvo '$actual'."
  fi
}

assert_contains_ci() {
  local check_name="$1"
  local expected="$2"
  local actual="$3"
  local expected_lower="${expected,,}"
  local actual_lower="${actual,,}"

  if [[ "$actual_lower" != *"$expected_lower"* ]]; then
    fail_check "$check_name no encontro '$expected'."
  fi
}

cookie_header() {
  local headers_path="$1"
  local cookie_name="$2"
  tr -d '\r' < "$headers_path" |
    grep -i "^set-cookie: ${cookie_name}=" |
    head -n 1
}

cookie_pair() {
  local header_line="$1"
  cut -d: -f2- <<<"$header_line" | sed 's/^ *//' | cut -d';' -f1
}

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
if [[ ! "$lookup_key_hex" =~ ^[0-9a-fA-F]{64}$ ]]; then
  fail_check "identity_email_lookup_key no contiene 32 bytes hexadecimales."
fi

email_hash="$({
  printf '%s' "${email^^}" |
    openssl dgst -sha256 -mac HMAC -macopt "hexkey:$lookup_key_hex" -binary |
    od -An -vtx1 |
    tr -d ' \n'
})"

if [[ "${BL027_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

  "${psql_base[@]}" --command="
BEGIN;
DELETE FROM security.session
WHERE account_id IN (
  SELECT account_id FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM ops.job_attempt
WHERE job_id IN (
  SELECT job_id FROM ops.background_job
  WHERE payload->>'aggregateId' IN (
    SELECT account_id::text FROM security.account
    WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
  )
);
DELETE FROM ops.background_job
WHERE payload->>'aggregateId' IN (
  SELECT account_id::text FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM ops.outbox_message
WHERE aggregate_id IN (
  SELECT account_id FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM security.account_verification
WHERE account_id IN (
  SELECT account_id FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
ALTER TABLE identity.consent_record DISABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.consent_record
WHERE account_id IN (
  SELECT account_id FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
ALTER TABLE identity.consent_record ENABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.user_profile
WHERE account_id IN (
  SELECT account_id FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM security.credential
WHERE account_id IN (
  SELECT account_id FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
DELETE FROM ops.idempotency_record
WHERE account_id IS NULL AND idempotency_key = '$registration_key';
COMMIT;
" >/dev/null 2>&1 || true

  rm -rf "$work_dir"
}

trap cleanup EXIT

if [[ "${BL027_USE_RUNNING_API:-false}" != "true" ]]; then
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
  if curl_request --fail --silent "$api_url/health/live" >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    tail -80 "$api_log" >&2
    fail_check "la API no quedo disponible."
  fi
  sleep 1
done

curl_request --fail --silent --show-error \
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
if [[ "${#notice_versions[@]}" -ne 2 ]]; then
  fail_check "la API no publico los avisos requeridos."
fi

node - "$email" "$password" "${notice_versions[0]}" "${notice_versions[1]}" \
  > "$work_dir/registration-request.json" <<'NODE'
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

registration_status="$(curl_request --silent --show-error \
  --output "$work_dir/registration-response.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: $registration_key" \
  --data-binary "@$work_dir/registration-request.json" \
  "$api_url/api/v1/auth/register")"
assert_equal "alta de cuenta" "$registration_status" "202"

"${psql_base[@]}" --command="
UPDATE security.account
SET status_code = 'ACTIVE', verified_at = CURRENT_TIMESTAMP
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
" >/dev/null

account_id="$({
  "${psql_base[@]}" --command="
SELECT account_id FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
"
} | tr -d '[:space:]')"
if [[ ! "$account_id" =~ ^[0-9a-f-]{36}$ ]]; then
  fail_check "no se pudo activar la cuenta sintetica."
fi

node - "$email" "$password" > "$work_dir/login-request.json" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE

csrf_status="$(curl_request --silent --show-error \
  --dump-header "$work_dir/login-csrf-headers.txt" \
  --output "$work_dir/login-csrf.json" \
  --write-out '%{http_code}' \
  "$api_url/api/v1/auth/csrf")"
assert_equal "csrf para login" "$csrf_status" "200"

mapfile -t login_csrf_contract < <(
  node - "$work_dir/login-csrf.json" <<'NODE'
const fs = require('node:fs');
const contract = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (
  typeof contract.requestToken !== 'string' ||
  contract.requestToken.length < 32 ||
  contract.headerName !== 'X-CSRF-TOKEN'
) process.exit(1);
process.stdout.write(`${contract.requestToken}\n${contract.headerName}\n`);
NODE
)
login_csrf_token="${login_csrf_contract[0]}"
csrf_header_name="${login_csrf_contract[1]}"
login_csrf_cookie_header="$(cookie_header "$work_dir/login-csrf-headers.txt" "__Host-MusicaAprender.Csrf")"
login_csrf_cookie_pair="$(cookie_pair "$login_csrf_cookie_header")"

login_a_status="$(curl_request --silent --show-error \
  --dump-header "$work_dir/login-a-headers.txt" \
  --output "$work_dir/login-a.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "$csrf_header_name: $login_csrf_token" \
  --cookie "$login_csrf_cookie_pair" \
  --data-binary "@$work_dir/login-request.json" \
  "$api_url/api/v1/auth/login")"
assert_equal "login A" "$login_a_status" "200"

login_b_status="$(curl_request --silent --show-error \
  --dump-header "$work_dir/login-b-headers.txt" \
  --output "$work_dir/login-b.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "$csrf_header_name: $login_csrf_token" \
  --cookie "$login_csrf_cookie_pair" \
  --data-binary "@$work_dir/login-request.json" \
  "$api_url/api/v1/auth/login")"
assert_equal "login B" "$login_b_status" "200"

session_a_header="$(cookie_header "$work_dir/login-a-headers.txt" "__Host-MusicaAprender.Session")"
session_b_header="$(cookie_header "$work_dir/login-b-headers.txt" "__Host-MusicaAprender.Session")"
session_a_pair="$(cookie_pair "$session_a_header")"
session_b_pair="$(cookie_pair "$session_b_header")"

session_a_status="$(curl_request --silent --show-error \
  --output "$work_dir/session-a.json" --write-out '%{http_code}' \
  --cookie "$session_a_pair" "$api_url/api/v1/auth/session")"
session_b_status="$(curl_request --silent --show-error \
  --output "$work_dir/session-b.json" --write-out '%{http_code}' \
  --cookie "$session_b_pair" "$api_url/api/v1/auth/session")"
assert_equal "sesion A antes de logout" "$session_a_status" "200"
assert_equal "sesion B antes de logout" "$session_b_status" "200"

logout_csrf_status="$(curl_request --silent --show-error \
  --dump-header "$work_dir/logout-csrf-headers.txt" \
  --output "$work_dir/logout-csrf.json" \
  --write-out '%{http_code}' \
  --cookie "$session_a_pair" \
  "$api_url/api/v1/auth/csrf")"
assert_equal "csrf autenticado para logout" "$logout_csrf_status" "200"

mapfile -t logout_csrf_contract < <(
  node - "$work_dir/logout-csrf.json" <<'NODE'
const fs = require('node:fs');
const contract = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (
  typeof contract.requestToken !== 'string' ||
  contract.requestToken.length < 32 ||
  contract.headerName !== 'X-CSRF-TOKEN'
) process.exit(1);
process.stdout.write(`${contract.requestToken}\n${contract.headerName}\n`);
NODE
)
logout_csrf_token="${logout_csrf_contract[0]}"
logout_csrf_cookie_header="$(cookie_header "$work_dir/logout-csrf-headers.txt" "__Host-MusicaAprender.Csrf")"
logout_csrf_cookie_pair="$(cookie_pair "$logout_csrf_cookie_header")"

missing_csrf_status="$(curl_request --silent --show-error \
  --output "$work_dir/logout-missing-csrf.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --cookie "$logout_csrf_cookie_pair; $session_a_pair" \
  --data '{}' \
  "$api_url/api/v1/auth/logout")"
assert_equal "logout sin CSRF" "$missing_csrf_status" "400"

still_active_status="$(curl_request --silent --show-error \
  --output "$work_dir/session-a-after-missing-csrf.json" \
  --write-out '%{http_code}' \
  --cookie "$session_a_pair" \
  "$api_url/api/v1/auth/session")"
assert_equal "CSRF invalido no revoca" "$still_active_status" "200"

logout_status="$(curl_request --silent --show-error \
  --dump-header "$work_dir/logout-headers.txt" \
  --output "$work_dir/logout.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "$csrf_header_name: $logout_csrf_token" \
  --cookie "$logout_csrf_cookie_pair; $session_a_pair" \
  --data '{}' \
  "$api_url/api/v1/auth/logout")"
assert_equal "logout actual" "$logout_status" "200"

node - "$work_dir/logout.json" <<'NODE'
const fs = require('node:fs');
const response = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (response.status !== 'SIGNED_OUT') process.exit(1);
if ('token' in response || 'sessionId' in response || 'accountId' in response) process.exit(1);
NODE

delete_header="$(cookie_header "$work_dir/logout-headers.txt" "__Host-MusicaAprender.Session")"
if [[ -z "$delete_header" ]]; then
  fail_check "logout no retiro la cookie de sesion."
fi
assert_contains_ci "cookie eliminada Path=/" "; path=/" "$delete_header"
assert_contains_ci "cookie eliminada Secure" "; secure" "$delete_header"
assert_contains_ci "cookie eliminada HttpOnly" "; httponly" "$delete_header"
assert_contains_ci "cookie eliminada SameSite=Strict" "; samesite=strict" "$delete_header"
delete_header_lower="${delete_header,,}"
if [[ "$delete_header_lower" != *"expires="* && "$delete_header_lower" != *"max-age=0"* ]]; then
  fail_check "la cookie de sesion no fue invalidada en el cliente."
fi

session_a_after_status="$(curl_request --silent --show-error \
  --output "$work_dir/session-a-after.json" --write-out '%{http_code}' \
  --cookie "$session_a_pair" "$api_url/api/v1/auth/session")"
assert_equal "cookie revocada no autentica" "$session_a_after_status" "401"

session_b_after_status="$(curl_request --silent --show-error \
  --output "$work_dir/session-b-after.json" --write-out '%{http_code}' \
  --cookie "$session_b_pair" "$api_url/api/v1/auth/session")"
assert_equal "otra sesion permanece activa" "$session_b_after_status" "200"

isolation_contract="$({
  "${psql_base[@]}" --command="
SELECT count(*) FILTER (WHERE revoked_at IS NOT NULL) = 1
   AND count(*) FILTER (WHERE revoked_at IS NULL) = 1
FROM security.session
WHERE account_id = '$account_id';
"
} | tr -d '[:space:]')"
assert_equal "revocacion aislada de sesion" "$isolation_contract" "t"

cat > artifacts/postgres/personal-logout-summary.txt <<EOF
bl_mvp=027
endpoint_logout=POST /api/v1/auth/logout
logout_requires_session=authorization
logout_requires_csrf=400-without-token
logout_status=200
logout_response=SIGNED_OUT
revoked_cookie_reuse=401
parallel_session_after_logout=200
server_revocation=current-session-only
session_cookie_removed=client-expiration
EOF

if grep -F -R -q -e "$password" artifacts; then
  fail_check "la contrasena aparecio en evidencia persistente."
fi

echo "OK: BL-MVP-027 logout revoca la sesion actual, retira la cookie y conserva otra sesion independiente."
