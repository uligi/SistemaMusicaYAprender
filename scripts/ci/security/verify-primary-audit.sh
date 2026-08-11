#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL033_API_URL:-https://localhost:5449}"
work_dir="$(mktemp -d)"
email="bl033-$(openssl rand -hex 10)@example.test"
password="Auditoria 日本語 segura 2026"
registration_key="bl033-$(openssl rand -hex 16)"
duplicate_key="bl033-duplicate-$(openssl rand -hex 16)"
registration_correlation="$(node -e "console.log(require('node:crypto').randomUUID())")"
duplicate_correlation="$(node -e "console.log(require('node:crypto').randomUUID())")"
login_failure_correlation="$(node -e "console.log(require('node:crypto').randomUUID())")"
login_correlation="$(node -e "console.log(require('node:crypto').randomUUID())")"
authorization_correlation="$(node -e "console.log(require('node:crypto').randomUUID())")"
logout_correlation="$(node -e "console.log(require('node:crypto').randomUUID())")"

api_log="$work_dir/api.log"
api_pid=""
account_id=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-033: $1" >&2
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

if [[ "${BL033_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

if [[ "${BL033_USE_RUNNING_API:-false}" != "true" ]]; then
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

# -------------------------------------------------------------------
# Registro real: éxito, idempotencia y duplicado no enumerable.
# -------------------------------------------------------------------
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
  "$email" \
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
    --header "X-Correlation-Id: $registration_correlation" \
    --data-binary "@$work_dir/register.json" \
    "$api_url/api/v1/auth/register"
)"
assert_equal "registro auditado" "$register_status" "202"

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
email_hash="$(
  printf '%s' "${email^^}" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$lookup_key_hex" -binary \
    | od -An -vtx1 \
    | tr -d ' \n'
)"

account_id="$(
  "${psql_base[@]}" --command="
SELECT account_id
FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
" | tr -d '[:space:]'
)"

[[ "$account_id" =~ ^[0-9a-f-]{36}$ ]] \
  || fail_check "No se resolvió la cuenta sintética."

registration_event_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.security_event
WHERE account_id = '$account_id'::uuid
  AND event_type = 'ACCOUNT_REGISTRATION'
  AND result_code = 'SUCCEEDED'
  AND correlation_id = '$registration_correlation'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "evento de registro" "$registration_event_count" "1"

# Repetir la misma operación lógica no ejecuta otra vez los efectos.
replay_status="$(
  curl_request \
    --output "$work_dir/register-replay.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $registration_key" \
    --header "X-Correlation-Id: $registration_correlation" \
    --data-binary "@$work_dir/register.json" \
    "$api_url/api/v1/auth/register"
)"
assert_equal "reintento idempotente del registro" "$replay_status" "202"

registration_event_count_after_replay="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.security_event
WHERE account_id = '$account_id'::uuid
  AND event_type = 'ACCOUNT_REGISTRATION'
  AND result_code = 'SUCCEEDED'
  AND correlation_id = '$registration_correlation'::uuid;
" | tr -d '[:space:]'
)"
assert_equal \
  "sin auditoría primaria duplicada por reintento" \
  "$registration_event_count_after_replay" \
  "1"

duplicate_status="$(
  curl_request \
    --output "$work_dir/register-duplicate.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $duplicate_key" \
    --header "X-Correlation-Id: $duplicate_correlation" \
    --data-binary "@$work_dir/register.json" \
    "$api_url/api/v1/auth/register"
)"
assert_equal "registro duplicado no enumerable" "$duplicate_status" "202"

duplicate_event="$(
  "${psql_base[@]}" --command="
SELECT concat(
    count(*), '|',
    coalesce(max(octet_length(client_fingerprint)), 0), '|',
    coalesce(bool_and(account_id IS NULL), false)
)
FROM security.security_event
WHERE event_type = 'ACCOUNT_REGISTRATION'
  AND result_code = 'RECEIVED_OR_EXISTING'
  AND correlation_id = '$duplicate_correlation'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "duplicado minimizado/pseudonimizado" "$duplicate_event" "1|32|t"

# Activar la cuenta de prueba sin saltarse el login real.
"${psql_base[@]}" --command="
UPDATE security.account
SET status_code = 'ACTIVE',
    verified_at = CURRENT_TIMESTAMP
WHERE account_id = '$account_id'::uuid;
" >/dev/null

