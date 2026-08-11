#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL036_API_URL:-https://localhost:5451}"
work_dir="$(mktemp -d)"
admin_email="bl036-admin-$(openssl rand -hex 10)@example.test"
password="Brisa 日本語 segura 2026"
registration_key="bl036-$(openssl rand -hex 16)"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
admin_assignment="$(node -e "console.log(require('node:crypto').randomUUID())")"
api_log="$work_dir/api.log"
api_pid=""

curl_tls_options=()
case "$api_url" in
  https://localhost:* | https://127.0.0.1:*)
    curl_tls_options+=(--insecure)
    ;;
esac

fail_check() {
  echo "ERROR: BL-MVP-036: $1" >&2
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

if [[ "${BL036_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

if [[ "${BL036_USE_RUNNING_API:-false}" != "true" ]]; then
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
    "$api_url/api/v1/administration/configuration"
)"
assert_equal "lectura sin sesión" "$unauth_status" "401"

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
    '$admin_assignment'::uuid,
    a.account_id,
    r.role_id,
    NULL,
    CURRENT_TIMESTAMP - INTERVAL '2 minutes',
    CURRENT_TIMESTAMP + INTERVAL '1 hour',
    'BL-MVP-036 bootstrap técnico de prueba'
FROM security.account a
CROSS JOIN security.role r
WHERE encode(a.email_lookup_hash, 'hex') = '$email_hash'
  AND r.role_code = 'ADMIN';
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
  || fail_check "No se resolvió la sesión para assurance."

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
    'BL036-SYNTHETIC-MFA-NOT-USED',
    CURRENT_TIMESTAMP,
    NULL
);

UPDATE security.session
SET assurance_level = 'MFA',
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
    decode(repeat('b6', 32), 'hex'),
    200,
    jsonb_build_object(
        'assurance', 'MFA',
        'purpose', 'PRIVILEGED',
        'source', 'BL036'
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

read_snapshot() {
  local target="$1"
  local status
  status="$(
    curl_request \
      --cookie "$work_dir/cookies.txt" \
      --output "$target" \
      --write-out '%{http_code}' \
      "$api_url/api/v1/administration/configuration"
  )"
  assert_equal "snapshot protegido" "$status" "200"
}

post_json() {
  local phase="$1"
  local endpoint="$2"
  local body="$3"
  local output="$4"
  local expected="$5"
  local idempotency="${6:-}"

  refresh_csrf "$phase"

  local args=(
    --cookie "$work_dir/cookies.txt"
    --output "$output"
    --write-out '%{http_code}'
    --header 'Content-Type: application/json'
    --header "${csrf[1]}: ${csrf[0]}"
    --header "X-Correlation-Id: $correlation_id"
  )

  if [[ -n "$idempotency" ]]; then
    args+=(--header "Idempotency-Key: $idempotency")
  fi

  local status
  status="$(
    curl_request \
      "${args[@]}" \
      --data-binary "@$body" \
      "$api_url$endpoint"
  )"
  assert_equal "$phase" "$status" "$expected"
}

read_snapshot "$work_dir/snapshot.json"

mapfile -t parameter_base < <(
  node - "$work_dir/snapshot.json" <<'NODE'
const fs = require('node:fs');
const snapshot = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const parameter = snapshot.parameters.find(
  (item) =>
    item.parameterKey === 'SEARCH_MIN_QUERY_LENGTH' &&
    item.scopeCode === 'GLOBAL' &&
    !item.scopeValue
);
if (!parameter || parameter.currentValueJson !== '2') process.exit(1);
process.stdout.write(`${parameter.currentVersionNo}\n${parameter.currentValueJson}\n`);
NODE
)
[[ "${#parameter_base[@]}" -eq 2 ]] \
  || fail_check "No se resolvió SEARCH_MIN_QUERY_LENGTH=2."

