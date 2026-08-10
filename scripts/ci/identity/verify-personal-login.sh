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

api_url="${BL026_API_URL:-https://localhost:5080}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
: > "$api_log"
email="bl026-$(openssl rand -hex 12)@example.test"
unknown_email="unknown-$email"
password="Brisa 日本語 segura 2026"
wrong_password="Brisa 日本語 incorrecta 2026"
registration_key="bl026-$(openssl rand -hex 16)"

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
  echo "ERROR: BL-MVP-026: $message" >&2
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

assert_cookie_contract() {
  local cookie_name="$1"
  local header_line="$2"

  assert_contains_ci "$cookie_name usa Path=/" "; path=/" "$header_line"
  assert_contains_ci "$cookie_name usa Secure" "; secure" "$header_line"
  assert_contains_ci "$cookie_name usa HttpOnly" "; httponly" "$header_line"
  assert_contains_ci "$cookie_name usa SameSite=Strict" "; samesite=strict" "$header_line"

  local header_lower="${header_line,,}"
  if [[ "$header_lower" == *"; domain="* ]]; then
    fail_check "$cookie_name no puede incluir Domain con el prefijo __Host-."
  fi
}

problem_fingerprint() {
  local response_path="$1"

  node - "$response_path" <<'NODE'
const fs = require('node:fs');
const problem = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const fields = [problem.status, problem.title, problem.detail, problem.code];
if (
  problem.status !== 401 ||
  problem.code !== 'identity.login.failed' ||
  fields.some((value) => value === undefined || value === null)
) {
  process.exit(1);
}
process.stdout.write(fields.join('|'));
NODE
}

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
if [[ ! "$lookup_key_hex" =~ ^[0-9a-fA-F]{64}$ ]]; then
  fail_check "identity_email_lookup_key no contiene 32 bytes hexadecimales."
fi

email_hash="$({ printf '%s' "${email^^}" \
  | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$lookup_key_hex" -binary \
  | od -An -vtx1 \
  | tr -d ' \n'; })"

if [[ "${BL026_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM ops.job_attempt
WHERE job_id IN (
  SELECT job_id
  FROM ops.background_job
  WHERE payload->>'aggregateId' IN (
    SELECT account_id::text
    FROM security.account
    WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
  )
);
DELETE FROM ops.background_job
WHERE payload->>'aggregateId' IN (
  SELECT account_id::text
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM ops.outbox_message
WHERE aggregate_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM security.account_verification
WHERE account_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
ALTER TABLE identity.consent_record DISABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.consent_record
WHERE account_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
ALTER TABLE identity.consent_record ENABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.user_profile
WHERE account_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM security.credential
WHERE account_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
);
DELETE FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
DELETE FROM ops.idempotency_record
WHERE account_id IS NULL
  AND idempotency_key = '$registration_key';
COMMIT;
" >/dev/null 2>&1 || true

  rm -rf "$work_dir"
}

trap cleanup EXIT

function_contract="$({
  "${psql_base[@]}" --command="
WITH protected_function(function_id) AS (
  SELECT unnest(ARRAY[
    to_regprocedure('security.resolve_active_password_credential(bytea)'),
    to_regprocedure('security.resolve_active_session(bytea)'),
    to_regprocedure('security.revoke_active_session(bytea)')
  ])
)
SELECT count(*) = 3
   AND bool_and(function_id IS NOT NULL)
   AND bool_and(has_function_privilege('jp_app', function_id, 'EXECUTE'))
   AND bool_and(NOT has_function_privilege('jp_readonly', function_id, 'EXECUTE'))
FROM protected_function;
"
} | tr -d '[:space:]')"
assert_equal "funciones de acceso minimo" "$function_contract" "t"

if [[ "${BL026_USE_RUNNING_API:-false}" != "true" ]]; then
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

curl_request \
  --fail \
  --silent \
  --show-error \
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
  fail_check "la API no publico los avisos requeridos para crear la cuenta de prueba."
