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

api_url="${BL028_API_URL:-${BL024_API_URL:-http://127.0.0.1:5080}}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
key_one="bl024-$(openssl rand -hex 16)"
key_two="bl024-$(openssl rand -hex 16)"
key_stale="bl024-$(openssl rand -hex 16)"
key_missing="bl024-$(openssl rand -hex 16)"
key_rejected="bl024-$(openssl rand -hex 16)"
key_invalid="bl024-$(openssl rand -hex 16)"
key_short="bl028-$(openssl rand -hex 16)"
key_blocked="bl028-$(openssl rand -hex 16)"
email="bl024-$(openssl rand -hex 12)@example.test"
duplicate_email="${email^^}"
stale_email="stale-$email"
missing_email="missing-$email"
rejected_email="rejected-$email"
short_email="short-$email"
blocked_email="blocked-$email"
username="bl024$(openssl rand -hex 8)"
valid_password="Brisa 日本語 segura 2026"
changed_password="Brisa 日本語 segura 2027"

fail_check() {
  local message="$1"
  echo "ERROR: BL-MVP-028: $message" >&2
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

assert_nonempty() {
  local check_name="$1"
  local actual="$2"

  if [[ -z "$actual" ]]; then
    fail_check "$check_name no produjo un valor."
  fi
}

assert_contains() {
  local check_name="$1"
  local expected="$2"
  local file="$3"

  if ! grep -F -q -- "$expected" "$file"; then
    fail_check "$check_name no encontro el contrato esperado en la respuesta."
  fi
}

assert_files_equal() {
  local check_name="$1"
  local first="$2"
  local second="$3"

  if ! cmp --silent "$first" "$second"; then
    fail_check "$check_name produjo respuestas diferentes."
  fi
}

assert_count_delta() {
  local check_name="$1"
  local before="$2"
  local after="$3"
  local expected_delta="$4"

  if [[ ! "$before" =~ ^[0-9]+$ || ! "$after" =~ ^[0-9]+$ ]]; then
    fail_check "$check_name no obtuvo conteos enteros de PostgreSQL."
  fi

  local actual_delta=$((after - before))
  if [[ "$actual_delta" -ne "$expected_delta" ]]; then
    fail_check "$check_name esperaba delta $expected_delta y obtuvo $actual_delta."
  fi
}

assert_minimum_seconds() {
  local check_name="$1"
  local actual="$2"
  local minimum="$3"

  if ! node - "$actual" "$minimum" <<'NODE'
const actual = Number(process.argv[2]);
const minimum = Number(process.argv[3]);
process.exit(Number.isFinite(actual) && actual >= minimum ? 0 : 1);
NODE
  then
    fail_check "$check_name esperaba al menos $minimum s y obtuvo '$actual' s."
  fi
}

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
if [[ ! "$lookup_key_hex" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "ERROR: identity_email_lookup_key no contiene 32 bytes hexadecimales." >&2
  exit 1
fi

lookup_hash() {
  local candidate="$1"
  printf '%s' "${candidate^^}" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$lookup_key_hex" -binary \
    | od -An -vtx1 \
    | tr -d ' \n'
}

email_hash="$(lookup_hash "$email")"
stale_hash="$(lookup_hash "$stale_email")"
missing_hash="$(lookup_hash "$missing_email")"
rejected_hash="$(lookup_hash "$rejected_email")"

if [[ "${BL028_USE_DOCKER_PSQL:-${BL024_USE_DOCKER_PSQL:-false}}" == "true" ]]; then
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
DELETE FROM ops.job_attempt
WHERE job_id IN (
  SELECT job_id
  FROM ops.background_job
  WHERE payload->>'aggregateId' IN (
    SELECT account_id::text
    FROM security.account
    WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash')
  )
);
DELETE FROM ops.background_job
WHERE payload->>'aggregateId' IN (
  SELECT account_id::text
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash')
);
DELETE FROM ops.outbox_message
WHERE aggregate_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash')
);
DELETE FROM security.account_verification
WHERE account_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash')
);
ALTER TABLE identity.consent_record DISABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.consent_record
WHERE account_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash')
);
ALTER TABLE identity.consent_record ENABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.user_profile
WHERE account_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash')
);
DELETE FROM security.credential
WHERE account_id IN (
  SELECT account_id
  FROM security.account
  WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash')
);
DELETE FROM security.account
WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash');
COMMIT;
" >/dev/null 2>&1 || true

  "${psql_base[@]}" --command="