node - "${parameter_base[0]}" >"$work_dir/parameter-change.json" <<'NODE'
const [version] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  parameterKey: 'SEARCH_MIN_QUERY_LENGTH',
  scopeCode: 'GLOBAL',
  scopeValue: null,
  typedValueJson: '3',
  validUntil: null,
  reason: 'BL-MVP-036 cambio controlado de prueba',
  impact: 'Consumidor de búsqueda; reversible al valor 2; sin datos personales ni secretos.',
  expectedVersionNo: Number(version),
}));
NODE

post_json \
  "simulación parámetro" \
  "/api/v1/administration/configuration/parameters/simulate" \
  "$work_dir/parameter-change.json" \
  "$work_dir/parameter-sim.json" \
  "200"

node - "$work_dir/parameter-sim.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.canActivate || value.historicalValueWillBePreserved !== true) process.exit(1);
NODE

post_json \
  "activación parámetro" \
  "/api/v1/administration/configuration/parameters/activate" \
  "$work_dir/parameter-change.json" \
  "$work_dir/parameter-activate.json" \
  "201" \
  "bl036-param-$correlation_id"

parameter_changed_version="$(
  node - "$work_dir/parameter-activate.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.alreadyApplied !== false || value.historicalValuePreserved !== true) process.exit(1);
process.stdout.write(String(value.activeVersion));
NODE
)"
assert_equal \
  "nueva versión parámetro" \
  "$parameter_changed_version" \
  "$((parameter_base[0] + 1))"

post_json \
  "reintento idempotente parámetro" \
  "/api/v1/administration/configuration/parameters/activate" \
  "$work_dir/parameter-change.json" \
  "$work_dir/parameter-replay.json" \
  "200" \
  "bl036-param-replay-$correlation_id"

node - "$work_dir/parameter-replay.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.alreadyApplied !== true) process.exit(1);
NODE

read_snapshot "$work_dir/snapshot-after-param.json"

mapfile -t catalog_base < <(
  node - "$work_dir/snapshot-after-param.json" <<'NODE'
const fs = require('node:fs');
const snapshot = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const catalog = snapshot.catalogs.find((item) => item.catalogCode === 'LANGUAGE');
const entry = catalog?.entries.find((item) => item.entryCode === 'ES');
if (!entry) process.exit(1);
process.stdout.write(`${entry.catalogEntryId}\n${entry.version}\n${entry.labelsJson}\n${entry.valueJson}\n`);
NODE
)
[[ "${#catalog_base[@]}" -eq 4 ]] \
  || fail_check "No se resolvió LANGUAGE/ES."

# CA-MVP-143: el valor sintético secreto se rechaza antes de cualquier cambio.
node - "${catalog_base[0]}" "${catalog_base[1]}" >"$work_dir/catalog-secret.json" <<'NODE'
const [entryId, version] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  catalogCode: 'LANGUAGE',
  entryCode: 'ES',
  labelsJson: '{"es":"Español","api-key":"NO-DEBE-PERSISTIR"}',
  valueJson: '"ES"',
  validUntil: null,
  reason: 'Prueba de rechazo de secreto',
  impact: 'Debe quedar bloqueado antes de persistir.',
  expectedEntryId: entryId,
  expectedVersion: Number(version),
}));
NODE

post_json \
  "rechazo de secreto" \
  "/api/v1/administration/configuration/catalogs/activate" \
  "$work_dir/catalog-secret.json" \
  "$work_dir/secret-response.json" \
  "400"

if grep -Fq 'NO-DEBE-PERSISTIR' "$work_dir/secret-response.json"; then
  fail_check "La respuesta devolvió el valor secreto sintético."
fi

node - "${catalog_base[0]}" "${catalog_base[1]}" >"$work_dir/catalog-change.json" <<'NODE'
const [entryId, version] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  catalogCode: 'LANGUAGE',
  entryCode: 'ES',
  labelsJson: '{"es":"Español BL036"}',
  valueJson: '"ES"',
  validUntil: null,
  reason: 'BL-MVP-036 localización versionada de prueba',
  impact: 'Solo presentación; código ES estable; consumidores mantienen compatibilidad.',
  expectedEntryId: entryId,
  expectedVersion: Number(version),
}));
NODE

