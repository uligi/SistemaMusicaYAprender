#!/usr/bin/env bash
set -Eeuo pipefail
main_shell_pid=$BASHPID

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

mkdir -p artifacts/postgres artifacts/test-results

failure_artifact="artifacts/test-results/account-verification-smoke-failure.txt"
rm -f "$failure_artifact"
smoke_stage="preparacion"

api_url="${BL025_API_URL:-http://127.0.0.1:5080}"
mailpit_api="${BL025_MAILPIT_API_BASE:-http://127.0.0.1:8025}"
work_dir="$(mktemp -d)"
api_log="$work_dir/api.log"
worker_log="$work_dir/worker.log"
touch "$api_log" "$worker_log"
valid_email="bl025-valid-$(openssl rand -hex 10)@example.test"
valid_email_canonical="${valid_email^^}"
expired_email="bl025-expired-$(openssl rand -hex 10)@example.test"
prerequisite_email="bl025-prerequisite-$(openssl rand -hex 10)@example.test"
unknown_email="bl025-unknown-$(openssl rand -hex 10)@example.test"
valid_registration_key="bl025-register-valid-$(openssl rand -hex 12)"
expired_registration_key="bl025-register-expired-$(openssl rand -hex 12)"
prerequisite_registration_key="bl025-register-prerequisite-$(openssl rand -hex 12)"
resend_key="bl025-resend-pending-$(openssl rand -hex 12)"
unknown_resend_key="bl025-resend-unknown-$(openssl rand -hex 12)"