fi

node - \
  "$email" \
  "$password" \
  "${notice_versions[0]}" \
  "${notice_versions[1]}" \
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

registration_status="$(curl_request \
  --silent \
  --show-error \
  --output "$work_dir/registration-response.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: $registration_key" \
  --data-binary "@$work_dir/registration-request.json" \
  "$api_url/api/v1/auth/register")"
assert_equal "alta de cuenta para el smoke" "$registration_status" "202"

"${psql_base[@]}" --command="
UPDATE security.account
SET status_code = 'ACTIVE',
    verified_at = CURRENT_TIMESTAMP
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
" >/dev/null

account_id="$({
  "${psql_base[@]}" --command="
SELECT account_id
FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
"
} | tr -d '[:space:]')"

if [[ ! "$account_id" =~ ^[0-9a-f-]{36}$ ]]; then
  fail_check "no se pudo activar de forma determinista la cuenta de prueba."
fi

node - "$email" "$password" > "$work_dir/login-request.json" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE

csrf_status="$(curl_request \
  --silent \
  --show-error \
  --dump-header "$work_dir/csrf-headers.txt" \
  --output "$work_dir/csrf.json" \
  --write-out '%{http_code}' \
  "$api_url/api/v1/auth/csrf")"
assert_equal "emision antifalsificacion" "$csrf_status" "200"

mapfile -t csrf_contract < <(
  node - "$work_dir/csrf.json" <<'NODE'
const fs = require('node:fs');
const contract = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (
  typeof contract.requestToken !== 'string' ||
  contract.requestToken.length < 32 ||
  contract.headerName !== 'X-CSRF-TOKEN'
) {
  process.exit(1);
}
process.stdout.write(`${contract.requestToken}\n${contract.headerName}\n`);
NODE
)

if [[ "${#csrf_contract[@]}" -ne 2 ]]; then
  fail_check "el contrato antifalsificacion no fue valido."
fi

csrf_token="${csrf_contract[0]}"
csrf_header_name="${csrf_contract[1]}"
csrf_cookie_header="$(tr -d '\r' < "$work_dir/csrf-headers.txt" \
  | grep -i '^set-cookie: __Host-MusicaAprender.Csrf=' \
  | head -n 1)"
if [[ -z "$csrf_cookie_header" ]]; then
  fail_check "la respuesta no emitio la cookie antifalsificacion __Host-."
fi
assert_cookie_contract "cookie antifalsificacion" "$csrf_cookie_header"
csrf_cookie_pair="$(cut -d: -f2- <<<"$csrf_cookie_header" | sed 's/^ *//' | cut -d';' -f1)"

missing_csrf_status="$(curl_request \
  --silent \
  --show-error \
  --output "$work_dir/missing-csrf.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --cookie "$csrf_cookie_pair" \
  --data-binary "@$work_dir/login-request.json" \
  "$api_url/api/v1/auth/login")"
assert_equal "login mutable sin CSRF" "$missing_csrf_status" "400"

login_status="$(curl_request \
  --silent \
  --show-error \
  --dump-header "$work_dir/login-headers.txt" \
  --output "$work_dir/login-response.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "$csrf_header_name: $csrf_token" \
  --cookie "$csrf_cookie_pair" \
  --data-binary "@$work_dir/login-request.json" \
  "$api_url/api/v1/auth/login")"
assert_equal "credencial valida" "$login_status" "200"

node - "$work_dir/login-response.json" <<'NODE'
const fs = require('node:fs');
const response = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (response.status !== 'AUTHENTICATED' || response.role !== 'STUDENT') process.exit(1);
if ('token' in response || 'sessionId' in response || 'accountId' in response) process.exit(1);
NODE

session_cookie_header="$(tr -d '\r' < "$work_dir/login-headers.txt" \
  | grep -i '^set-cookie: __Host-MusicaAprender.Session=' \
  | head -n 1)"