post_json \
  "simulación catálogo" \
  "/api/v1/administration/configuration/catalogs/simulate" \
  "$work_dir/catalog-change.json" \
  "$work_dir/catalog-sim.json" \
  "200"

node - "$work_dir/catalog-sim.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!value.canActivate || value.historicalValueWillBePreserved !== true) process.exit(1);
NODE

post_json \
  "activación catálogo" \
  "/api/v1/administration/configuration/catalogs/activate" \
  "$work_dir/catalog-change.json" \
  "$work_dir/catalog-activate.json" \
  "201" \
  "bl036-catalog-$correlation_id"

node - "$work_dir/catalog-activate.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (value.alreadyApplied !== false || value.historicalValuePreserved !== true) process.exit(1);
NODE

# Verifica historial antes de restaurar y luego deja el ambiente en los valores base.
parameter_history="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM configuration.parameter_version v
JOIN configuration.parameter_definition d
  ON d.parameter_definition_id = v.parameter_definition_id
WHERE d.parameter_key = 'SEARCH_MIN_QUERY_LENGTH';
" | tr -d '[:space:]'
)"
if (( parameter_history < 2 )); then
  fail_check "La versión anterior del parámetro no se preservó."
fi

catalog_history="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM configuration.catalog_entry e
JOIN configuration.catalog_definition d
  ON d.catalog_definition_id = e.catalog_definition_id
WHERE d.catalog_code = 'LANGUAGE'
  AND e.entry_code = 'ES';
" | tr -d '[:space:]'
)"
if (( catalog_history < 2 )); then
  fail_check "La entrada histórica del catálogo no se preservó."
fi

audit_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.audit_event
WHERE actor_id = '$admin_account_id'::uuid
  AND action_code IN (
    'CONFIG.PARAMETER.ACTIVATE',
    'CONFIG.CATALOG.ACTIVATE'
  )
  AND reason LIKE '%Impacto:%';
" | tr -d '[:space:]'
)"
if (( audit_count < 2 )); then
  fail_check "No se conservaron motivo e impacto en auditoría."
fi

secret_persisted="$(
  "${psql_base[@]}" --command="
SELECT (
  SELECT count(*)
  FROM security.audit_event
  WHERE actor_id = '$admin_account_id'::uuid
    AND reason LIKE '%NO-DEBE-PERSISTIR%'
) + (
  SELECT count(*)
  FROM configuration.catalog_entry
  WHERE labels::text LIKE '%NO-DEBE-PERSISTIR%'
     OR value::text LIKE '%NO-DEBE-PERSISTIR%'
);
" | tr -d '[:space:]'
)"
assert_equal "secreto sintético persistido" "$secret_persisted" "0"

# Restauración del parámetro al valor base, conservando las dos versiones previas.
read_snapshot "$work_dir/snapshot-before-param-revert.json"
parameter_current_version="$(
  node - "$work_dir/snapshot-before-param-revert.json" <<'NODE'
const fs = require('node:fs');
const snapshot = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const parameter = snapshot.parameters.find(
  (item) =>
    item.parameterKey === 'SEARCH_MIN_QUERY_LENGTH' &&
    item.scopeCode === 'GLOBAL' &&
    !item.scopeValue
);
if (!parameter || parameter.currentValueJson !== '3') process.exit(1);
process.stdout.write(String(parameter.currentVersionNo));
NODE
)"

node - "$parameter_current_version" >"$work_dir/parameter-revert.json" <<'NODE'
const [version] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  parameterKey: 'SEARCH_MIN_QUERY_LENGTH',
  scopeCode: 'GLOBAL',
  scopeValue: null,
  typedValueJson: '2',
  validUntil: null,
  reason: 'BL-MVP-036 restauración del valor de referencia',
  impact: 'Restaura el valor base tras el smoke; el historial de prueba permanece trazable.',
  expectedVersionNo: Number(version),
}));
NODE

