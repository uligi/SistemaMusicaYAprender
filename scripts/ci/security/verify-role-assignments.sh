#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL031_API_URL:-https://localhost:5447}"
work_dir="$(mktemp -d)"
admin_email="bl031-admin-$(openssl rand -hex 10)@example.test"
password="Brisa 日本語 segura 2026"
registration_key="bl031-$(openssl rand -hex 16)"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
target_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
target_lookup_hex="$(openssl rand -hex 32)"
target_cipher_hex="$(openssl rand -hex 32)"
seed_admin_assignment="$(node -e "console.log(require('node:crypto').randomUUID())")"

api_log="$work_dir/api.log"
api_pid=""
admin_account_id=""
created_assignment_id=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-031: $1" >&2
  if [[ -s "$api_log" ]]; then
    tail -n 80 "$api_log" >&2 || true
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

if [[ "${BL031_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

if [[ "${BL031_USE_RUNNING_API:-false}" != "true" ]]; then
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

# Reutiliza el flujo real de registro para obtener una credencial Argon2id válida.
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

INSERT INTO security.account (
    account_id,
    email_lookup_hash,
    email_cipher,
    status_code,
    verified_at
)
VALUES (
    '$target_id'::uuid,
    decode('$target_lookup_hex', 'hex'),
    decode('$target_cipher_hex', 'hex'),
    'ACTIVE',
    CURRENT_TIMESTAMP
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
    '$seed_admin_assignment'::uuid,
    account_id,
    role_id,
    NULL,
    CURRENT_TIMESTAMP - INTERVAL '2 minutes',
    CURRENT_TIMESTAMP + INTERVAL '1 hour',
    'BL-MVP-031 bootstrap técnico de prueba'
FROM security.account
CROSS JOIN security.role
WHERE encode(email_lookup_hash, 'hex') = '$email_hash'
  AND role_code = 'ADMIN';
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

# Sesión y CSRF reales.
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
assert_equal "login admin sintético" "$login_status" "200"

# BL-MVP-032 prerequisito MFA sintetico.
# El smoke BL031 sigue probando exclusivamente administración de roles.
session_id="$(
  "${psql_base[@]}" --command="
SELECT session_id
FROM security.session
WHERE account_id = '$admin_account_id'::uuid
  AND revoked_at IS NULL
ORDER BY created_at DESC
LIMIT 1;
" | tr -d '[:space:]'
)"

[[ "$session_id" =~ ^[0-9a-f-]{36}$ ]] \
  || fail_check "No se resolvió la sesión sintética para assurance."

session_key="${session_id//-/}"

"${psql_base[@]}" --command="
INSERT INTO security.mfa_method (
    account_id,
    method_type,
    secret_ref,
    enrolled_at,
    disabled_at
)
VALUES (
    '$admin_account_id'::uuid,
    'TOTP',
    'BL031-SYNTHETIC-MFA-NOT-USED',
    CURRENT_TIMESTAMP,
    NULL
);

UPDATE security.session
SET
    assurance_level = 'MFA',
    idle_expires_at = LEAST(
        idle_expires_at,
        CURRENT_TIMESTAMP + INTERVAL '15 minutes',
        absolute_expires_at,
        created_at + INTERVAL '8 hours'
    ),
    absolute_expires_at = LEAST(
        absolute_expires_at,
        created_at + INTERVAL '8 hours'
    )
WHERE session_id = '$session_id'::uuid
  AND account_id = '$admin_account_id'::uuid;

INSERT INTO ops.idempotency_record (
    account_id,
    operation_code,
    idempotency_key,
    request_digest,
    response_code,
    response_ref,
    created_at,
    expires_at
)
VALUES (
    '$admin_account_id'::uuid,
    'SECURITY.MFA.ASSURANCE',
    '$session_key',
    decode(repeat('a1', 32), 'hex'),
    200,
    jsonb_build_object(
        'assurance', 'MFA',
        'purpose', 'PRIVILEGED',
        'source', 'BL031-regression'
    ),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '15 minutes'
)
ON CONFLICT (
    account_id,
    operation_code,
    idempotency_key
)
DO UPDATE SET
    response_code = 200,
    response_ref = EXCLUDED.response_ref,
    created_at = CURRENT_TIMESTAMP,
    expires_at = CURRENT_TIMESTAMP + INTERVAL '15 minutes';
" >/dev/null

refresh_authenticated_csrf() {
  local phase="$1"
  local response_file="$work_dir/csrf-authenticated-$phase.json"
  local status

  status="$(
    curl_request       --cookie "$work_dir/cookies.txt"       --cookie-jar "$work_dir/cookies.txt"       --output "$response_file"       --write-out '%{http_code}'       "$api_url/api/v1/auth/csrf"
  )"
  assert_equal "CSRF autenticado ($phase)" "$status" "200"

  mapfile -t csrf < <(
    node - "$response_file" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (
  typeof value.requestToken !== 'string' ||
  value.requestToken.length === 0 ||
  typeof value.headerName !== 'string' ||
  value.headerName.length === 0
) {
  process.exit(1);
}
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
  )

  if [[ "${#csrf[@]}" -ne 2 ]]; then
    fail_check "Contrato CSRF autenticado incompleto en fase '$phase'."
  fi
}

catalog_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/catalog.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/security/role-assignments/catalog"
)"
assert_equal "catálogo protegido" "$catalog_status" "200"

