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

api_url="${BL029_API_URL:-https://localhost:5445}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
: > "$api_log"

email="bl029-$(openssl rand -hex 12)@example.test"
unknown_email="unknown-$(openssl rand -hex 12)@example.test"
password="Límite 日本語 seguro 2026"
wrong_password="Límite 日本語 incorrecto 2026"
registration_key="bl029-$(openssl rand -hex 16)"
threshold_correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
recovery_correlation_id="$(node -e "console.log(require('node:crypto').randomUUID())")"
current_correlation_id="$threshold_correlation_id"
client_prefix="$(openssl rand -hex 4)"
account_client="2001:db8:${client_prefix:0:4}:${client_prefix:4:4}::10"
unknown_client="2001:db8:${client_prefix:0:4}:${client_prefix:4:4}::11"
ip_limit_client="2001:db8:${client_prefix:0:4}:${client_prefix:4:4}::12"
recovery_client="2001:db8:${client_prefix:0:4}:${client_prefix:4:4}::13"
threshold_window_seconds=300
recovery_window_seconds=5

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
  echo "ERROR: BL-MVP-029: $message" >&2
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

problem_fingerprint() {
  local response_path="$1"
  local expected_status="$2"
  local expected_code="$3"

  node - "$response_path" "$expected_status" "$expected_code" <<'NODE'
const fs = require('node:fs');
const [path, expectedStatus, expectedCode] = process.argv.slice(2);
const problem = JSON.parse(fs.readFileSync(path, 'utf8'));
if (problem.status !== Number(expectedStatus) || problem.code !== expectedCode) process.exit(1);
for (const key of ['title', 'detail']) {
  if (typeof problem[key] !== 'string' || problem[key].length === 0) process.exit(1);
}
process.stdout.write([problem.status, problem.title, problem.detail, problem.code].join('|'));
NODE
}

write_login_request() {
  local target_email="$1"
  local target_password="$2"
  local output_path="$3"

  node - "$target_email" "$target_password" > "$output_path" <<'NODE'
const [email, password] = process.argv.slice(2);
process.stdout.write(JSON.stringify({ email, password }));
NODE
}

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
if [[ ! "$lookup_key_hex" =~ ^[0-9a-fA-F]{64}$ ]]; then
  fail_check "identity_email_lookup_key no contiene 32 bytes hexadecimales."
fi

abuse_key_hex="$(tr -d '[:space:]' < secrets/local/identity_login_abuse_key)"
if [[ ! "$abuse_key_hex" =~ ^[0-9a-fA-F]{64}$ ]]; then
  fail_check "identity_login_abuse_key no contiene 32 bytes hexadecimales."
fi

email_hash="$({
  printf '%s' "${email^^}" |
    openssl dgst -sha256 -mac HMAC -macopt "hexkey:$lookup_key_hex" -binary |
    od -An -vtx1 |
    tr -d ' \n'
})"

if [[ "${BL029_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

  # security.security_event, consent_record y job_attempt son evidencia append-only.
  # El fixture usa correo, correlación y clientes sintéticos únicos por ejecución, por lo
  # que se conserva la evidencia en lugar de deshabilitar sus protecciones físicas.

  rm -rf "$work_dir"
}

trap cleanup EXIT

start_api() {
  local configured_window="$1"

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
  Security__LoginAbuse__AccountFailureLimit=5 \
  Security__LoginAbuse__ClientFailureLimit=20 \
  Security__LoginAbuse__WindowSeconds="$configured_window" \
  Security__LoginAbuse__TrustClientAddressHeader=true \
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

  for attempt in $(seq 1 30); do
    if curl_request --fail --silent "$api_url/health/live" >/dev/null; then
      return
    fi

    if [[ "$attempt" -eq 30 ]]; then
      tail -80 "$api_log" >&2
      fail_check "la API standalone no quedo disponible."
    fi

    sleep 1
  done
}

stop_api() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" >/dev/null 2>&1 || true
    wait "$api_pid" >/dev/null 2>&1 || true
    api_pid=""
  fi
}