DELETE FROM ops.idempotency_record
WHERE account_id IS NULL
  AND idempotency_key IN (
    '$key_one', '$key_two', '$key_stale', '$key_missing', '$key_rejected', '$key_invalid',
    '$key_short', '$key_blocked'
  );
" >/dev/null 2>&1 || true

  rm -rf "$work_dir"
}

trap cleanup EXIT

before_accounts="$("${psql_base[@]}" --command="SELECT count(*) FROM security.account;")"
before_credentials="$("${psql_base[@]}" --command="SELECT count(*) FROM security.credential;")"
before_profiles="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.user_profile;")"
before_consents="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.consent_record;")"
before_verifications="$("${psql_base[@]}" --command="SELECT count(*) FROM security.account_verification;")"
before_outbox="$("${psql_base[@]}" --command="SELECT count(*) FROM ops.outbox_message WHERE event_name = 'email.delivery.requested';")"

if [[ "${BL028_USE_RUNNING_API:-${BL024_USE_RUNNING_API:-false}}" != "true" ]]; then
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
  ASPNETCORE_URLS="$api_url" \
  dotnet run \
    --project apps/api/MusicaAprender.Api.csproj \
    --configuration Release \
    --no-build \
    --no-restore \
    >"$api_log" 2>&1 &
  api_pid=$!
fi

for attempt in $(seq 1 30); do
  if curl --fail --silent "$api_url/health/live" >/dev/null; then
    break
  fi

  if [[ "$attempt" -eq 30 ]]; then
    tail -80 "$api_log" >&2
    exit 1
  fi

  sleep 1
done

curl \
  --fail \
  --silent \
  --show-error \
  --output "$work_dir/dependencies.json" \
  "$api_url/health/dependencies"

if ! grep -F -q '"name":"minimum-configuration","status":"Healthy"' "$work_dir/dependencies.json"; then
  echo "ERROR: minimum-configuration no reporto Healthy en /health/dependencies." >&2
  cat "$work_dir/dependencies.json" >&2
  exit 1
fi

curl \
  --fail \
  --silent \
  --show-error \
  --output "$work_dir/consent-catalog.json" \
  "$api_url/api/v1/auth/registration-consents"

mapfile -t notice_versions < <(
  node - "$work_dir/consent-catalog.json" <<'NODE'
const fs = require('node:fs');
const catalog = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const expected = ['TERMS_OF_USE', 'PRIVACY_POLICY'];

if (!Array.isArray(catalog.notices) || catalog.notices.length !== expected.length) {
  process.exit(1);
}

for (const purpose of expected) {
  const matches = catalog.notices.filter((notice) => notice.purposeCode === purpose);
  if (
    matches.length !== 1 ||
    matches[0].required !== true ||
    typeof matches[0].noticeVersion !== 'string' ||
    matches[0].noticeVersion.length === 0
  ) {
    process.exit(1);
  }
  process.stdout.write(`${matches[0].noticeVersion}\n`);
}
NODE
)

if [[ "${#notice_versions[@]}" -ne 2 ]]; then
  echo "ERROR: la API no publico exactamente términos y privacidad vigentes." >&2
  cat "$work_dir/consent-catalog.json" >&2
  exit 1
fi

terms_version="${notice_versions[0]}"
privacy_version="${notice_versions[1]}"

post_registration() {
  local idempotency_key="$1"
  local request_body="$2"
  local output_file="$3"
  local write_format="${4:-%{http_code}}"

  curl \
    --silent \
    --show-error \
    --output "$output_file" \
    --write-out "$write_format" \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $idempotency_key" \
    --data "$request_body" \
    "$api_url/api/v1/auth/register"
}

