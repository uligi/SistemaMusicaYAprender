#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL032_API_URL:-https://localhost:5448}"
work_dir="$(mktemp -d)"
admin_email="bl032-admin-$(openssl rand -hex 10)@example.test"
password="MFA 日本語 segura 2026"
registration_key="bl032-$(openssl rand -hex 16)"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
seed_admin_assignment="$(node -e "console.log(require('node:crypto').randomUUID())")"

api_log="$work_dir/api.log"
api_pid=""
admin_account_id=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-032: $1" >&2
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
    if [[ -f "$work_dir/problem.json" ]]; then
      cat "$work_dir/problem.json" >&2 || true
      echo >&2
    fi
    fail_check "$name esperaba '$expected' y obtuvo '$actual'."
  fi
}

if [[ "${BL032_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

if [[ "${BL032_USE_RUNNING_API:-false}" != "true" ]]; then
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

# Registro real para obtener credencial Argon2id con las políticas vigentes.
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

[[ "${#notice_versions[@]}" -eq 2 ]] \
  || fail_check "No se resolvieron los consentimientos obligatorios."

node - \
  "$admin_email" \
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
assert_equal "registro admin sintético" "$register_status" "202"

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
email_hash="$(
  printf '%s' "${admin_email^^}" \
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
    '$seed_admin_assignment'::uuid,
    account.account_id,
    role.role_id,
    NULL,
    CURRENT_TIMESTAMP - INTERVAL '2 minutes',
    CURRENT_TIMESTAMP + INTERVAL '1 hour',
    'BL-MVP-032 bootstrap técnico de prueba'
FROM security.account AS account
CROSS JOIN security.role AS role
WHERE encode(account.email_lookup_hash, 'hex') = '$email_hash'
  AND role.role_code = 'ADMIN';
" >/dev/null

admin_account_id="$(
  "${psql_base[@]}" --command="
SELECT account_id
FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
" | tr -d '[:space:]'
)"

[[ "$admin_account_id" =~ ^[0-9a-f-]{36}$ ]] \
  || fail_check "No se resolvió la cuenta admin sintética."

# Login y CSRF reales.
curl_request \
  --cookie-jar "$work_dir/cookies.txt" \
  --output "$work_dir/csrf.json" \
  "$api_url/api/v1/auth/csrf"

mapfile -t csrf < <(
  node - "$work_dir/csrf.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

node - "$admin_email" "$password" >"$work_dir/login.json" <<'NODE'
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
assert_equal "login admin MFA" "$login_status" "200"

policy_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/policy.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/security/mfa/policy"
)"
assert_equal "catálogo de política MFA" "$policy_status" "200"

node - "$work_dir/policy.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const totp = value.methods?.find((method) => method.methodType === 'TOTP');
if (
  value.version !== 'MFA-POLICY-1' ||
  value.privilegedAssuranceLevel !== 'MFA' ||
  value.recentAssuranceMinutes !== 15 ||
  value.maximumAttempts !== 5 ||
  !totp ||
  totp.digits !== 6 ||
  totp.periodSeconds !== 30 ||
  totp.clockSkewSteps !== 1
) {
  process.exit(1);
}
NODE

refresh_authenticated_csrf() {
  local phase="$1"
  local response_file="$work_dir/csrf-$phase.json"
  local status

  status="$(
    curl_request \
      --cookie "$work_dir/cookies.txt" \
      --cookie-jar "$work_dir/cookies.txt" \
      --output "$response_file" \
      --write-out '%{http_code}' \
      "$api_url/api/v1/auth/csrf"
  )"
  assert_equal "CSRF autenticado ($phase)" "$status" "200"

  mapfile -t csrf < <(
    node - "$response_file" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.requestToken || !value.headerName) process.exit(1);
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
  )
}

# Permission sí existe, assurance todavía no: debe cerrarse con 403 específico.
catalog_denied="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/catalog-denied.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/security/role-assignments/catalog"
)"
assert_equal "rol admin sin step-up" "$catalog_denied" "403"

node - "$work_dir/catalog-denied.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.code !== 'security.authentication.step-up-required') process.exit(1);
NODE