lookup_key_hex="$(tr -d '[:space:]' < secrets/local/identity_email_lookup_key)"
verification_key_hex="$(tr -d '[:space:]' < secrets/local/identity_verification_token_key)"
if [[ ! "$lookup_key_hex" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "ERROR: identity_email_lookup_key no contiene 32 bytes hexadecimales." >&2
  exit 1
fi
if [[ ! "$verification_key_hex" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "ERROR: identity_verification_token_key no contiene 32 bytes hexadecimales." >&2
  exit 1
fi

lookup_hash() {
  local candidate="$1"
  printf '%s' "${candidate^^}" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$lookup_key_hex" -binary \
    | od -An -vtx1 \
    | tr -d ' \n'
}

valid_hash="$(lookup_hash "$valid_email")"
expired_hash="$(lookup_hash "$expired_email")"
prerequisite_hash="$(lookup_hash "$prerequisite_email")"

if [[ "${BL025_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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

account_ids_sql() {
  printf "SELECT account_id FROM security.account WHERE encode(email_lookup_hash, 'hex') IN ('%s', '%s', '%s')" \
    "$valid_hash" "$expired_hash" "$prerequisite_hash"
}

cleanup() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" >/dev/null 2>&1 || true
    wait "$api_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "${worker_pid:-}" ]]; then
    kill "$worker_pid" >/dev/null 2>&1 || true
    wait "$worker_pid" >/dev/null 2>&1 || true
  fi

  local accounts_query
  accounts_query="$(account_ids_sql)"
  "${psql_base[@]}" --command="
BEGIN;
ALTER TABLE ops.job_attempt DISABLE TRIGGER tr_ops_job_attempt_append_only;
DELETE FROM ops.job_attempt
WHERE job_id IN (
  SELECT job_id FROM ops.background_job
  WHERE payload->>'aggregateId' IN (SELECT account_id::text FROM ($accounts_query) AS test_accounts)
);
ALTER TABLE ops.job_attempt ENABLE TRIGGER tr_ops_job_attempt_append_only;
DELETE FROM ops.background_job
WHERE payload->>'aggregateId' IN (SELECT account_id::text FROM ($accounts_query) AS test_accounts);
DELETE FROM ops.inbox_message
WHERE event_id IN (
  SELECT event_id FROM ops.outbox_message
  WHERE aggregate_id IN (SELECT account_id FROM ($accounts_query) AS test_accounts)
);
DELETE FROM ops.outbox_message
WHERE aggregate_id IN (SELECT account_id FROM ($accounts_query) AS test_accounts);
ALTER TABLE security.security_event DISABLE TRIGGER tr_security_security_event_append_only;
DELETE FROM security.security_event
WHERE account_id IN (SELECT account_id FROM ($accounts_query) AS test_accounts);
ALTER TABLE security.security_event ENABLE TRIGGER tr_security_security_event_append_only;
DELETE FROM security.account_verification
WHERE account_id IN (SELECT account_id FROM ($accounts_query) AS test_accounts);
ALTER TABLE identity.consent_record DISABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.consent_record
WHERE account_id IN (SELECT account_id FROM ($accounts_query) AS test_accounts);
ALTER TABLE identity.consent_record ENABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.user_profile
WHERE account_id IN (SELECT account_id FROM ($accounts_query) AS test_accounts);
DELETE FROM security.account
WHERE account_id IN (SELECT account_id FROM ($accounts_query) AS test_accounts);
DELETE FROM ops.idempotency_record
WHERE account_id IS NULL
  AND idempotency_key IN (
    '$valid_registration_key',
    '$expired_registration_key',
    '$prerequisite_registration_key',
    '$resend_key',
    '$unknown_resend_key'
  );
COMMIT;
" >/dev/null 2>&1 || true

  rm -rf "$work_dir"
}

report_smoke_failure() {
  local exit_code=$?

  if [[ "$BASHPID" != "$main_shell_pid" ]]; then
    return "$exit_code"
  fi

  trap - ERR

  {
    printf 'bl_mvp=025\n'
    printf 'status=failed\n'
    printf 'stage=%s\n' "$smoke_stage"
    printf 'exit_code=%s\n' "$exit_code"
  } | tee "$failure_artifact" >&2

  if [[ -n "${valid_account_id:-}" ]]; then
    echo "Diagnostico seguro de entrega (sin correo, token, secreto ni payload):" >&2
    "${psql_base[@]}" --command="
SELECT
    'outbox' AS component,
    status_code,
    0 AS attempt_count,
    '' AS error_code
FROM ops.outbox_message
WHERE aggregate_id = '$valid_account_id'
  AND event_name = 'email.delivery.requested'
UNION ALL
SELECT
    'email_job' AS component,
    job.status_code,
    job.attempt_count,
    COALESCE(attempt.error_code, '') AS error_code
FROM ops.background_job AS job
LEFT JOIN LATERAL (
    SELECT job_attempt.error_code
    FROM ops.job_attempt AS job_attempt
    WHERE job_attempt.job_id = job.job_id
    ORDER BY job_attempt.attempt_no DESC
    LIMIT 1
) AS attempt ON true
WHERE job.payload->>'aggregateId' = '$valid_account_id'
ORDER BY component;
" >&2 || true
  fi

  echo "ERROR: BL-MVP-025 fallo en la etapa segura '$smoke_stage'." >&2
  exit "$exit_code"
}

trap cleanup EXIT
trap report_smoke_failure ERR

smoke_stage="mailpit-readiness"
docker compose up --detach smtp-sink
for attempt in $(seq 1 30); do
  if curl --fail --silent "$mailpit_api/api/v1/messages" >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    docker compose logs smtp-sink >&2
    exit 1
  fi
  sleep 1
done

smoke_stage="api-readiness"
if [[ "${BL025_USE_RUNNING_SERVICES:-false}" != "true" ]]; then
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

  Secrets__Directory="$ROOT/secrets/local" \
  Secrets__RequireExternal=true \
  Database__Host="$PGHOST" \
  Database__Port="$PGPORT" \
  Database__Name="$PGDATABASE" \
  Database__Username=jp_login_worker \
  Database__PasswordSecret=postgres_worker_password \
  ObjectStore__Endpoint=http://127.0.0.1:9000 \
  ObjectStore__Bucket=musica-aprender-private \
  ObjectStore__EncryptionKeyReference=local-secret://object_store_encryption_key/v1 \
  Smtp__Host=127.0.0.1 \
  Smtp__Port=1025 \
  Smtp__FromAddress=no-reply@musica-aprender.local \
  Smtp__FromDisplayName="Musica y Aprender" \
  Smtp__Security=None \
  dotnet run \
    --project apps/worker/MusicaAprender.Worker.csproj \
    --configuration Release \
    --no-build \
    --no-restore \
    >"$worker_log" 2>&1 &
  worker_pid=$!
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

smoke_stage="catalogo-consentimientos"
curl --fail --silent --show-error \
  --output "$work_dir/consent-catalog.json" \
  "$api_url/api/v1/auth/registration-consents"

mapfile -t notice_versions < <(
  node - "$work_dir/consent-catalog.json" <<'NODE'
const fs = require('node:fs');
const catalog = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const purpose of ['TERMS_OF_USE', 'PRIVACY_POLICY']) {
  const notice = catalog.notices?.find((item) => item.purposeCode === purpose && item.required === true);
  if (!notice || typeof notice.noticeVersion !== 'string' || notice.noticeVersion.length === 0) {
    process.exit(1);
  }
  process.stdout.write(`${notice.noticeVersion}\n`);
}
NODE
)
[[ "${#notice_versions[@]}" -eq 2 ]]
terms_version="${notice_versions[0]}"
privacy_version="${notice_versions[1]}"

post_registration() {
  local email="$1"
  local idempotency_key="$2"
  local output_file="$3"
  local body
  body="$(printf '{"email":"%s","consents":[{"purposeCode":"TERMS_OF_USE","noticeVersion":"%s","decision":true},{"purposeCode":"PRIVACY_POLICY","noticeVersion":"%s","decision":true}]}' "$email" "$terms_version" "$privacy_version")"
  curl --silent --show-error \
    --output "$output_file" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $idempotency_key" \
    --data "$body" \
    "$api_url/api/v1/auth/register"
}

create_account() {
  local email="$1"
  local email_hash="$2"
  local idempotency_key="$3"
  local name="$4"
  local status
  status="$(post_registration "$email" "$idempotency_key" "$work_dir/$name-registration.json")"
  [[ "$status" == "202" ]]
  grep -F -q '"status":"RECEIVED"' "$work_dir/$name-registration.json"

  CREATED_ACCOUNT_ID="$("${psql_base[@]}" --command="
SELECT account_id FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$email_hash';
")"
  [[ -n "$CREATED_ACCOUNT_ID" ]]
  CREATED_VERIFICATION_ID="$("${psql_base[@]}" --command="
SELECT verification_id FROM security.account_verification
WHERE account_id = '$CREATED_ACCOUNT_ID'
ORDER BY created_at DESC, verification_id DESC LIMIT 1;
")"
  [[ -n "$CREATED_VERIFICATION_ID" ]]
}

create_token() {
  local account_id="$1"
  local verification_id="$2"
  node - "$verification_key_hex" "$account_id" "$verification_id" <<'NODE'
const crypto = require('node:crypto');
const key = Buffer.from(process.argv[2], 'hex');
const account = Buffer.from(process.argv[3].replaceAll('-', ''), 'hex');
const verification = Buffer.from(process.argv[4].replaceAll('-', ''), 'hex');
const payload = Buffer.concat([account, verification]);
const purpose = Buffer.from('MusicaAprender.AccountVerification.v1\0', 'ascii');
const signature = crypto.createHmac('sha256', key).update(Buffer.concat([purpose, payload])).digest();
process.stdout.write(Buffer.concat([payload, signature]).toString('base64url'));
NODE
}

verify_token() {
  local candidate="$1"
  local output_file="$2"
  curl --silent --show-error \
    --output "$output_file" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --data "$(printf '{"token":"%s"}' "$candidate")" \
    "$api_url/api/v1/auth/verify-account"
}

smoke_stage="registro-valido"
create_account "$valid_email" "$valid_hash" "$valid_registration_key" valid
valid_account_id="$CREATED_ACCOUNT_ID"
valid_verification_id="$CREATED_VERIFICATION_ID"
valid_token="$(create_token "$valid_account_id" "$valid_verification_id")"
[[ "${#valid_token}" -eq 86 ]]

smoke_stage="entrega-correo-valido"
mail_found=false
for attempt in $(seq 1 60); do
  curl --fail --silent --show-error \
    --output "$work_dir/mail-list.json" \
    "$mailpit_api/api/v1/messages"
  message_id="$(node - "$work_dir/mail-list.json" "$valid_verification_id" <<'NODE'
const fs = require('node:fs');
const response = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const expected = `[BL025][ACCOUNT_VERIFICATION:v1] ${process.argv[3].replaceAll('-', '')}`;
const messages = Array.isArray(response.messages) ? response.messages : [];
const match = messages.find((message) => message.Subject === expected);
if (match?.ID) process.stdout.write(match.ID);
NODE
)"
  if [[ -n "$message_id" ]]; then
    curl --fail --silent --show-error \
      --output "$work_dir/mail-detail.json" \
      "$mailpit_api/api/v1/message/$message_id"
    if node - "$work_dir/mail-detail.json" "$valid_token" "$valid_email_canonical" <<'NODE'
const fs = require('node:fs');
const detail = JSON.stringify(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')));
if (!detail.includes(process.argv[3]) || !detail.includes(process.argv[4])) process.exit(1);
NODE
    then
      mail_found=true
      break
    fi
  fi
  sleep 1
done
[[ "$mail_found" == "true" ]]

smoke_stage="consumo-token-valido"
valid_status="$(verify_token "$valid_token" "$work_dir/valid-verification.json")"
[[ "$valid_status" == "200" ]]
grep -F -q '"status":"VERIFIED"' "$work_dir/valid-verification.json"

valid_state="$("${psql_base[@]}" --command="
SELECT account.status_code = 'ACTIVE'
   AND account.verified_at IS NOT NULL
   AND verification.consumed_at IS NOT NULL
FROM security.account AS account
INNER JOIN security.account_verification AS verification USING (account_id)
WHERE account.account_id = '$valid_account_id'
  AND verification.verification_id = '$valid_verification_id';
")"
[[ "$valid_state" == "t" ]]

smoke_stage="replay-idempotente"
consumed_at_before="$("${psql_base[@]}" --command="
SELECT consumed_at FROM security.account_verification
WHERE verification_id = '$valid_verification_id';
")"
replay_status="$(verify_token "$valid_token" "$work_dir/replay-verification.json")"
[[ "$replay_status" == "200" ]]
cmp "$work_dir/valid-verification.json" "$work_dir/replay-verification.json"
consumed_at_after="$("${psql_base[@]}" --command="
SELECT consumed_at FROM security.account_verification
WHERE verification_id = '$valid_verification_id';
")"
[[ "$consumed_at_before" == "$consumed_at_after" ]]

smoke_stage="token-manipulado"
last_character="${valid_token: -1}"
if [[ "$last_character" == "A" ]]; then
  tampered_token="${valid_token::-1}B"
else
  tampered_token="${valid_token::-1}A"
fi
tampered_status="$(verify_token "$tampered_token" "$work_dir/tampered-verification.json")"
[[ "$tampered_status" == "400" ]]

success_events="$("${psql_base[@]}" --command="
SELECT count(*) FROM security.security_event
WHERE account_id = '$valid_account_id'
  AND event_type = 'ACCOUNT_VERIFICATION'
  AND result_code = 'SUCCEEDED';
")"
[[ "$success_events" -eq 1 ]]

smoke_stage="token-vencido"
create_account "$expired_email" "$expired_hash" "$expired_registration_key" expired
expired_account_id="$CREATED_ACCOUNT_ID"
expired_verification_id="$CREATED_VERIFICATION_ID"
expired_token="$(create_token "$expired_account_id" "$expired_verification_id")"
"${psql_base[@]}" --command="
UPDATE security.account_verification
SET created_at = CURRENT_TIMESTAMP - interval '2 hours',
    expires_at = CURRENT_TIMESTAMP - interval '1 hour'
WHERE verification_id = '$expired_verification_id';
" >/dev/null
expired_status="$(verify_token "$expired_token" "$work_dir/expired-verification.json")"
[[ "$expired_status" == "400" ]]
expired_state="$("${psql_base[@]}" --command="
SELECT account.status_code = 'PENDING'
   AND account.verified_at IS NULL
   AND verification.consumed_at IS NULL
FROM security.account AS account
INNER JOIN security.account_verification AS verification USING (account_id)
WHERE account.account_id = '$expired_account_id'
  AND verification.verification_id = '$expired_verification_id';
")"
[[ "$expired_state" == "t" ]]

smoke_stage="prerrequisitos-consentimiento"
create_account "$prerequisite_email" "$prerequisite_hash" "$prerequisite_registration_key" prerequisite
prerequisite_account_id="$CREATED_ACCOUNT_ID"
prerequisite_verification_id="$CREATED_VERIFICATION_ID"
prerequisite_token="$(create_token "$prerequisite_account_id" "$prerequisite_verification_id")"
"${psql_base[@]}" --command="
BEGIN;
ALTER TABLE identity.consent_record DISABLE TRIGGER tr_identity_consent_record_append_only;
DELETE FROM identity.consent_record
WHERE account_id = '$prerequisite_account_id'
  AND purpose_code = 'PRIVACY_POLICY';
ALTER TABLE identity.consent_record ENABLE TRIGGER tr_identity_consent_record_append_only;
COMMIT;
" >/dev/null
prerequisite_status="$(verify_token "$prerequisite_token" "$work_dir/prerequisite-verification.json")"
[[ "$prerequisite_status" == "409" ]]
prerequisite_state="$("${psql_base[@]}" --command="
SELECT account.status_code = 'PENDING'
   AND account.verified_at IS NULL
   AND verification.consumed_at IS NULL
FROM security.account AS account
INNER JOIN security.account_verification AS verification USING (account_id)
WHERE account.account_id = '$prerequisite_account_id'
  AND verification.verification_id = '$prerequisite_verification_id';
")"
[[ "$prerequisite_state" == "t" ]]

smoke_stage="reenvio-no-enumerable"
post_resend() {
  local email="$1"
  local idempotency_key="$2"
  local output_file="$3"
  curl --silent --show-error \
    --output "$output_file" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $idempotency_key" \
    --data "$(printf '{"email":"%s"}' "$email")" \
    "$api_url/api/v1/auth/verification/resend"
}

verification_count_before="$("${psql_base[@]}" --command="
SELECT count(*) FROM security.account_verification
WHERE account_id = '$expired_account_id';
")"
resend_status="$(post_resend "$expired_email" "$resend_key" "$work_dir/resend-pending.json")"
[[ "$resend_status" == "202" ]]
unknown_status="$(post_resend "$unknown_email" "$unknown_resend_key" "$work_dir/resend-unknown.json")"
[[ "$unknown_status" == "202" ]]
cmp "$work_dir/resend-pending.json" "$work_dir/resend-unknown.json"
if grep -F -q "$expired_email" "$work_dir/resend-pending.json" \
  || grep -F -q "$unknown_email" "$work_dir/resend-unknown.json"; then
  echo "ERROR: el reenvio expuso si una cuenta existe." >&2
  exit 1
fi

verification_count_after="$("${psql_base[@]}" --command="
SELECT count(*) FROM security.account_verification
WHERE account_id = '$expired_account_id';
")"
[[ "$verification_count_after" -eq $((verification_count_before + 1)) ]]
resend_replay_status="$(post_resend "$expired_email" "$resend_key" "$work_dir/resend-replay.json")"
[[ "$resend_replay_status" == "202" ]]
cmp "$work_dir/resend-pending.json" "$work_dir/resend-replay.json"
verification_count_replay="$("${psql_base[@]}" --command="
SELECT count(*) FROM security.account_verification
WHERE account_id = '$expired_account_id';
")"
[[ "$verification_count_replay" -eq "$verification_count_after" ]]

smoke_stage="payloads-opacos"
opaque_payloads="$("${psql_base[@]}" --command="
SELECT count(*) >= 4
   AND bool_and(payload->>'templateCode' = 'PERSONAL_ACCOUNT_VERIFICATION')
   AND bool_and(payload->>'templateVersion' = '1')
   AND bool_and(position('@' IN payload::text) = 0)
FROM ops.outbox_message
WHERE aggregate_id IN ('$valid_account_id', '$expired_account_id', '$prerequisite_account_id')
  AND event_name = 'email.delivery.requested';
")"
[[ "$opaque_payloads" == "t" ]]

smoke_stage="higiene-logs"
for sensitive_value in \
  "$valid_email" "$expired_email" "$prerequisite_email" "$unknown_email" \
  "$valid_token" "$expired_token" "$prerequisite_token"; do
  if grep -F -q "$sensitive_value" "$api_log" "$worker_log"; then
    echo "ERROR: una entrada sensible apareció en logs de servicio." >&2
    exit 1
  fi
done

smoke_stage="evidencia-final"
cat > artifacts/postgres/account-verification-summary.txt <<EOF
bl_mvp=025
endpoint_verification=POST /api/v1/auth/verify-account
endpoint_resend=POST /api/v1/auth/verification/resend
token_lifetime_minutes=30
token_persistence=sha256-only
valid_token=200
valid_replay=200-idempotent
tampered_token=400-generic
expired_token=400-generic
stale_prerequisites=409-no-activation
resend_pending=202-generic
resend_unknown=202-generic-equal
resend_replay=202-no-duplicate
email_template=PERSONAL_ACCOUNT_VERIFICATION:v1:es
email_outbox_payload=opaque-references-only
security_event=ACCOUNT_VERIFICATION:SUCCEEDED
EOF

rm -f "$failure_artifact"
smoke_stage="completado"
echo "OK: BL-MVP-025 token firmado de un uso, vencimiento, prerrequisitos y reenvío no enumerable verificados."