start_api "$threshold_window_seconds"

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
  fail_check "la API no publicó los avisos requeridos."
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
assert_equal "alta de cuenta sintética" "$registration_status" "202"

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
  fail_check "no se pudo activar la cuenta sintética."
fi

csrf_status="$(curl_request \
  --silent \
  --show-error \
  --dump-header "$work_dir/csrf-headers.txt" \
  --output "$work_dir/csrf.json" \
  --write-out '%{http_code}' \
  "$api_url/api/v1/auth/csrf")"
assert_equal "emisión CSRF" "$csrf_status" "200"

mapfile -t csrf_contract < <(
  node - "$work_dir/csrf.json" <<'NODE'
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

csrf_token="${csrf_contract[0]}"
csrf_header_name="${csrf_contract[1]}"
csrf_cookie_header="$(tr -d '\r' < "$work_dir/csrf-headers.txt" |
  grep -i '^set-cookie: __Host-MusicaAprender.Csrf=' |
  head -n 1)"
csrf_cookie_pair="$(cut -d: -f2- <<<"$csrf_cookie_header" | sed 's/^ *//' | cut -d';' -f1)"

login_request() {
  local request_path="$1"
  local client_address="$2"
  local response_path="$3"
  local headers_path="$4"

  curl_request \
    --silent \
    --show-error \
    --dump-header "$headers_path" \
    --output "$response_path" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "$csrf_header_name: $csrf_token" \
    --header "X-Correlation-Id: $current_correlation_id" \
    --header "X-Musica-Client-Address: $client_address" \
    --cookie "$csrf_cookie_pair" \
    --data-binary "@$request_path" \
    "$api_url/api/v1/auth/login"
}

write_login_request "$email" "$wrong_password" "$work_dir/known-wrong.json"
write_login_request "$unknown_email" "$wrong_password" "$work_dir/unknown-wrong.json"

for attempt in $(seq 1 5); do
  status="$(login_request \
    "$work_dir/known-wrong.json" \
    "$account_client" \
    "$work_dir/known-$attempt.json" \
    "$work_dir/known-$attempt.headers")"
  assert_equal "fallo conocido $attempt/5" "$status" "401"
done

known_failure_count="$({
  "${psql_base[@]}" --command="
SELECT count(*)
FROM security.security_event
WHERE correlation_id = '$threshold_correlation_id'
  AND event_type = 'LOGIN_FAILURE_ACCOUNT';
"
} | tr -d '[:space:]')"
assert_equal "persistencia de cinco fallos conocidos" "$known_failure_count" "5"

known_limited_status="$(login_request \
  "$work_dir/known-wrong.json" \
  "$account_client" \
  "$work_dir/known-limited.json" \
  "$work_dir/known-limited.headers")"
assert_equal "límite por cuenta conocida" "$known_limited_status" "429"

for attempt in $(seq 1 5); do
  status="$(login_request \
    "$work_dir/unknown-wrong.json" \
    "$unknown_client" \
    "$work_dir/unknown-$attempt.json" \
    "$work_dir/unknown-$attempt.headers")"
  assert_equal "fallo desconocido $attempt/5" "$status" "401"
done

unknown_limited_status="$(login_request \
  "$work_dir/unknown-wrong.json" \
  "$unknown_client" \
  "$work_dir/unknown-limited.json" \
  "$work_dir/unknown-limited.headers")"
assert_equal "límite por clave de cuenta desconocida" "$unknown_limited_status" "429"

assert_equal \
  "respuesta 401 no enumerable" \
  "$(problem_fingerprint "$work_dir/known-1.json" 401 identity.login.failed)" \
  "$(problem_fingerprint "$work_dir/unknown-1.json" 401 identity.login.failed)"

assert_equal \
  "respuesta 429 no enumerable" \
  "$(problem_fingerprint "$work_dir/known-limited.json" 429 identity.login.rate-limited)" \
  "$(problem_fingerprint "$work_dir/unknown-limited.json" 429 identity.login.rate-limited)"