valid_body="$(printf '{"username":"%s","email":"%s","password":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$username" "$email" "$valid_password" "$terms_version" "$privacy_version")"
duplicate_body="$(printf '{"username":"%s","email":"%s","password":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$username" "$duplicate_email" "$valid_password" "$terms_version" "$privacy_version")"

mapfile -t first_metrics < <(
  post_registration "$key_one" "$valid_body" "$work_dir/first.json" '%{http_code}\n%{time_total}\n' \
    | tr -d '\r'
)
status_first="${first_metrics[0]}"
argon_request_seconds="${first_metrics[1]}"
assert_equal "registro valido" "$status_first" "202"
assert_minimum_seconds "derivacion Argon2id" "$argon_request_seconds" "0.100"
assert_contains "estado generico" '"status":"RECEIVED"' "$work_dir/first.json"
assert_contains \
  "mensaje generico" \
  '"message":"La solicitud fue recibida. El resultado no confirma si el correo ya estaba registrado."' \
  "$work_dir/first.json"

account_id="$("${psql_base[@]}" --command="SELECT account_id FROM security.account WHERE encode(email_lookup_hash, 'hex') = '$email_hash';")"
assert_nonempty "cuenta persistida" "$account_id"

status_replay="$(post_registration "$key_one" "$valid_body" "$work_dir/replay.json")"
assert_equal "reintento con la misma clave" "$status_replay" "202"
assert_files_equal \
  "reintento idempotente" \
  "$work_dir/first.json" \
  "$work_dir/replay.json"

status_duplicate="$(post_registration "$key_two" "$duplicate_body" "$work_dir/duplicate.json")"
assert_equal "correo duplicado" "$status_duplicate" "202"
assert_files_equal \
  "respuesta no enumerable para correo duplicado" \
  "$work_dir/first.json" \
  "$work_dir/duplicate.json"

if grep -F -q "$email" "$work_dir/first.json"; then
  echo "ERROR: la respuesta generica expuso el identificador de registro." >&2
  exit 1
fi

conflict_body="$(printf '{"username":"%s","email":"otra-%s","password":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$username" "$email" "$valid_password" "$terms_version" "$privacy_version")"
status_conflict="$(post_registration "$key_one" "$conflict_body" "$work_dir/conflict.json")"
assert_equal "misma clave con otro correo" "$status_conflict" "409"

changed_password_body="$(printf '{"username":"%s","email":"%s","password":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$username" "$email" "$changed_password" "$terms_version" "$privacy_version")"
status_password_conflict="$(post_registration "$key_one" "$changed_password_body" "$work_dir/password-conflict.json")"
assert_equal "misma clave con otra contrasena" "$status_password_conflict" "409"

stale_body="$(printf '{"username":"%s","email":"%s","password":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"obsolete","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "${username}stale" "$stale_email" "$valid_password" "$privacy_version")"
status_stale="$(post_registration "$key_stale" "$stale_body" "$work_dir/stale.json")"
assert_equal "consentimiento obsoleto" "$status_stale" "400"
assert_contains "error de consentimiento obsoleto" '"consents"' "$work_dir/stale.json"

missing_body="$(printf '{"username":"%s","email":"%s","password":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true}]}' "${username}miss" "$missing_email" "$valid_password" "$terms_version")"
status_missing="$(post_registration "$key_missing" "$missing_body" "$work_dir/missing.json")"
assert_equal "consentimiento faltante" "$status_missing" "400"
assert_contains "error de consentimiento faltante" '"consents"' "$work_dir/missing.json"

rejected_body="$(printf '{"username":"%s","email":"%s","password":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":false}]}' "${username}reject" "$rejected_email" "$valid_password" "$terms_version" "$privacy_version")"
status_rejected="$(post_registration "$key_rejected" "$rejected_body" "$work_dir/rejected.json")"
assert_equal "consentimiento rechazado" "$status_rejected" "400"
assert_contains "error de consentimiento rechazado" '"consents"' "$work_dir/rejected.json"

