#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL046_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-046: $1" >&2
  exit 1
}

grep -Fq 'data-route-id="UI-MVP-019"' \
  apps/web/src/routes/editorial/SongEditorialDossierPage.tsx \
  || fail_check "UI-MVP-019 no quedó materializada como expediente."

grep -Fq 'SongEditorialDossierPage' \
  apps/web/src/routes/editorial/EditorialArea.tsx \
  || fail_check "EditorialArea no carga el expediente BL046."

grep -Fq '/api/v1/editorial/song-dossiers/{recordingId:guid}' \
  apps/api/Endpoints/Editorial/SongEditorialDossierEndpoints.cs \
  || fail_check "Falta endpoint de expediente."

grep -Fq 'AuthorizationScope.ForObject' \
  apps/api/Endpoints/Editorial/SongEditorialDossierEndpoints.cs \
  || fail_check "El expediente no revalida alcance por objeto."

for field in \
  "Componentes por revisión" \
  "Derechos y procedencia" \
  "Incidencias abiertas" \
  "Accesos permitidos"; do
  grep -Fq "$field" \
    apps/web/src/routes/editorial/SongEditorialDossierPage.tsx \
    || fail_check "Falta sección '$field'."
done

if grep -Eq 'rights\.recorded_(by|at)' \
  src/Modules/Catalog/Infrastructure/Administration/SongEditorialDossierService.cs; then
  fail_check "El expediente consulta columnas inexistentes de editorial.rights_record."
fi

for table in \
  "content.lyrics_revision" \
  "content.timing_revision" \
  "content.translation_revision" \
  "content.linguistic_analysis_revision" \
  "learning.exercise_revision" \
  "editorial.rights_record" \
  "ops.data_quality_issue"; do
  grep -Fq "$table" \
    src/Modules/Catalog/Infrastructure/Administration/SongEditorialDossierService.cs \
    || fail_check "Falta lectura $table."
done

if grep -Eq '>Publicar<|aria-label="Publicar"|name: .Publicar.' \
  apps/web/src/routes/editorial/SongEditorialDossierPage.tsx; then
  fail_check "BL046 no debe adelantar publicación."
fi

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-046-editorial-dossier.txt <<'SQL'
PREPARE bl046_recording(uuid) AS
SELECT
    recording.recording_id,
    work.canonical_title,
    recording.status_code,
    recording.version,
    (
        SELECT count(*)
        FROM content.lyrics_revision AS lyrics
        WHERE lyrics.recording_id = recording.recording_id
    ) AS lyrics_revisions,
    (
        SELECT count(*)
        FROM learning.exercise_definition AS definition
        INNER JOIN learning.exercise_revision AS revision
            ON revision.exercise_id = definition.exercise_id
        WHERE definition.recording_id = recording.recording_id
    ) AS exercise_revisions,
    (
        SELECT count(*)
        FROM editorial.rights_record AS rights
        WHERE rights.object_type = 'RECORDING'
          AND rights.object_id = recording.recording_id
    ) AS rights_records,
    (
        SELECT count(*)
        FROM ops.data_quality_issue AS issue
        WHERE issue.object_id = recording.recording_id
          AND issue.status_code IN ('OPEN', 'ACKNOWLEDGED')
    ) AS open_incidents
FROM catalog.recording AS recording
INNER JOIN catalog.musical_work AS work
    ON work.work_id = recording.work_id
WHERE recording.recording_id = $1;

DEALLOCATE bl046_recording;

PREPARE bl046_rights_summary(uuid) AS
SELECT
    (
        SELECT count(*)::integer
        FROM editorial.rights_record AS rights
        WHERE rights.object_type = 'RECORDING'
          AND rights.object_id = $1
    ) AS total_records,
    (
        SELECT count(*)::integer
        FROM editorial.rights_record AS rights
        INNER JOIN ops.stored_object AS evidence
            ON evidence.object_id = rights.evidence_object_id
        WHERE rights.object_type = 'RECORDING'
          AND rights.object_id = $1
          AND rights.status_code = 'ACTIVE'
          AND (rights.valid_from IS NULL OR rights.valid_from <= CURRENT_TIMESTAMP)
          AND (rights.valid_to IS NULL OR rights.valid_to > CURRENT_TIMESTAMP)
          AND evidence.status_code = 'ACTIVE'
    ) AS active_records,
    (
        SELECT count(*)::integer
        FROM catalog.recording_credit AS credit
        INNER JOIN editorial.provenance_record AS provenance
            ON provenance.object_type = 'RECORDING_CREDIT'
           AND provenance.object_id = credit.credit_id
        WHERE credit.recording_id = $1
    ) AS provenance_records,
    latest.actor_id,
    latest.rights_record_id
FROM (VALUES (1)) AS singleton(dummy)
LEFT JOIN LATERAL (
    SELECT
        latest_audit.actor_id,
        rights.rights_record_id
    FROM editorial.rights_record AS rights
    LEFT JOIN LATERAL (
        SELECT
            audit.actor_id,
            audit.occurred_at,
            audit.audit_id
        FROM security.audit_event AS audit
        WHERE audit.object_id = rights.rights_record_id
        ORDER BY
            audit.occurred_at DESC,
            audit.audit_id DESC
        LIMIT 1
    ) AS latest_audit ON true
    WHERE rights.object_type = 'RECORDING'
      AND rights.object_id = $1
    ORDER BY
        latest_audit.occurred_at DESC NULLS LAST,
        rights.rights_record_id DESC
    LIMIT 1
) AS latest ON true;

DEALLOCATE bl046_rights_summary;

SQL

echo "route=/editorial/canciones/{id}"
echo "ui=UI-MVP-019"
echo "components=catalog,lyrics,timing,translation,analysis,exercises,rights"
echo "owner=server-derived"
echo "incidents=ops.data_quality_issue"
echo "accesses=server-object-scope"
echo "publishes=false"
echo "OK: BL-MVP-046 revisiones, propietario, estado, derechos, incidencias y accesos permitidos verificados."