valid_until="$(node -e "console.log(new Date(Date.now() + 30*60*1000).toISOString())")"
node - "$target_id" "$valid_until" >"$work_dir/grant.json" <<'NODE'
const [accountId, validUntil] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  accountId,
  roleCode: 'EDITOR',
  scopeId: null,
  validUntil,
  reason: 'BL-MVP-031 smoke grant',
}));
NODE

refresh_authenticated_csrf "grant"

grant_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/grant-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "Idempotency-Key: bl031-grant-$target_id" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/grant.json" \
    "$api_url/api/v1/security/role-assignments"
)"
if [[ "$grant_status" != "201" ]]; then
  echo "Respuesta HTTP del grant autorizado:" >&2
  cat "$work_dir/grant-response.json" >&2 || true
  echo >&2
  fail_check "grant autorizado esperaba '201' y obtuvo '$grant_status'."
fi

created_assignment_id="$(
  node - "$work_dir/grant-response.json" <<'NODE'
const fs = require('node:fs');
const response = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (response.alreadyApplied !== false) process.exit(1);
process.stdout.write(response.assignment.assignmentId);
NODE
)"

refresh_authenticated_csrf "retry-grant"

retry_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/grant-retry.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/grant.json" \
    "$api_url/api/v1/security/role-assignments"
)"
assert_equal "grant idempotente" "$retry_status" "200"

node - "$target_id" "$valid_until" >"$work_dir/overlap.json" <<'NODE'
const [accountId, validUntil] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  accountId,
  roleCode: 'EDITOR',
  scopeId: null,
  validUntil,
  reason: 'Motivo diferente que debe chocar',
}));
NODE

refresh_authenticated_csrf "overlap"

overlap_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/overlap-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/overlap.json" \
    "$api_url/api/v1/security/role-assignments"
)"
assert_equal "solape rechazado" "$overlap_status" "409"

node - "$work_dir/overlap-response.json" <<'NODE'
const fs = require('node:fs');
const problem = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (problem.code !== 'security.role-assignment.overlap') process.exit(1);
NODE

list_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/list.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/security/role-assignments/$target_id"
)"
assert_equal "consulta de asignaciones" "$list_status" "200"

node - "$work_dir/list.json" "$created_assignment_id" <<'NODE'
const fs = require('node:fs');
const list = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const id = process.argv[3];
const assignment = list.find((candidate) => candidate.assignmentId === id);
if (!assignment || assignment.roleCode !== 'EDITOR' || assignment.state !== 'ACTIVE') process.exit(1);
NODE

node >"$work_dir/revoke.json" <<'NODE'
process.stdout.write(JSON.stringify({
  reason: 'BL-MVP-031 smoke revoke',
}));
NODE

refresh_authenticated_csrf "revoke"

revoke_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/revoke-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/revoke.json" \
    "$api_url/api/v1/security/role-assignments/$created_assignment_id/revoke"
)"
assert_equal "revocación autorizada" "$revoke_status" "200"

refresh_authenticated_csrf "retry-revoke"

retry_revoke_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/revoke-retry.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/revoke.json" \
    "$api_url/api/v1/security/role-assignments/$created_assignment_id/revoke"
)"
assert_equal "revocación idempotente" "$retry_revoke_status" "200"

node - "$work_dir/revoke-retry.json" <<'NODE'
const fs = require('node:fs');
const response = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (response.alreadyApplied !== true) process.exit(1);
NODE

audit_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.audit_event
WHERE object_type = 'ROLE_ASSIGNMENT'
  AND object_id = '$created_assignment_id'::uuid
  AND action_code IN (
      'SECURITY.ROLE_ASSIGNMENT.GRANT',
      'SECURITY.ROLE_ASSIGNMENT.REVOKE'
  );
" | tr -d '[:space:]'
)"
assert_equal "auditoría grant+revoke" "$audit_count" "2"

effective_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.role_assignment ra
JOIN security.role r ON r.role_id = ra.role_id
WHERE ra.assignment_id = '$created_assignment_id'::uuid
  AND r.role_code = 'EDITOR'
  AND ra.valid_from <= CURRENT_TIMESTAMP
  AND (ra.valid_to IS NULL OR ra.valid_to > CURRENT_TIMESTAMP);
" | tr -d '[:space:]'
)"
assert_equal "retiro efectivo inmediato" "$effective_count" "0"

node - "$admin_account_id" >"$work_dir/self-grant.json" <<'NODE'
const accountId = process.argv[2];
process.stdout.write(JSON.stringify({
  accountId,
  roleCode: 'ADMIN',
  scopeId: null,
  validUntil: null,
  reason: 'Debe rechazarse',
}));
NODE

refresh_authenticated_csrf "self-grant"

self_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/self-response.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/self-grant.json" \
    "$api_url/api/v1/security/role-assignments"
)"
assert_equal "autoasignación bloqueada" "$self_status" "409"

node - "$work_dir/self-response.json" <<'NODE'
const fs = require('node:fs');
const problem = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (problem.code !== 'security.role-assignment.self-change') process.exit(1);
NODE

printf '%s\n' \
  "BL-MVP-031 role assignment verification" \
  "admin=$admin_account_id" \
  "target=$target_id" \
  "assignment=$created_assignment_id" \
  "grant=201" \
  "retry-grant=200" \
  "overlap=409" \
  "revoke=200" \
  "retry-revoke=200" \
  "audit-events=2" \
  "effective-after-revoke=0" \
  "self-change=409" \
  > artifacts/postgres/role-assignment-summary.txt

echo "OK: BL-MVP-031 asignación/revocación, vigencia, solape, autoelevación y auditoría verificados."