invalid_body="$(printf '{"username":"%s","email":"correo-invalido","password":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "${username}invalid" "$valid_password" "$terms_version" "$privacy_version")"
status_invalid="$(post_registration "$key_invalid" "$invalid_body" "$work_dir/invalid.json")"
assert_equal "correo invalido" "$status_invalid" "400"
assert_contains "error de correo invalido" '"email"' "$work_dir/invalid.json"

short_body="$(printf '{"username":"%s","email":"%s","password":"muy-corta","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "${username}short" "$short_email" "$terms_version" "$privacy_version")"
status_short="$(post_registration "$key_short" "$short_body" "$work_dir/short.json")"
assert_equal "contrasena corta" "$status_short" "400"
assert_contains "error de contrasena corta" '"password"' "$work_dir/short.json"

blocked_body="$(printf '{"username":"%s","email":"%s","password":"correcthorsebatterystaple","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "${username}block" "$blocked_email" "$terms_version" "$privacy_version")"
status_blocked="$(post_registration "$key_blocked" "$blocked_body" "$work_dir/blocked.json")"
assert_equal "contrasena bloqueada" "$status_blocked" "400"
assert_contains "error de contrasena bloqueada" '"password"' "$work_dir/blocked.json"

status_missing_key="$(curl --silent --show-error --output "$work_dir/missing-key.json" --write-out '%{http_code}' --header 'Content-Type: application/json' --data "$valid_body" "$api_url/api/v1/auth/register")"
assert_equal "clave de idempotencia faltante" "$status_missing_key" "400"
assert_contains \
  "error de clave de idempotencia faltante" \
  '"idempotencyKey"' \
  "$work_dir/missing-key.json"

after_accounts="$("${psql_base[@]}" --command="SELECT count(*) FROM security.account;")"
after_credentials="$("${psql_base[@]}" --command="SELECT count(*) FROM security.credential;")"
after_profiles="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.user_profile;")"
after_consents="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.consent_record;")"
after_verifications="$("${psql_base[@]}" --command="SELECT count(*) FROM security.account_verification;")"
after_outbox="$("${psql_base[@]}" --command="SELECT count(*) FROM ops.outbox_message WHERE event_name = 'email.delivery.requested';")"

assert_count_delta "cuentas" "$before_accounts" "$after_accounts" 1
assert_count_delta "credenciales" "$before_credentials" "$after_credentials" 1
assert_count_delta "perfiles" "$before_profiles" "$after_profiles" 1
assert_count_delta "consentimientos" "$before_consents" "$after_consents" 2
assert_count_delta "verificaciones" "$before_verifications" "$after_verifications" 1
assert_count_delta "outbox de correo" "$before_outbox" "$after_outbox" 1

account_check="$("${psql_base[@]}" --command="SELECT status_code = 'PENDING' AND verified_at IS NULL AND octet_length(email_lookup_hash) = 32 AND octet_length(email_cipher) > 29 FROM security.account WHERE account_id = '$account_id';")"
assert_equal "contrato de security.account" "$account_check" "t"

credential_check="$("${psql_base[@]}" --command="
SELECT count(*) = 1
   AND bool_and(algorithm = 'ARGON2ID')
   AND bool_and(active)
   AND bool_and(octet_length(decode(hash, 'base64')) = 32)
   AND bool_and((parameters::jsonb->>'v')::integer = 19)
   AND bool_and((parameters::jsonb->>'m')::integer = 65536)
   AND bool_and((parameters::jsonb->>'t')::integer = 3)
   AND bool_and((parameters::jsonb->>'p')::integer = 1)
   AND bool_and((parameters::jsonb->>'l')::integer = 32)
   AND bool_and(octet_length(decode(parameters::jsonb->>'s', 'base64')) = 16)
   AND bool_and(parameters::jsonb->>'n' = 'NFC')
   AND bool_and(parameters::jsonb->>'policy' = 'PASSWORD_V1_2026-08-10')
   AND bool_and(position('$valid_password' IN hash) = 0)
   AND bool_and(position('$valid_password' IN parameters) = 0)
FROM security.credential
WHERE account_id = '$account_id';
")"
assert_equal "contrato de security.credential" "$credential_check" "t"

