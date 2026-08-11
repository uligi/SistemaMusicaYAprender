#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

api_url="${BL034_API_URL:-https://localhost:5450}"
work_dir="$(mktemp -d)"
email="bl034-$(openssl rand -hex 10)@example.test"
password="Preferencias 日本語 seguras 2026"
registration_key="bl034-$(openssl rand -hex 16)"
correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
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
  echo "ERROR: BL-MVP-034: $1" >&2
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

if [[ "${BL034_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

if [[ "${BL034_USE_RUNNING_API:-false}" != "true" ]]; then
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
  || fail_check "No se resolvieron consentimientos obligatorios."

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
    --header "X-Correlation-Id: $correlation_id" \
    --data-binary "@$work_dir/register.json" \
    "$api_url/api/v1/auth/register"
)"
assert_equal "registro con preferencias iniciales" "$register_status" "202"

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

initial_state="$(
  "${psql_base[@]}" --command="
SELECT concat(
    profile.ui_language, '|',
    profile.time_zone, '|',
    preference.version, '|',
    revision.revision_no, '|',
    revision.values ->> 'interfaceLanguage', '|',
    revision.values ->> 'translationLanguage', '|',
    revision.values #>> '{privacy,activityVisibility}', '|',
    revision.values #>> '{accessibility,reducedMotion}', '|',
    revision.values #>> '{accessibility,flashProtection}', '|',
    revision.values #>> '{provenance,contractVersion}'
)
FROM identity.user_profile AS profile
INNER JOIN identity.preference_set AS preference
    ON preference.account_id = profile.account_id
INNER JOIN identity.preference_revision AS revision
    ON revision.revision_id = preference.current_revision_id
WHERE profile.account_id = '$account_id'::uuid;
" | tr -d '[:space:]'
)"
assert_equal \
  "perfil y revisión inicial segura" \
  "$initial_state" \
  "es-CR|America/Costa_Rica|1|1|ES|ES|PRIVATE|true|true|1"

sensitive_count="$(
  "${psql_base[@]}" --command="
SELECT count(*)
FROM identity.preference_revision
WHERE preference_set_id = (
    SELECT preference_set_id
    FROM identity.preference_set
    WHERE account_id = '$account_id'::uuid
)
AND lower(values::text) ~ '(password|credential|secret|token|email)';
" | tr -d '[:space:]'
)"
assert_equal "sin credenciales en preferencias" "$sensitive_count" "0"

"${psql_base[@]}" --command="
UPDATE security.account
SET status_code = 'ACTIVE',
    verified_at = CURRENT_TIMESTAMP
WHERE account_id = '$account_id'::uuid;
" >/dev/null

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

node - "$email" "$password" >"$work_dir/login.json" <<'NODE'
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
    --data-binary "@$work_dir/login.json" \
    "$api_url/api/v1/auth/login"
)"
assert_equal "login para preferencias" "$login_status" "200"

get_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/preferences.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/preferences"
)"
assert_equal "lectura de preferencias propias" "$get_status" "200"

node - "$work_dir/preferences.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (
  value.version !== 1 ||
  value.revisionNo !== 1 ||
  value.profile.uiLanguage !== 'es-CR' ||
  value.profile.timeZone !== 'America/Costa_Rica' ||
  value.values.interfaceLanguage !== 'ES' ||
  value.values.translationLanguage !== 'ES' ||
  value.values.privacy.activityVisibility !== 'PRIVATE' ||
  value.options.languages?.[0]?.code !== 'ES'
) process.exit(1);
NODE

curl_request \
  --cookie "$work_dir/cookies.txt" \
  --cookie-jar "$work_dir/cookies.txt" \
  --output "$work_dir/csrf-put.json" \
  "$api_url/api/v1/auth/csrf"

mapfile -t csrf < <(
  node - "$work_dir/csrf-put.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

cat >"$work_dir/update.json" <<'JSON'
{
  "version": 1,
  "interfaceLanguage": "ES",
  "translationLanguage": "ES",
  "japanese": {
    "showKanji": true,
    "showKana": true,
    "furiganaMode": "ALWAYS",
    "romajiMode": "HIDDEN",
    "showNaturalTranslation": true
  },
  "accessibility": {
    "fontScalePercent": 150,
    "highContrast": true,
    "reducedMotion": true,
    "flashProtection": true
  },
  "privacy": {
    "activityVisibility": "PRIVATE"
  }
}
JSON

put_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/preferences-updated.json" \
    --write-out '%{http_code}' \
    --request PUT \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/update.json" \
    "$api_url/api/v1/preferences"
)"
assert_equal "confirmación de nueva revisión" "$put_status" "200"

