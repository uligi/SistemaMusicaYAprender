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

api_url="${BL024_API_URL:-http://127.0.0.1:5080}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
key_one="bl024-$(openssl rand -hex 16)"
key_two="bl024-$(openssl rand -hex 16)"
key_stale="bl024-$(openssl rand -hex 16)"
key_missing="bl024-$(openssl rand -hex 16)"
key_rejected="bl024-$(openssl rand -hex 16)"
key_invalid="bl024-$(openssl rand -hex 16)"
email="bl024-$(openssl rand -hex 12)@example.test"
duplicate_email="${email^^}"
stale_email="stale-$email"
missing_email="missing-$email"
rejected_email="rejected-$email"

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

if [[ "${BL024_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
DELETE FROM security.account
WHERE encode(email_lookup_hash, 'hex') IN ('$email_hash', '$stale_hash', '$missing_hash', '$rejected_hash');
COMMIT;
" >/dev/null 2>&1 || true

  "${psql_base[@]}" --command="
DELETE FROM ops.idempotency_record
WHERE account_id IS NULL
  AND idempotency_key IN (
    '$key_one', '$key_two', '$key_stale', '$key_missing', '$key_rejected', '$key_invalid'
  );
" >/dev/null 2>&1 || true

  rm -rf "$work_dir"
}

trap cleanup EXIT

before_accounts="$("${psql_base[@]}" --command="SELECT count(*) FROM security.account;")"
before_profiles="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.user_profile;")"
before_consents="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.consent_record;")"

if [[ "${BL024_USE_RUNNING_API:-false}" != "true" ]]; then
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

  curl \
    --silent \
    --show-error \
    --output "$output_file" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $idempotency_key" \
    --data "$request_body" \
    "$api_url/api/v1/auth/register"
}

valid_body="$(printf '{"email":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$email" "$terms_version" "$privacy_version")"
duplicate_body="$(printf '{"email":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$duplicate_email" "$terms_version" "$privacy_version")"

status_first="$(post_registration "$key_one" "$valid_body" "$work_dir/first.json")"
[[ "$status_first" == "202" ]]
grep -F -q '"status":"RECEIVED"' "$work_dir/first.json"
grep -F -q '"message":"La solicitud fue recibida. El resultado no confirma si el correo ya estaba registrado."' "$work_dir/first.json"

account_id="$("${psql_base[@]}" --command="SELECT account_id FROM security.account WHERE encode(email_lookup_hash, 'hex') = '$email_hash';")"
[[ -n "$account_id" ]]

status_replay="$(post_registration "$key_one" "$valid_body" "$work_dir/replay.json")"
[[ "$status_replay" == "202" ]]
cmp "$work_dir/first.json" "$work_dir/replay.json"

status_duplicate="$(post_registration "$key_two" "$duplicate_body" "$work_dir/duplicate.json")"
[[ "$status_duplicate" == "202" ]]
cmp "$work_dir/first.json" "$work_dir/duplicate.json"

if grep -F -q "$email" "$work_dir/first.json"; then
  echo "ERROR: la respuesta generica expuso el identificador de registro." >&2
  exit 1
fi

conflict_body="$(printf '{"email":"otra-%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$email" "$terms_version" "$privacy_version")"
status_conflict="$(post_registration "$key_one" "$conflict_body" "$work_dir/conflict.json")"
[[ "$status_conflict" == "409" ]]

stale_body="$(printf '{"email":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"obsolete","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$stale_email" "$privacy_version")"
status_stale="$(post_registration "$key_stale" "$stale_body" "$work_dir/stale.json")"
[[ "$status_stale" == "400" ]]
grep -F -q '"consents"' "$work_dir/stale.json"

missing_body="$(printf '{"email":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true}]}' "$missing_email" "$terms_version")"
status_missing="$(post_registration "$key_missing" "$missing_body" "$work_dir/missing.json")"
[[ "$status_missing" == "400" ]]
grep -F -q '"consents"' "$work_dir/missing.json"

rejected_body="$(printf '{"email":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":false}]}' "$rejected_email" "$terms_version" "$privacy_version")"
status_rejected="$(post_registration "$key_rejected" "$rejected_body" "$work_dir/rejected.json")"
[[ "$status_rejected" == "400" ]]
grep -F -q '"consents"' "$work_dir/rejected.json"

invalid_body="$(printf '{"email":"correo-invalido","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$terms_version" "$privacy_version")"
status_invalid="$(post_registration "$key_invalid" "$invalid_body" "$work_dir/invalid.json")"
[[ "$status_invalid" == "400" ]]
grep -F -q '"email"' "$work_dir/invalid.json"

status_missing_key="$(curl --silent --show-error --output "$work_dir/missing-key.json" --write-out '%{http_code}' --header 'Content-Type: application/json' --data "$valid_body" "$api_url/api/v1/auth/register")"
[[ "$status_missing_key" == "400" ]]
grep -F -q '"idempotencyKey"' "$work_dir/missing-key.json"

after_accounts="$("${psql_base[@]}" --command="SELECT count(*) FROM security.account;")"
after_profiles="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.user_profile;")"
after_consents="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.consent_record;")"

[[ "$after_accounts" -eq $((before_accounts + 1)) ]]
[[ "$after_profiles" -eq $((before_profiles + 1)) ]]
[[ "$after_consents" -eq $((before_consents + 2)) ]]

account_check="$("${psql_base[@]}" --command="SELECT status_code = 'PENDING' AND verified_at IS NULL AND octet_length(email_lookup_hash) = 32 AND octet_length(email_cipher) > 29 FROM security.account WHERE account_id = '$account_id';")"
[[ "$account_check" == "t" ]]

profile_check="$("${psql_base[@]}" --command="SELECT ui_language = 'es-CR' AND time_zone = 'America/Costa_Rica' AND display_name IS NULL FROM identity.user_profile WHERE account_id = '$account_id';")"
[[ "$profile_check" == "t" ]]

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
[[ "$consent_check" == "t" ]]

if "${psql_base[@]}" --command="UPDATE identity.consent_record SET decision = FALSE WHERE account_id = '$account_id';" >/dev/null 2>&1; then
  echo "ERROR: identity.consent_record permitio mutar una aceptación confirmada." >&2
  exit 1
fi

cat > artifacts/postgres/personal-registration-summary.txt <<EOF
bl_mvp=024
endpoint_catalog=GET /api/v1/auth/registration-consents
endpoint_registration=POST /api/v1/auth/register
required_purposes=TERMS_OF_USE,PRIVACY_POLICY
terms_version=$terms_version
privacy_version=$privacy_version
valid_status=202
same_key_replay=generic_equal
duplicate_email=generic_equal
same_key_different_digest=409
missing_consent=400
rejected_consent=400
obsolete_version=400
account_delta=1
profile_delta=1
consent_delta=2
consent_storage=append-only
EOF

echo "OK: BL-MVP-024 consentimientos vigentes, versionados, atomicos e inmutables verificados."