profile_check="$("${psql_base[@]}" --command="SELECT username = '$username' AND ui_language = 'es-CR' AND time_zone = 'America/Costa_Rica' AND display_name IS NULL FROM identity.user_profile WHERE account_id = '$account_id';")"
assert_equal "contrato de identity.user_profile" "$profile_check" "t"

consent_check="$("${psql_base[@]}" --command="
SELECT count(*) = 2
   AND count(DISTINCT purpose_code) = 2
   AND bool_and(decision)
   AND bool_and(
       (purpose_code = 'TERMS_OF_USE' AND notice_version = '$terms_version')
       OR (purpose_code = 'PRIVACY_POLICY' AND notice_version = '$privacy_version')
   )
   AND min(decided_at) = max(decided_at)
FROM identity.consent_record
WHERE account_id = '$account_id'
  AND purpose_code IN ('TERMS_OF_USE', 'PRIVACY_POLICY');
")"
assert_equal "contrato de identity.consent_record" "$consent_check" "t"

verification_check="$("${psql_base[@]}" --command="
SELECT count(*) = 1
   AND bool_and(octet_length(token_hash) = 32)
   AND bool_and(consumed_at IS NULL)
   AND bool_and(expires_at > CURRENT_TIMESTAMP)
   AND bool_and(expires_at <= created_at + interval '30 minutes 5 seconds')
FROM security.account_verification
WHERE account_id = '$account_id';
")"
assert_equal "contrato de security.account_verification" "$verification_check" "t"

opaque_email_payload_check="$("${psql_base[@]}" --command="
SELECT count(*) = 1
   AND bool_and(payload->>'templateCode' = 'PERSONAL_ACCOUNT_VERIFICATION')
   AND bool_and(payload->>'templateVersion' = '1')
   AND bool_and(position('@' IN payload::text) = 0)
FROM ops.outbox_message
WHERE aggregate_id = '$account_id'
  AND event_name = 'email.delivery.requested';
")"
assert_equal "payload opaco de correo" "$opaque_email_payload_check" "t"

if "${psql_base[@]}" --command="UPDATE identity.consent_record SET decision = FALSE WHERE account_id = '$account_id';" >/dev/null 2>&1; then
  echo "ERROR: identity.consent_record permitio mutar una aceptación confirmada." >&2
  exit 1
fi

if grep -F -q -e "$valid_password" -e "$changed_password" "$api_log"; then
  echo "ERROR: la contraseña apareció en logs de la API." >&2
  exit 1
fi

cat > artifacts/postgres/personal-registration-summary.txt <<EOF
bl_mvp=028
endpoint_catalog=GET /api/v1/auth/registration-consents
endpoint_registration=POST /api/v1/auth/register
password_policy=PASSWORD_V1_2026-08-10
password_length_codepoints=15..128
password_spaces_unicode=accepted-nfc
password_common_blocklist=local-versioned
credential_algorithm=ARGON2ID
argon2id_memory_kib=65536
argon2id_iterations=3
argon2id_parallelism=1
argon2id_salt_bytes=16-random-per-credential
argon2id_hash_bytes=32
first_registration_seconds=$argon_request_seconds
first_registration_target=at-least-0.100-seconds
required_purposes=TERMS_OF_USE,PRIVACY_POLICY
terms_version=$terms_version
privacy_version=$privacy_version
valid_status=202
same_key_replay=generic_equal
duplicate_email=generic_equal
same_key_different_digest=409
same_key_changed_password=409-keyed-fingerprint
missing_consent=400
rejected_consent=400
obsolete_version=400
account_delta=1
credential_delta=1
credential_plaintext_storage=absent
idempotency_password_material=keyed-fingerprint-only
profile_delta=1
consent_delta=2
consent_storage=append-only
verification_delta=1
verification_token_storage=sha256-only
verification_email_payload=opaque-references-only
EOF

if grep -F -R -q -e "$valid_password" -e "$changed_password" artifacts; then
  echo "ERROR: la contraseña apareció en evidencia persistente." >&2
  exit 1
fi

echo "OK: BL-MVP-028 politica larga, bloqueo local, Argon2id y persistencia sin texto claro verificados."