node - "$work_dir/preferences-updated.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (
  value.version !== 2 ||
  value.revisionNo !== 2 ||
  value.values.japanese.furiganaMode !== 'ALWAYS' ||
  value.values.japanese.romajiMode !== 'HIDDEN' ||
  value.values.accessibility.fontScalePercent !== 150 ||
  value.values.accessibility.highContrast !== true ||
  value.values.privacy.activityVisibility !== 'PRIVATE'
) process.exit(1);
NODE

revision_state="$(
  "${psql_base[@]}" --command="
SELECT concat(
    preference.version, '|',
    count(revision.revision_id), '|',
    max(revision.revision_no)
)
FROM identity.preference_set AS preference
INNER JOIN identity.preference_revision AS revision
    ON revision.preference_set_id = preference.preference_set_id
WHERE preference.account_id = '$account_id'::uuid
GROUP BY preference.version;
" | tr -d '[:space:]'
)"
assert_equal "historial inmutable y cabeza v2" "$revision_state" "2|2|2"

curl_request \
  --cookie "$work_dir/cookies.txt" \
  --cookie-jar "$work_dir/cookies.txt" \
  --output "$work_dir/csrf-invalid.json" \
  "$api_url/api/v1/auth/csrf"

mapfile -t csrf < <(
  node - "$work_dir/csrf-invalid.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

node - "$work_dir/update.json" >"$work_dir/invalid.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
value.version = 2;
value.interfaceLanguage = 'EN';
process.stdout.write(JSON.stringify(value));
NODE

invalid_status="$(
  curl_request \
    --cookie "$work_dir/cookies.txt" \
    --output "$work_dir/problem.json" \
    --write-out '%{http_code}' \
    --request PUT \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/invalid.json" \
    "$api_url/api/v1/preferences"
)"
assert_equal "idioma no publicado rechazado" "$invalid_status" "400"

unchanged_state="$(
  "${psql_base[@]}" --command="
SELECT concat(
    preference.version, '|',
    count(revision.revision_id), '|',
    max(revision.revision_no)
)
FROM identity.preference_set AS preference
INNER JOIN identity.preference_revision AS revision
    ON revision.preference_set_id = preference.preference_set_id
WHERE preference.account_id = '$account_id'::uuid
GROUP BY preference.version;
" | tr -d '[:space:]'
)"
assert_equal "valor inválido conserva última revisión" "$unchanged_state" "2|2|2"

# RLS: otro contexto de cuenta no puede observar las preferencias de la primera.
other_account_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
cross_count="$(
  "${psql_base[@]}" --command="
BEGIN;
SET LOCAL ROLE jp_app;
SELECT set_config('app.account_id', '$other_account_id', true);
SELECT set_config('app.role_code', 'STUDENT', true);
SELECT set_config('app.correlation_id', 'bl034-rls-check', true);
SELECT count(*)
FROM identity.preference_set
WHERE account_id = '$account_id'::uuid;
ROLLBACK;
" | grep -E '^[0-9]+$' | tail -n 1 | tr -d '[:space:]'
)"
assert_equal "RLS impide lectura cruzada" "$cross_count" "0"

# Cerrar y volver a entrar: el servidor conserva la revisión confirmada.
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
    "$api_url/api/v1/auth/logout"
)"
assert_equal "logout previo a continuidad" "$logout_status" "200"

curl_request \
  --cookie-jar "$work_dir/cookies-2.txt" \
  --output "$work_dir/csrf-login-2.json" \
  "$api_url/api/v1/auth/csrf"

mapfile -t csrf < <(
  node - "$work_dir/csrf-login-2.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
process.stdout.write(`${value.requestToken}\n${value.headerName}\n`);
NODE
)

login_again="$(
  curl_request \
    --cookie "$work_dir/cookies-2.txt" \
    --cookie-jar "$work_dir/cookies-2.txt" \
    --output "$work_dir/login-again.json" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "${csrf[1]}: ${csrf[0]}" \
    --data-binary "@$work_dir/login.json" \
    "$api_url/api/v1/auth/login"
)"
assert_equal "nuevo login para continuidad" "$login_again" "200"

resume_status="$(
  curl_request \
    --cookie "$work_dir/cookies-2.txt" \
    --output "$work_dir/preferences-resumed.json" \
    --write-out '%{http_code}' \
    "$api_url/api/v1/preferences"
)"
assert_equal "preferencias tras nueva sesión" "$resume_status" "200"

node - "$work_dir/preferences-resumed.json" <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (
  value.version !== 2 ||
  value.revisionNo !== 2 ||
  value.values.japanese.furiganaMode !== 'ALWAYS' ||
  value.values.accessibility.fontScalePercent !== 150
) process.exit(1);
NODE

echo "OK: BL-MVP-034 perfil separado, defaults seguros, revisión confirmada, validación, privacidad RLS y continuidad verificados."