# -------------------------------------------------------------------
# Login fallido y login exitoso con sesión auditada.
# -------------------------------------------------------------------
curl_request \
  --cookie-jar "$work_dir/cookies.txt" \
  --output "$work_dir/csrf.json" \
  "$api_url/api/v1/auth/csrf"

mapfile -t csrf < <(
  node - "$work_dir/csrf.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.requestToken || !value.headerName) process.exit(1);
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

node - "$email" "$password" >"$work_dir/login.json" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE

node - "$email" "Credencial equivocada 2026" >"$work_dir/login-bad.json" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE

bad_login_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/problem.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $login_failure_correlation" \
    --data-binary "@$work_dir/login-bad.json" \
    "$api_url/api/v1/auth/login"
)"
assert_equal "login fallido auditado" "$bad_login_status" "401"

login_failure_events="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.security_event
WHERE correlation_id = '$login_failure_correlation'::uuid
  AND event_type IN ('LOGIN_FAILURE_ACCOUNT', 'LOGIN_FAILURE_CLIENT')
  AND result_code = 'REJECTED';
" | tr -d '[:space:]'
)"
assert_equal "dos dimensiones pseudónimas del fallo de login" "$login_failure_events" "2"

# CSRF nuevo antes del login exitoso.
curl_request \
  --cookie "$work_dir/cookies.txt" \
  --cookie-jar "$work_dir/cookies.txt" \
  --output "$work_dir/csrf-login.json" \
  "$api_url/api/v1/auth/csrf"

mapfile -t csrf < <(
  node - "$work_dir/csrf-login.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

login_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/login-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $login_correlation" \
    --data-binary "@$work_dir/login.json" \
    "$api_url/api/v1/auth/login"
)"
assert_equal "login exitoso" "$login_status" "200"

session_event_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.security_event
WHERE account_id = '$account_id'::uuid
  AND event_type = 'SESSION_CREATED'
  AND result_code = 'SUCCEEDED'
  AND correlation_id = '$login_correlation'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "sesión creada auditada" "$session_event_count" "1"

# -------------------------------------------------------------------
# Denegación de autorización: security_event + audit_event correlacionados.
# -------------------------------------------------------------------
authorization_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/problem.json" \
    --write-out '%{http_code}' \
    --header "X-Correlation-Id: $authorization_correlation" \
    "$api_url/api/v1/security/authorization/catalog"
)"
assert_equal "catálogo sin SECURITY.MANAGE_ROLES" "$authorization_status" "403"

authorization_security_event="$(
  "${psql_base[@]}" --command="
SELECT concat(
    count(*), '|',
    coalesce(bool_and(account_id = '$account_id'::uuid), false)
)
FROM security.security_event
WHERE event_type = 'AUTHORIZATION_DECISION'
  AND result_code = 'DENIED'
  AND correlation_id = '$authorization_correlation'::uuid;
" | tr -d '[:space:]'
)"
assert_equal \
  "denegación conserva sujeto y correlación" \
  "$authorization_security_event" \
  "1|t"

authorization_audit_event="$(
  "${psql_base[@]}" --command="
SELECT concat(
    count(*), '|',
    coalesce(max(role_code), ''), '|',
    coalesce(max(object_type), ''), '|',
    coalesce(max(action_code), ''), '|',
    coalesce(max(reason), ''), '|',
    coalesce(max(octet_length(after_digest)), 0)
)
FROM security.audit_event
WHERE actor_id = '$account_id'::uuid
  AND correlation_id = '$authorization_correlation'::uuid;
" | tr -d '[:space:]'
)"
assert_equal \
  "auditoría primaria de decisión" \
  "$authorization_audit_event" \
  "1|STUDENT|AUTHORIZATION_GLOBAL|SECURITY.MANAGE_ROLES|NO_VALID_GRANT|32"

# -------------------------------------------------------------------
# MFA y administración de roles ya recorrieron sus regresiones antes de
# este smoke. Sus eventos nuevos deben existir y el audit_event BL031
# conserva la decisión de negocio separada de la decisión de autorización.
# -------------------------------------------------------------------
mfa_event_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.security_event
WHERE event_type IN (
    'MFA_ENROLLMENT_CHALLENGE',
    'MFA_ENROLLMENT_CONFIRM',
    'MFA_STEP_UP_CHALLENGE',
    'MFA_STEP_UP_CONFIRM'
);
" | tr -d '[:space:]'
)"
if [[ "$mfa_event_count" -lt 4 ]]; then
  fail_check "La regresión MFA no dejó la secuencia primaria esperada."