# La contraseña incorrecta no inicia la inscripción.
refresh_authenticated_csrf "wrong-password"
wrong_password_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/wrong-password.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data '{"currentPassword":"incorrecta-que-no-puede-validar"}' \
    "$api_url/api/v1/security/mfa/enrollment/start"
)"
assert_equal "reautenticación incorrecta" "$wrong_password_status" "401"

refresh_authenticated_csrf "enrollment-start"
node - "$password" >"$work_dir/enroll-start.json" <<'NODE'
process.stdout.write(JSON.stringify({ currentPassword: process.argv[2] }));
NODE

enroll_start_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/enroll-start-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/enroll-start.json" \
    "$api_url/api/v1/security/mfa/enrollment/start"
)"
assert_equal "inicio inscripción TOTP" "$enroll_start_status" "200"

mapfile -t enrollment < <(
  node - "$work_dir/enroll-start-response.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.challengeId || !value.secret || !value.otpAuthUri) process.exit(1);
process.stdout.write(`${value.challengeId}\n${value.secret}\n`);
NODE
)

[[ "${#enrollment[@]}" -eq 2 ]] \
  || fail_check "Respuesta de inscripción TOTP incompleta."

# PostgreSQL solo conserva el digest mientras el secreto aún no está confirmado.
pending_digest_length="$(
  "${psql_base[@]}" --command="
SELECT octet_length(request_digest)
FROM ops.idempotency_record
WHERE account_id = '$admin_account_id'::uuid
  AND operation_code = 'SECURITY.MFA.ENROLL'
  AND idempotency_key = replace('${enrollment[0]}', '-', '');
" | tr -d '[:space:]'
)"
assert_equal "digest del reto de inscripción" "$pending_digest_length" "32"

pending_policy="$(
  "${psql_base[@]}" --command="
SELECT response_ref ->> 'policyVersion'
FROM ops.idempotency_record
WHERE account_id = '$admin_account_id'::uuid
  AND operation_code = 'SECURITY.MFA.ENROLL'
  AND idempotency_key = replace('${enrollment[0]}', '-', '');
" | tr -d '[:space:]'
)"
assert_equal "versión de política ligada al reto" "$pending_policy" "MFA-POLICY-1"

active_before="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.mfa_method
WHERE account_id = '$admin_account_id'::uuid
  AND disabled_at IS NULL;
" | tr -d '[:space:]'
)"
assert_equal "sin método antes de confirmar" "$active_before" "0"

totp_code() {
  node - "$1" <<'NODE'
const crypto = require('node:crypto');
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const text = process.argv[2].replace(/[\s-]/g, '').toUpperCase();
let buffer = 0;
let bits = 0;
const bytes = [];
for (const ch of text) {
  const index = alphabet.indexOf(ch);
  if (index < 0) process.exit(2);
  buffer = (buffer << 5) | index;
  bits += 5;
  if (bits >= 8) {
    bits -= 8;
    bytes.push((buffer >> bits) & 255);
  }
}
const counter = Math.floor(Date.now() / 1000 / 30);
const counterBytes = Buffer.alloc(8);
counterBytes.writeBigUInt64BE(BigInt(counter));
const digest = crypto.createHmac('sha1', Buffer.from(bytes)).update(counterBytes).digest();
const offset = digest[digest.length - 1] & 15;
const binary =
  ((digest[offset] & 127) << 24) |
  ((digest[offset + 1] & 255) << 16) |
  ((digest[offset + 2] & 255) << 8) |
  (digest[offset + 3] & 255);
console.log(String(binary % 1000000).padStart(6, '0'));
NODE
}

enrollment_code="$(totp_code "${enrollment[1]}")"

refresh_authenticated_csrf "enrollment-confirm"
node - \
  "${enrollment[0]}" \
  "${enrollment[1]}" \
  "$enrollment_code" \
  >"$work_dir/enroll-confirm.json" <<'NODE'
const [challengeId, secret, code] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ challengeId, secret, code }));
NODE

enroll_confirm_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/enroll-confirm-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/enroll-confirm.json" \
    "$api_url/api/v1/security/mfa/enrollment/confirm"
)"
assert_equal "confirmación inscripción TOTP" "$enroll_confirm_status" "200"

