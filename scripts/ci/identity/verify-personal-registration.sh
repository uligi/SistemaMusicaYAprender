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

api_url="http://127.0.0.1:5080"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
account_id=""
key_one="bl023-$(openssl rand -hex 16)"
key_two="bl023-$(openssl rand -hex 16)"
email="bl023-$(openssl rand -hex 12)@example.test"
duplicate_email="${email^^}"

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

cleanup() {
  if [[ -n "$account_id" ]]; then
    "${psql_base[@]}" --command="DELETE FROM identity.user_profile WHERE account_id = '$account_id'; DELETE FROM security.account WHERE account_id = '$account_id';" >/dev/null 2>&1 || true
  fi

  "${psql_base[@]}" --command="DELETE FROM ops.idempotency_record WHERE account_id IS NULL AND idempotency_key IN ('$key_one', '$key_two');" >/dev/null 2>&1 || true

  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" >/dev/null 2>&1 || true
    wait "$api_pid" >/dev/null 2>&1 || true
  fi

  rm -rf "$work_dir"
}

trap cleanup EXIT

before_accounts="$("${psql_base[@]}" --command="SELECT count(*) FROM security.account;")"
before_profiles="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.user_profile;")"

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

post_registration() {
  local request_email="$1"
  local idempotency_key="$2"
  local output_file="$3"

  curl \
    --silent \
    --show-error \
    --output "$output_file" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $idempotency_key" \
    --data "{\"email\":\"$request_email\"}" \
    "$api_url/api/v1/auth/register"
}

status_first="$(post_registration "$email" "$key_one" "$work_dir/first.json")"
[[ "$status_first" == "202" ]]
grep -F -q '"status":"RECEIVED"' "$work_dir/first.json"
grep -F -q '"message":"La solicitud fue recibida. El resultado no confirma si el correo ya estaba registrado."' "$work_dir/first.json"
account_id="$("${psql_base[@]}" --command="SELECT a.account_id FROM security.account a JOIN identity.user_profile p USING (account_id) WHERE a.status_code = 'PENDING' ORDER BY a.created_at DESC LIMIT 1;")"
[[ -n "$account_id" ]]

status_replay="$(post_registration "$email" "$key_one" "$work_dir/replay.json")"
[[ "$status_replay" == "202" ]]
cmp "$work_dir/first.json" "$work_dir/replay.json"

status_duplicate="$(post_registration "$duplicate_email" "$key_two" "$work_dir/duplicate.json")"
[[ "$status_duplicate" == "202" ]]
cmp "$work_dir/first.json" "$work_dir/duplicate.json"

if grep -F -q "$email" "$work_dir/first.json"; then
  echo "ERROR: la respuesta generica expuso el identificador de registro." >&2
  exit 1
fi

status_conflict="$(post_registration "otra-$email" "$key_one" "$work_dir/conflict.json")"
[[ "$status_conflict" == "409" ]]

status_invalid="$(post_registration "correo-invalido" "bl023-invalid-$(openssl rand -hex 8)" "$work_dir/invalid.json")"
[[ "$status_invalid" == "400" ]]
grep -q '"email"' "$work_dir/invalid.json"

status_missing_key="$(curl --silent --show-error --output "$work_dir/missing-key.json" --write-out '%{http_code}' --header 'Content-Type: application/json' --data "{\"email\":\"$email\"}" "$api_url/api/v1/auth/register")"
[[ "$status_missing_key" == "400" ]]
grep -q '"idempotencyKey"' "$work_dir/missing-key.json"

after_accounts="$("${psql_base[@]}" --command="SELECT count(*) FROM security.account;")"
after_profiles="$("${psql_base[@]}" --command="SELECT count(*) FROM identity.user_profile;")"

[[ "$after_accounts" -eq $((before_accounts + 1)) ]]
[[ "$after_profiles" -eq $((before_profiles + 1)) ]]

protection_check="$("${psql_base[@]}" --command="SELECT octet_length(email_lookup_hash) = 32 AND octet_length(email_cipher) > 29 FROM security.account WHERE account_id = '$account_id';")"
[[ "$protection_check" == "t" ]]

profile_check="$("${psql_base[@]}" --command="SELECT ui_language = 'es-CR' AND time_zone = 'America/Costa_Rica' AND display_name IS NULL FROM identity.user_profile WHERE account_id = '$account_id';")"
[[ "$profile_check" == "t" ]]

cat > artifacts/postgres/personal-registration-summary.txt <<'EOF'
bl_mvp=023
endpoint=POST /api/v1/auth/register
valid_status=202
same_key_replay=generic_equal
duplicate_email=generic_equal
same_key_different_digest=409
invalid_email=400
missing_idempotency_key=400
account_delta=1
profile_delta=1
email_lookup=HMAC-SHA-256
email_cipher=AES-256-GCM
EOF

echo "OK: BL-MVP-023 registro personal atomico, idempotente y no enumerativo verificado."