retry_after="$(tr -d '\r' < "$work_dir/known-limited.headers" |
  awk -F': ' 'tolower($1) == "retry-after" { print $2; exit }')"
if [[ ! "$retry_after" =~ ^[0-9]+$ ]] || [[ "$retry_after" -lt 1 ]] || [[ "$retry_after" -gt "$threshold_window_seconds" ]]; then
  fail_check "Retry-After no quedó dentro de la ventana configurada."
fi

for attempt in $(seq 1 20); do
  ip_email="ip-${attempt}-$(openssl rand -hex 4)@example.test"
  write_login_request "$ip_email" "$wrong_password" "$work_dir/ip-$attempt.request.json"
  status="$(login_request \
    "$work_dir/ip-$attempt.request.json" \
    "$ip_limit_client" \
    "$work_dir/ip-$attempt.json" \
    "$work_dir/ip-$attempt.headers")"
  assert_equal "fallo IP $attempt/20" "$status" "401"
done

ip_email="ip-21-$(openssl rand -hex 4)@example.test"
write_login_request "$ip_email" "$wrong_password" "$work_dir/ip-21.request.json"
ip_limited_status="$(login_request \
  "$work_dir/ip-21.request.json" \
  "$ip_limit_client" \
  "$work_dir/ip-limited.json" \
  "$work_dir/ip-limited.headers")"
assert_equal "límite por IP" "$ip_limited_status" "429"

threshold_event_contract="$({
  "${psql_base[@]}" --command="
SELECT
  count(*) FILTER (WHERE event_type = 'LOGIN_FAILURE_ACCOUNT') = 30
  AND count(*) FILTER (WHERE event_type = 'LOGIN_FAILURE_CLIENT') = 30
  AND count(*) FILTER (WHERE event_type = 'LOGIN_RATE_LIMITED') = 3
  AND bool_and(octet_length(client_fingerprint) = 32)
FROM security.security_event
WHERE correlation_id = '$threshold_correlation_id';
"
} | tr -d '[:space:]')"
assert_equal "eventos de umbral 5/20 seudonimizados" "$threshold_event_contract" "t"

stop_api
: > "$api_log"
current_correlation_id="$recovery_correlation_id"
start_api "$recovery_window_seconds"

recovery_email="recovery-$(openssl rand -hex 12)@example.test"
write_login_request "$recovery_email" "$wrong_password" "$work_dir/recovery.request.json"

for attempt in $(seq 1 5); do
  status="$(login_request \
    "$work_dir/recovery.request.json" \
    "$recovery_client" \
    "$work_dir/recovery-prime-$attempt.json" \
    "$work_dir/recovery-prime-$attempt.headers")"
  assert_equal "fallo de recuperacion $attempt/5" "$status" "401"
done

recovery_limited_status="$(login_request \
  "$work_dir/recovery.request.json" \
  "$recovery_client" \
  "$work_dir/recovery-limited.json" \
  "$work_dir/recovery-limited.headers")"
assert_equal "limite previo a recuperacion" "$recovery_limited_status" "429"

recovered=false
for attempt in $(seq 1 $((recovery_window_seconds + 5))); do
  sleep 1

  recovery_status="$(login_request \
    "$work_dir/recovery.request.json" \
    "$recovery_client" \
    "$work_dir/recovery-$attempt.json" \
    "$work_dir/recovery-$attempt.headers")"

  if [[ "$recovery_status" == "401" ]]; then
    recovered=true
    break
  fi

  if [[ "$recovery_status" != "429" ]]; then
    fail_check "la recuperacion automatica devolvio HTTP $recovery_status."
  fi
done

if [[ "$recovered" != "true" ]]; then
  fail_check "el limite no se recupero automaticamente al vencer la ventana corta de prueba."
fi

write_login_request "$email" "$password" "$work_dir/valid-login.request.json"
valid_status="$(login_request \
  "$work_dir/valid-login.request.json" \
  "$account_client" \
  "$work_dir/valid-login.json" \
  "$work_dir/valid-login.headers")"