secret_ref="$(
  "${psql_base[@]}" --command="
SELECT secret_ref
FROM security.mfa_method
WHERE account_id = '$admin_account_id'::uuid
  AND method_type = 'TOTP'
  AND disabled_at IS NULL
ORDER BY enrolled_at DESC
LIMIT 1;
" | tr -d '\r\n'
)"

[[ "$secret_ref" == maobj1:* ]] \
  || fail_check "security.mfa_method no conserva una referencia opaca MAOBJ1."

if [[ "$secret_ref" == *"${enrollment[1]}"* ]]; then
  fail_check "security.mfa_method expuso el secreto Base32."
fi

# El límite de intentos pertenece al reto, no a la sesión completa.
refresh_authenticated_csrf "limit-step-start"
limit_start_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/limit-start.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data '{}' \
    "$api_url/api/v1/security/mfa/step-up/start"
)"
assert_equal "inicio reto de límite" "$limit_start_status" "200"

limit_step_id="$(
  node - "$work_dir/limit-start.json" <<'NODE'
const fs = require('node:fs');
process.stdout.write(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).challengeId);
NODE
)"
invalid_code="$(
  node - "${enrollment[1]}" <<'NODE'
const crypto = require('node:crypto');
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const text = process.argv[2].replace(/[\s-]/g, '').toUpperCase();
let buffer = 0;
let bits = 0;
const bytes = [];
for (const ch of text) {
  const index = alphabet.indexOf(ch);
  if (index < 0) process.exit(2);
  buffer = (buffer << 5) | index;
  bits += 5;
  if (bits >= 8) {
    bits -= 8;
    bytes.push((buffer >> bits) & 255);
  }
}
const key = Buffer.from(bytes);
const base = Math.floor(Date.now() / 1000 / 30);
const accepted = new Set();
for (const delta of [-2, -1, 0, 1, 2]) {
  const counterBytes = Buffer.alloc(8);
  counterBytes.writeBigUInt64BE(BigInt(base + delta));
  const digest = crypto.createHmac('sha1', key).update(counterBytes).digest();
  const offset = digest[digest.length - 1] & 15;
  const binary =
    ((digest[offset] & 127) << 24) |
    ((digest[offset + 1] & 255) << 16) |
    ((digest[offset + 2] & 255) << 8) |
    (digest[offset + 3] & 255);
  accepted.add(String(binary % 1000000).padStart(6, '0'));
}
for (let candidate = 0; candidate < 10; candidate++) {
  const value = String(candidate).padStart(6, '0');
  if (!accepted.has(value)) {
    process.stdout.write(value);
    process.exit(0);
  }
}
process.exit(3);
NODE
)"

for attempt in 1 2 3 4 5; do
  refresh_authenticated_csrf "limit-$attempt"
  node - "$limit_step_id" "$invalid_code" >"$work_dir/limit-confirm.json" <<'NODE'
const [challengeId, code] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ challengeId, code }));
NODE

  limit_status="$(
    curl_request \
      --cookie "$work_dir/cookies.txt" \
      --output "$work_dir/problem.json" \
      --write-out '%{http_code}' \
      --header 'Content-Type: application/json' \
      --header "${csrf[1]}: ${csrf[0]}" \
      --data-binary "@$work_dir/limit-confirm.json" \
      "$api_url/api/v1/security/mfa/step-up/confirm"
  )"

  if [[ "$attempt" -lt 5 ]]; then
    assert_equal "intento MFA inválido $attempt" "$limit_status" "400"
  else
    assert_equal "agotamiento del reto MFA" "$limit_status" "429"
  fi

  rm -f "$work_dir/problem.json"
done

refresh_authenticated_csrf "limit-exhausted"
exhausted_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/problem.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/limit-confirm.json" \
    "$api_url/api/v1/security/mfa/step-up/confirm"
)"
assert_equal "reto agotado no recuperable" "$exhausted_status" "429"
rm -f "$work_dir/problem.json"

# Sin step-up, la operación sensible todavía está cerrada.
catalog_after_enrollment="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/catalog-after-enrollment.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/security/role-assignments/catalog"
)"
assert_equal "factor inscrito sin step-up" "$catalog_after_enrollment" "403"

