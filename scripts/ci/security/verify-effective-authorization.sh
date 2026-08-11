#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL030_API_URL:-http://localhost:5173}"
work_dir="$(mktemp -d)"
email="bl030-$(openssl rand -hex 12)@example.test"
password="Brisa 日本語 segura 2026"
registration_key="bl030-$(openssl rand -hex 16)"
assignment_module_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
assignment_global_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
scope_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"

api_log="$work_dir/api.log"
api_pid=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-030: $1" >&2
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

if [[ "${BL030_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
if [[ ! "$lookup_key_hex" =~ ^[0-9a-fA-F]{64}$ ]]; then
  fail_check "identity_email_lookup_key no contiene 32 bytes hexadecimales."
fi

email_hash="$({
  printf '%s' "${email^^}" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$lookup_key_hex" -binary \
    | od -An -vtx1 \
    | tr -d ' \n'
})"

account_id=""

cleanup() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" >/dev/null 2>&1 || true
    wait "$api_pid" >/dev/null 2>&1 || true
  fi

  if [[ -n "$account_id" ]]; then
    "${psql_base[@]}" --command="
DELETE FROM security.role_assignment
WHERE account_id = '$account_id'::uuid;

DELETE FROM security.access_scope
WHERE scope_id = '$scope_id'::uuid;
" >/dev/null 2>&1 || true
  fi

  rm -rf "$work_dir"
}
trap cleanup EXIT

curl_request() {
  curl "${curl_tls_options[@]}" --silent --show-error "$@"
}

if [[ "${BL030_USE_RUNNING_API:-false}" != "true" ]]; then
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
    fail_check "el entorno local no quedó disponible."
  fi

  sleep 1
done

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

if [[ "${#notice_versions[@]}" -ne 2 ]]; then
  fail_check "no se obtuvieron los consentimientos vigentes."
fi

node - \
  "$email" \
  "$password" \
  "${notice_versions[0]}" \
  "${notice_versions[1]}" \
  > "$work_dir/register.json" <<'NODE'
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
  --output "$work_dir/register-response.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: $registration_key" \
  --data-binary "@$work_dir/register.json" \
  "$api_url/api/v1/auth/register")"
assert_equal "registro sintético" "$registration_status" "202"

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
  fail_check "no se resolvió la cuenta sintética."
fi

node - "$email" "$password" > "$work_dir/login.json" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE

curl_request \
  --dump-header "$work_dir/csrf-headers.txt" \
  --output "$work_dir/csrf.json" \
  "$api_url/api/v1/auth/csrf" >/dev/null

mapfile -t csrf < <(
  node - "$work_dir/csrf.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

csrf_cookie="$(
  tr -d '\r' < "$work_dir/csrf-headers.txt" \
    | grep -i '^set-cookie: __Host-MusicaAprender.Csrf=' \
    | head -n 1 \
    | cut -d: -f2- \
    | sed 's/^ *//' \
    | cut -d';' -f1
)"

login_status="$(curl_request \
  --dump-header "$work_dir/login-headers.txt" \
  --output "$work_dir/login-response.json" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header "${csrf[1]}: ${csrf[0]}" \
  --header "X-Correlation-Id: $correlation_id" \
  --cookie "$csrf_cookie" \
  --data-binary "@$work_dir/login.json" \
  "$api_url/api/v1/auth/login")"
assert_equal "login sintético" "$login_status" "200"

session_cookie="$(
  tr -d '\r' < "$work_dir/login-headers.txt" \
    | grep -i '^set-cookie: __Host-MusicaAprender.Session=' \
    | head -n 1 \
    | cut -d: -f2- \
    | sed 's/^ *//' \
    | cut -d';' -f1
)"

if [[ -z "$session_cookie" ]]; then
  fail_check "no se emitió la cookie de sesión."
fi

session_status="$(curl_request \
  --output "$work_dir/session-student.json" \
  --write-out '%{http_code}' \
  --header "X-Correlation-Id: $correlation_id" \
  --cookie "$session_cookie" \
  "$api_url/api/v1/auth/session")"
assert_equal "snapshot STUDENT" "$session_status" "200"

node - "$work_dir/session-student.json" <<'NODE'
const fs = require('node:fs');
const session = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (session.status !== 'AUTHENTICATED' || session.role !== 'STUDENT') process.exit(1);
if (!session.roles?.includes('STUDENT')) process.exit(1);
for (const permission of ['PROFILE.READ', 'CONTENT.READ', 'LEARNING.START']) {
  if (!session.capabilities?.includes(permission)) process.exit(1);
}
if (session.capabilities?.includes('SECURITY.MANAGE_ROLES')) process.exit(1);
NODE