assert_equal "login tras recuperación" "$valid_status" "200"

session_cookie_header="$(tr -d '\r' < "$work_dir/valid-login.headers" |
  grep -i '^set-cookie: __Host-MusicaAprender.Session=' |
  head -n 1)"
if [[ -z "$session_cookie_header" ]]; then
  fail_check "el login recuperado no emitió cookie de sesión."
fi
session_cookie_pair="$(cut -d: -f2- <<<"$session_cookie_header" | sed 's/^ *//' | cut -d';' -f1)"

session_status="$(curl_request \
  --silent \
  --show-error \
  --output "$work_dir/session-before-revoke.json" \
  --write-out '%{http_code}' \
  --cookie "$session_cookie_pair" \
  "$api_url/api/v1/auth/session")"
assert_equal "sesión activa tras recuperación" "$session_status" "200"

session_contract="$({
  "${psql_base[@]}" --command="
SELECT
  idle_expires_at > created_at
  AND idle_expires_at <= created_at + interval '12 hours'
  AND absolute_expires_at > idle_expires_at
  AND absolute_expires_at <= created_at + interval '30 days'
  AND revoked_at IS NULL
FROM security.session
WHERE account_id = '$account_id'
ORDER BY created_at DESC
LIMIT 1;
"
} | tr -d '[:space:]')"
assert_equal "límites temporales de sesión STUDENT" "$session_contract" "t"

recovery_event_contract="$({
  "${psql_base[@]}" --command="
SELECT
  count(*) FILTER (WHERE event_type = 'LOGIN_FAILURE_ACCOUNT') >= 6
  AND count(*) FILTER (WHERE event_type = 'LOGIN_FAILURE_CLIENT') >= 6
  AND count(*) FILTER (WHERE event_type = 'LOGIN_RATE_LIMITED') >= 1
  AND count(*) FILTER (WHERE event_type = 'LOGIN_SUCCESS') = 1
  AND bool_and(octet_length(client_fingerprint) = 32)
FROM security.security_event
WHERE correlation_id = '$recovery_correlation_id';
"
} | tr -d '[:space:]')"
assert_equal "eventos de recuperacion/login seudonimizados" "$recovery_event_contract" "t"

revoke_result="$({
  "${psql_base[@]}" --command="
SELECT security.revoke_active_session(session_hash)
FROM security.session
WHERE account_id = '$account_id'
  AND revoked_at IS NULL
ORDER BY created_at DESC
LIMIT 1;
"
} | tr -d '[:space:]')"
assert_equal "revocación explícita" "$revoke_result" "t"

session_after_revoke="$(curl_request \
  --silent \
  --show-error \
  --output "$work_dir/session-after-revoke.json" \
  --write-out '%{http_code}' \
  --cookie "$session_cookie_pair" \
  "$api_url/api/v1/auth/session")"
assert_equal "cookie revocada rechazada" "$session_after_revoke" "401"

cat > artifacts/postgres/login-abuse-summary.txt <<EOF
bl_mvp=029
account_failure_limit_default=5
client_failure_limit_default=20
window_default_seconds=900
threshold_test_window_seconds=$threshold_window_seconds
recovery_test_window_seconds=$recovery_window_seconds
known_failure_response=401-nonenumerable
unknown_failure_response=401-nonenumerable
account_rate_limit_response=429
client_rate_limit_response=429
retry_after_header=present
automatic_recovery=verified
security_event_fingerprint_bytes=32
student_idle_limit_hours=12
student_absolute_limit_days=30
revoked_session_response=401
EOF

if grep -F -R -q -e "$email" -e "$unknown_email" -e "$recovery_email" -e "$password" -e "$wrong_password" artifacts; then
  fail_check "datos sensibles del smoke aparecieron en evidencia persistente."
fi

echo "OK: BL-MVP-029 limites 5/cuenta y 20/IP, recuperacion independiente, eventos y sesion revocable verificados."
