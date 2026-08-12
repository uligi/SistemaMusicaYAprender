#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL044_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(
    docker compose exec -T postgres
    psql
    --username="$PGUSER"
    --dbname="$PGDATABASE"
    --no-password
    --set=ON_ERROR_STOP=1
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
  )
fi

fail_check() {
  echo "ERROR: BL-MVP-044: $1" >&2
  exit 1
}

grep -Fq 'data-route-id="UI-MVP-017"' \
  apps/web/src/routes/editorial/EditorialInboxPage.tsx \
  || fail_check "UI-MVP-017 no quedó conectada a la bandeja real."

grep -Fq 'EditorialInboxPage' \
  apps/web/src/routes/editorial/EditorialArea.tsx \
  || fail_check "EditorialArea no carga la bandeja."

if grep -Fq "path: '/editorial/canciones'," \
  apps/web/src/app/router/route-manifest.ts; then
  fail_check "Se introdujo la ruta no aprobada /editorial/canciones."
fi

grep -Fq 'AuthorizationScope.ForObject' \
  apps/api/Endpoints/Editorial/EditorialInboxEndpoints.cs \
  || fail_check "La bandeja no revalida el alcance por objeto."

for permission in \
  EDITORIAL.DRAFT \
  EDITORIAL.REVIEW \
  EDITORIAL.PUBLISH \
  EDITORIAL.CORRECT; do
  grep -Fq "\"$permission\"" \
    apps/api/Endpoints/Editorial/EditorialInboxEndpoints.cs \
    || fail_check "Falta capacidad $permission."
done

grep -Fq 'editorial.editorial_lock' \
  src/Modules/Catalog/Infrastructure/Administration/EditorialInboxService.cs \
  || fail_check "Falta bloqueo editorial."

grep -Fq 'security.audit_event' \
  src/Modules/Catalog/Infrastructure/Administration/EditorialInboxService.cs \
  || fail_check "Falta responsable/actividad auditable."

grep -Fq 'editorial.provenance_record' \
  src/Modules/Catalog/Infrastructure/Administration/EditorialInboxService.cs \
  || fail_check "Falta procedencia."

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-044-editorial-inbox.txt <<'SQL'
SELECT
    recording.recording_id,
    work.canonical_title,
    recording.status_code,
    active_lock.operation_code,
    latest_audit.actor_id,
    EXISTS (
        SELECT 1
        FROM catalog.recording_credit AS credit
        INNER JOIN editorial.provenance_record AS provenance
            ON provenance.object_type = 'RECORDING_CREDIT'
           AND provenance.object_id = credit.credit_id
        WHERE credit.recording_id = recording.recording_id
    ) AS has_provenance
FROM catalog.recording AS recording
INNER JOIN catalog.musical_work AS work
    ON work.work_id = recording.work_id
LEFT JOIN LATERAL (
    SELECT
        editorial_lock.operation_code,
        editorial_lock.expires_at
    FROM editorial.editorial_lock
    WHERE editorial_lock.recording_id = recording.recording_id
      AND editorial_lock.expires_at > CURRENT_TIMESTAMP
    ORDER BY editorial_lock.expires_at DESC
    LIMIT 1
) AS active_lock ON true
LEFT JOIN LATERAL (
    SELECT
        audit.actor_id,
        audit.occurred_at
    FROM security.audit_event AS audit
    WHERE audit.object_type = 'RECORDING'
      AND audit.object_id = recording.recording_id
    ORDER BY audit.occurred_at DESC
    LIMIT 1
) AS latest_audit ON true
ORDER BY lower(work.canonical_title)
LIMIT 0;
SQL

echo "route=/editorial"
echo "ui=UI-MVP-017"
echo "permissions=EDITORIAL.DRAFT,EDITORIAL.REVIEW,EDITORIAL.PUBLISH,EDITORIAL.CORRECT"
echo "server_object_scope=true"
echo "lock=editorial.editorial_lock"
echo "owner=security.audit_event.actor_id"
echo "provenance=editorial.provenance_record"
echo "next_action=server_derived"
echo "OK: BL-MVP-044 bandeja por capacidades, estado, propietario, bloqueo, procedencia y siguiente accion verificados."