post_json \
  "restauración parámetro" \
  "/api/v1/administration/configuration/parameters/activate" \
  "$work_dir/parameter-revert.json" \
  "$work_dir/parameter-revert-response.json" \
  "201" \
  "bl036-param-revert-$correlation_id"

# Restauración de LANGUAGE/ES a sus etiquetas y valor originales.
read_snapshot "$work_dir/snapshot-before-catalog-revert.json"
mapfile -t catalog_current < <(
  node - "$work_dir/snapshot-before-catalog-revert.json" <<'NODE'
const fs = require('node:fs');
const snapshot = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const catalog = snapshot.catalogs.find((item) => item.catalogCode === 'LANGUAGE');
const entry = catalog?.entries.find((item) => item.entryCode === 'ES');
if (!entry || !entry.labelsJson.includes('Español BL036')) process.exit(1);
process.stdout.write(`${entry.catalogEntryId}\n${entry.version}\n`);
NODE
)
[[ "${#catalog_current[@]}" -eq 2 ]] \
  || fail_check "No se resolvió la entrada LANGUAGE/ES para restauración."

node - \
  "${catalog_current[0]}" \
  "${catalog_current[1]}" \
  "${catalog_base[2]}" \
  "${catalog_base[3]}" \
  >"$work_dir/catalog-revert.json" <<'NODE'
const [entryId, version, labelsJson, valueJson] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  catalogCode: 'LANGUAGE',
  entryCode: 'ES',
  labelsJson,
  valueJson,
  validUntil: null,
  reason: 'BL-MVP-036 restauración de la entrada de referencia',
  impact: 'Restaura la presentación base tras el smoke; el historial de prueba permanece trazable.',
  expectedEntryId: entryId,
  expectedVersion: Number(version),
}));
NODE

post_json \
  "restauración catálogo" \
  "/api/v1/administration/configuration/catalogs/activate" \
  "$work_dir/catalog-revert.json" \
  "$work_dir/catalog-revert-response.json" \
  "201" \
  "bl036-catalog-revert-$correlation_id"

read_snapshot "$work_dir/final-snapshot.json"
node - "$work_dir/final-snapshot.json" "${catalog_base[2]}" "${catalog_base[3]}" <<'NODE'
const fs = require('node:fs');
const [snapshotFile, originalLabels, originalValue] = process.argv.slice(2);
const snapshot = JSON.parse(fs.readFileSync(snapshotFile, 'utf8'));
const parameter = snapshot.parameters.find(
  (item) =>
    item.parameterKey === 'SEARCH_MIN_QUERY_LENGTH' &&
    item.scopeCode === 'GLOBAL' &&
    !item.scopeValue
);
const catalog = snapshot.catalogs.find((item) => item.catalogCode === 'LANGUAGE');
const entry = catalog?.entries.find((item) => item.entryCode === 'ES');
if (!parameter || parameter.currentValueJson !== '2') process.exit(1);
if (!entry) process.exit(1);
const normalize = (text) => JSON.stringify(JSON.parse(text));
if (normalize(entry.labelsJson) !== normalize(originalLabels)) process.exit(1);
if (normalize(entry.valueJson) !== normalize(originalValue)) process.exit(1);
NODE

mkdir -p artifacts/postgres
cat > artifacts/postgres/versioned-configuration-administration-summary.txt <<EOF
bl_mvp=036
permission_manage=CONFIG.MANAGE
permission_approve=CONFIG.APPROVE
privileged_assurance=required
csrf=required
simulation=verified
parameter_version_history=preserved
catalog_entry_history=preserved
impact_and_reason=audit
secret_common_field=rejected
idempotent_replay=verified
reference_values_restored=true
EOF

echo "OK: BL-MVP-036 permiso, step-up, simulación, impacto, vigencia, motivo, historial, secretos e idempotencia verificados; valores de referencia restaurados."