if [[ -z "$session_cookie_header" ]]; then
  fail_check "la autenticacion no emitio la cookie de sesion __Host-."
fi
assert_cookie_contract "cookie de sesion" "$session_cookie_header"
session_cookie_pair="$(cut -d: -f2- <<<"$session_cookie_header" | sed 's/^ *//' | cut -d';' -f1)"

if grep -F -q -e "$email" -e "$password" -e "$csrf_token" \
  "$work_dir/login-headers.txt" "$work_dir/login-response.json"; then
  fail_check "la respuesta de autenticacion expuso credenciales o material antifalsificacion."
fi

session_status="$(curl_request \
  --silent \
  --show-error \
  --output "$work_dir/session.json" \
  --write-out '%{http_code}' \
  --cookie "$session_cookie_pair" \
  "$api_url/api/v1/auth/session")"
assert_equal "validacion server-side de sesion" "$session_status" "200"

node - "$work_dir/session.json" <<'NODE'
const fs = require('node:fs');
const response = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (response.status !== 'AUTHENTICATED' || response.role !== 'STUDENT') process.exit(1);
NODE

session_contract="$({
  "${psql_base[@]}" --command="
SELECT count(*) = 1
   AND bool_and(octet_length(session_hash) = 32)
   AND bool_and(assurance_level = 'PASSWORD')
   AND bool_and(revoked_at IS NULL)
   AND bool_and(idle_expires_at > created_at)
   AND bool_and(idle_expires_at <= created_at + interval '12 hours 5 seconds')
   AND bool_and(absolute_expires_at >= idle_expires_at)
   AND bool_and(absolute_expires_at <= created_at + interval '30 days 5 seconds')
FROM security.session
WHERE account_id = '$account_id';
"
} | tr -d '[:space:]')"
assert_equal "persistencia opaca y expiraciones" "$session_contract" "t"

node - "$email" "$wrong_password" > "$work_dir/wrong-request.json" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE
node - "$unknown_email" "$password" > "$work_dir/unknown-request.json" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE

wrong_status="$(curl_request \
  --silent \
  --show-error \
  --dump-header "$work_dir/wrong-headers.txt" \
  --output "$work_dir/wrong.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "$csrf_header_name: $csrf_token" \
  --cookie "$csrf_cookie_pair" \
  --data-binary "@$work_dir/wrong-request.json" \
  "$api_url/api/v1/auth/login")"
unknown_status="$(curl_request \
  --silent \
  --show-error \
  --dump-header "$work_dir/unknown-headers.txt" \
  --output "$work_dir/unknown.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "$csrf_header_name: $csrf_token" \
  --cookie "$csrf_cookie_pair" \
  --data-binary "@$work_dir/unknown-request.json" \
  "$api_url/api/v1/auth/login")"
assert_equal "contrasena incorrecta" "$wrong_status" "401"
assert_equal "cuenta desconocida" "$unknown_status" "401"
assert_equal \
  "respuesta no enumerable" \
  "$(problem_fingerprint "$work_dir/wrong.json")" \
  "$(problem_fingerprint "$work_dir/unknown.json")"

if grep -i -q '^set-cookie: __Host-MusicaAprender.Session=' \
  "$work_dir/wrong-headers.txt" "$work_dir/unknown-headers.txt"; then
  fail_check "una credencial invalida emitio cookie de sesion."
fi

session_count="$({
  "${psql_base[@]}" --command="SELECT count(*) FROM security.session WHERE account_id = '$account_id';"
} | tr -d '[:space:]')"
assert_equal "sesiones tras credenciales invalidas" "$session_count" "1"

"${psql_base[@]}" --command="
UPDATE security.session
SET idle_expires_at = created_at + interval '1 millisecond'
WHERE account_id = '$account_id'
  AND revoked_at IS NULL;
" >/dev/null