fi

role_audit_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.audit_event
WHERE object_type = 'ROLE_ASSIGNMENT'
  AND action_code IN (
      'SECURITY.ROLE_ASSIGNMENT.GRANT',
      'SECURITY.ROLE_ASSIGNMENT.REVOKE'
  );
" | tr -d '[:space:]'
)"
if [[ "$role_audit_count" -lt 2 ]]; then
  fail_check "No se conservaron las decisiones de negocio BL031."
fi

# -------------------------------------------------------------------
# Logout: sujeto pseudónimo, correlación y append-only.
# -------------------------------------------------------------------
curl_request \
  --cookie "$work_dir/cookies.txt" \
  --cookie-jar "$work_dir/cookies.txt" \
  --output "$work_dir/csrf-logout.json" \
  "$api_url/api/v1/auth/csrf"

mapfile -t csrf < <(
  node - "$work_dir/csrf-logout.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

logout_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --cookie-jar "$work_dir/cookies.txt" \
    --output "$work_dir/logout.json" \
    --write-out '%{http_code}' \
    --request POST \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $logout_correlation" \
    "$api_url/api/v1/auth/logout"
)"
assert_equal "logout auditado" "$logout_status" "200"

logout_event="$(
  "${psql_base[@]}" --command="
SELECT concat(
    count(*), '|',
    coalesce(max(octet_length(client_fingerprint)), 0), '|',
    coalesce(bool_and(account_id IS NULL), false)
)
FROM security.security_event
WHERE event_type = 'SESSION_REVOKED'
  AND result_code = 'SUCCEEDED'
  AND correlation_id = '$logout_correlation'::uuid;
" | tr -d '[:space:]'
)"
assert_equal "logout pseudonimizado/correlacionado" "$logout_event" "1|32|t"

# Los eventos deben ser recientes (timestamptz UTC en PostgreSQL).
recent_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.security_event
WHERE correlation_id IN (
    '$registration_correlation'::uuid,
    '$login_failure_correlation'::uuid,
    '$login_correlation'::uuid,
    '$authorization_correlation'::uuid,
    '$logout_correlation'::uuid
)
  AND occurred_at >= CURRENT_TIMESTAMP - INTERVAL '2 minutes'
  AND occurred_at <= CURRENT_TIMESTAMP + INTERVAL '1 second';
" | tr -d '[:space:]'
)"
if [[ "$recent_count" -lt 6 ]]; then
  fail_check "Los eventos primarios no conservan marcas temporales recientes coherentes."
fi

# Append-only: ni security_event ni audit_event aceptan UPDATE/DELETE.
if "${psql_base[@]}" --command="
UPDATE security.security_event
SET result_code = 'ALTERED'
WHERE correlation_id = '$authorization_correlation'::uuid;
" >/dev/null 2>&1; then
  fail_check "security.security_event permitió UPDATE."
fi

if "${psql_base[@]}" --command="
DELETE FROM security.audit_event
WHERE correlation_id = '$authorization_correlation'::uuid;
" >/dev/null 2>&1; then
  fail_check "security.audit_event permitió DELETE."
fi

readonly_acl="$(
  "${psql_base[@]}" --command="
SELECT concat(
    has_table_privilege('jp_login_readonly', 'security.security_event', 'SELECT'),
    '|',
    has_table_privilege('jp_login_readonly', 'security.audit_event', 'SELECT')
);
" | tr -d '[:space:]'
)"
assert_equal "readonly sin acceso a auditoría privada" "$readonly_acl" "f|f"

# El esquema primario no contiene columnas para secretos/credenciales.
sensitive_columns="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM information_schema.columns
WHERE table_schema = 'security'
  AND table_name IN ('security_event', 'audit_event')
  AND lower(column_name) ~ '(email|password|secret|token|credential)';
" | tr -d '[:space:]'
)"
assert_equal "sin columnas sensibles en auditoría primaria" "$sensitive_columns" "0"

echo "OK: BL-MVP-033 éxitos, fallos y denegaciones conservan sujeto, acción, objeto, resultado, tiempo y correlación en registros protegidos."