denied_status="$(curl_request \
  --output "$work_dir/catalog-denied.json" \
  --write-out '%{http_code}' \
  --header "X-Correlation-Id: $correlation_id" \
  --cookie "$session_cookie" \
  "$api_url/api/v1/security/authorization/catalog")"
assert_equal "denegación por defecto" "$denied_status" "403"

node - "$work_dir/catalog-denied.json" <<'NODE'
const fs = require('node:fs');
const problem = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (problem.code !== 'security.authorization.denied') process.exit(1);
NODE

"${psql_base[@]}" --command="
INSERT INTO security.access_scope (
  scope_id,
  scope_type,
  module_code,
  definition
)
VALUES (
  '$scope_id'::uuid,
  'MODULE',
  'EDITORIAL',
  '{}'::jsonb
);

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
  '$assignment_module_id'::uuid,
  '$account_id'::uuid,
  role_id,
  '$scope_id'::uuid,
  CURRENT_TIMESTAMP - INTERVAL '2 minutes',
  CURRENT_TIMESTAMP + INTERVAL '30 minutes',
  'BL-MVP-030 smoke scoped'
FROM security.role
WHERE role_code = 'ADMIN';
" >/dev/null

session_scoped_status="$(curl_request \
  --output "$work_dir/session-scoped.json" \
  --write-out '%{http_code}' \
  --header "X-Correlation-Id: $correlation_id" \
  --cookie "$session_cookie" \
  "$api_url/api/v1/auth/session")"
assert_equal "reevaluación sin relogin" "$session_scoped_status" "200"

node - "$work_dir/session-scoped.json" <<'NODE'
const fs = require('node:fs');
const session = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!session.roles?.includes('ADMIN')) process.exit(1);
if (!session.capabilities?.includes('SECURITY.MANAGE_ROLES')) process.exit(1);
NODE

scoped_denied_status="$(curl_request \
  --output "$work_dir/catalog-scoped-denied.json" \
  --write-out '%{http_code}' \
  --header "X-Correlation-Id: $correlation_id" \
  --cookie "$session_cookie" \
  "$api_url/api/v1/security/authorization/catalog")"
assert_equal \
  "capacidad visible no sustituye ámbito server-side" \
  "$scoped_denied_status" \
  "403"

"${psql_base[@]}" --command="
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
  '$assignment_global_id'::uuid,
  '$account_id'::uuid,
  role_id,
  NULL,
  CURRENT_TIMESTAMP - INTERVAL '2 minutes',
  CURRENT_TIMESTAMP + INTERVAL '30 minutes',
  'BL-MVP-030 smoke global'
FROM security.role
WHERE role_code = 'ADMIN';
" >/dev/null

catalog_allowed_status="$(curl_request \
  --output "$work_dir/catalog-allowed.json" \
  --write-out '%{http_code}' \
  --header "X-Correlation-Id: $correlation_id" \
  --cookie "$session_cookie" \
  "$api_url/api/v1/security/authorization/catalog")"
assert_equal "permiso global vigente" "$catalog_allowed_status" "200"

node - "$work_dir/catalog-allowed.json" <<'NODE'
const fs = require('node:fs');
const catalog = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (catalog.status !== 'AUTHORIZED') process.exit(1);
for (const role of ['STUDENT', 'EDITOR', 'REVIEWER', 'ADMIN']) {
  if (!catalog.roles?.includes(role)) process.exit(1);
}
if (!catalog.permissions?.includes('SECURITY.MANAGE_ROLES')) process.exit(1);
NODE

"${psql_base[@]}" --command="
UPDATE security.role_assignment
SET valid_to = CURRENT_TIMESTAMP - INTERVAL '1 second'
WHERE assignment_id = '$assignment_global_id'::uuid;
" >/dev/null

expired_status="$(curl_request \
  --output "$work_dir/catalog-expired.json" \
  --write-out '%{http_code}' \
  --header "X-Correlation-Id: $correlation_id" \
  --cookie "$session_cookie" \
  "$api_url/api/v1/security/authorization/catalog")"
assert_equal "vigencia se recalcula sin relogin" "$expired_status" "403"

if grep -F -R -q -e "$email" -e "$password" artifacts; then
  fail_check "correo o contraseña sintéticos aparecieron en artifacts."
fi

cat > artifacts/postgres/bl-mvp-030-effective-authorization-summary.txt <<EOF
BL-MVP-030
baseline_role=STUDENT
default_deny=verified
scoped_admin_global_operation=denied
global_admin_global_operation=allowed
expired_global_assignment=denied
reevaluation_without_relogin=verified
client_visibility_is_not_server_authority=verified
EOF

echo "OK: BL-MVP-030 permisos efectivos, alcance, vigencia y denegacion por defecto verificados."