expired_status="$(curl_request \
  --silent \
  --show-error \
  --output "$work_dir/expired.json" \
  --write-out '%{http_code}' \
  --cookie "$session_cookie_pair" \
  "$api_url/api/v1/auth/session")"
assert_equal "sesion expirada" "$expired_status" "401"

second_login_status="$(curl_request \
  --silent \
  --show-error \
  --dump-header "$work_dir/second-login-headers.txt" \
  --output "$work_dir/second-login.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "$csrf_header_name: $csrf_token" \
  --cookie "$csrf_cookie_pair" \
  --data-binary "@$work_dir/login-request.json" \
  "$api_url/api/v1/auth/login")"
assert_equal "nueva sesion tras expiracion" "$second_login_status" "200"

second_cookie_header="$(tr -d '\r' < "$work_dir/second-login-headers.txt" \
  | grep -i '^set-cookie: __Host-MusicaAprender.Session=' \
  | head -n 1)"
assert_cookie_contract "segunda cookie de sesion" "$second_cookie_header"
second_cookie_pair="$(cut -d: -f2- <<<"$second_cookie_header" | sed 's/^ *//' | cut -d';' -f1)"

revoke_result="$({
  "${psql_base[@]}" --command="
SELECT security.revoke_active_session(session_hash)
FROM security.session
WHERE account_id = '$account_id'
  AND revoked_at IS NULL
  AND idle_expires_at > CURRENT_TIMESTAMP
ORDER BY created_at DESC
LIMIT 1;
"
} | tr -d '[:space:]')"
assert_equal "revocacion server-side" "$revoke_result" "t"

revoked_status="$(curl_request \
  --silent \
  --show-error \
  --output "$work_dir/revoked.json" \
  --write-out '%{http_code}' \
  --cookie "$second_cookie_pair" \
  "$api_url/api/v1/auth/session")"
assert_equal "sesion revocada" "$revoked_status" "401"

"${psql_base[@]}" --command="
UPDATE security.account
SET status_code = 'BLOCKED'
WHERE account_id = '$account_id';
" >/dev/null

blocked_status="$(curl_request \
  --silent \
  --show-error \
  --output "$work_dir/blocked.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "$csrf_header_name: $csrf_token" \
  --cookie "$csrf_cookie_pair" \
  --data-binary "@$work_dir/login-request.json" \
  "$api_url/api/v1/auth/login")"
assert_equal "cuenta no activa" "$blocked_status" "401"
assert_equal \
  "cuenta bloqueada no enumerable" \
  "$(problem_fingerprint "$work_dir/wrong.json")" \
  "$(problem_fingerprint "$work_dir/blocked.json")"

if grep -F -q -e "$password" -e "$wrong_password" "$api_log"; then
  fail_check "la API escribio una contrasena en logs."
fi

cat > artifacts/postgres/personal-login-summary.txt <<EOF
bl_mvp=026
endpoint_csrf=GET /api/v1/auth/csrf
endpoint_login=POST /api/v1/auth/login
endpoint_session=GET /api/v1/auth/session
valid_login=200
invalid_password=401-generic
unknown_account=401-generic-equal
inactive_account=401-generic-equal
csrf_missing=400
csrf_header=X-CSRF-TOKEN
csrf_cookie=__Host-Secure-HttpOnly-SameSite-Strict
session_cookie=__Host-Secure-HttpOnly-SameSite-Strict
session_client_storage=cookie-only
session_server_storage=sha256-only
session_assurance=PASSWORD
session_idle_lifetime=12-hours
session_absolute_lifetime=30-days
expired_session=401
revoked_session=401
account_state_revalidated=server-side
EOF

if grep -F -R -q -e "$password" -e "$wrong_password" artifacts; then
  fail_check "una contrasena aparecio en evidencia persistente."
fi

echo "OK: BL-MVP-026 login no enumerable, cookie __Host, CSRF y sesion revocable verificados."