refresh_authenticated_csrf "step-start"
step_start_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/step-start-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $correlation_id" \
    --data '{}' \
    "$api_url/api/v1/security/mfa/step-up/start"
)"
assert_equal "inicio step-up" "$step_start_status" "200"

step_id="$(
  node - "$work_dir/step-start-response.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.challengeId || value.maximumAttempts !== 5) process.exit(1);
process.stdout.write(value.challengeId);
NODE
)"

step_code="$(totp_code "${enrollment[1]}")"

refresh_authenticated_csrf "step-confirm"
node - "$step_id" "$step_code" >"$work_dir/step-confirm.json" <<'NODE'
const [challengeId, code] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ challengeId, code }));
NODE

step_confirm_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/step-confirm-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/step-confirm.json" \
    "$api_url/api/v1/security/mfa/step-up/confirm"
)"
assert_equal "confirmación step-up" "$step_confirm_status" "200"

mapfile -t session_state < <(
  "${psql_base[@]}" --command="
SELECT
    assurance_level,
    CASE WHEN idle_expires_at <= CURRENT_TIMESTAMP + INTERVAL '15 minutes 5 seconds' THEN 'idle-ok' ELSE 'idle-bad' END,
    CASE WHEN absolute_expires_at <= created_at + INTERVAL '8 hours 5 seconds' THEN 'absolute-ok' ELSE 'absolute-bad' END
FROM security.session
WHERE account_id = '$admin_account_id'::uuid
  AND revoked_at IS NULL
ORDER BY created_at DESC
LIMIT 1;
" | tr '|' '\n'
)

assert_equal "assurance de sesión" "${session_state[0]}" "MFA"
assert_equal "idle privilegiado" "${session_state[1]}" "idle-ok"
assert_equal "absoluto privilegiado" "${session_state[2]}" "absolute-ok"

catalog_allowed="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/catalog-allowed.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/security/role-assignments/catalog"
)"
assert_equal "rol admin con step-up" "$catalog_allowed" "200"

# El mismo reto consumido no puede reutilizarse.
refresh_authenticated_csrf "step-replay"
step_replay_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/problem.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/step-confirm.json" \
    "$api_url/api/v1/security/mfa/step-up/confirm"
)"
assert_equal "reto consumido no reutilizable" "$step_replay_status" "409"
rm -f "$work_dir/problem.json"

# Un reto nuevo tampoco acepta reutilizar el contador TOTP ya exitoso.
refresh_authenticated_csrf "step-second-start"
second_start_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/second-start.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data '{}' \
    "$api_url/api/v1/security/mfa/step-up/start"
)"
assert_equal "segundo reto" "$second_start_status" "200"

second_step_id="$(
  node - "$work_dir/second-start.json" <<'NODE'
const fs = require('node:fs');
process.stdout.write(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).challengeId);
NODE
)"
node - "$second_step_id" "$step_code" >"$work_dir/second-confirm.json" <<'NODE'
const [challengeId, code] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ challengeId, code }));
NODE

refresh_authenticated_csrf "step-code-replay"
code_replay_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/problem.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/second-confirm.json" \
    "$api_url/api/v1/security/mfa/step-up/confirm"
)"
assert_equal "contador TOTP no reutilizable" "$code_replay_status" "409"
rm -f "$work_dir/problem.json"

# Expira solo la aserción reciente: el permiso vuelve a cerrarse.
"${psql_base[@]}" --command="
UPDATE ops.idempotency_record
SET
    created_at = CURRENT_TIMESTAMP - INTERVAL '16 minutes',
    expires_at = CURRENT_TIMESTAMP - INTERVAL '1 second'
WHERE account_id = '$admin_account_id'::uuid
  AND operation_code = 'SECURITY.MFA.ASSURANCE';
" >/dev/null

catalog_expired="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/catalog-expired.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/security/role-assignments/catalog"
)"
assert_equal "step-up vencido vuelve a denegar" "$catalog_expired" "403"

echo "OK: BL-MVP-032 TOTP, inscripción confirmada, secreto privado, reto acotado, no reutilización y step-up vigente verificados."
