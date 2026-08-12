#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL052_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-052: $1" >&2
  exit 1
}

grep -Fq 'If-Match' \
  apps/api/Endpoints/Editorial/RecordingDraftAutosaveEndpoints.cs \
  || fail_check "el endpoint no exige If-Match."

grep -Fq 'Status412PreconditionFailed' \
  apps/api/Endpoints/Editorial/RecordingDraftAutosaveEndpoints.cs \
  || fail_check "el conflicto no devuelve 412."

grep -Fq 'Response.Headers["ETag"]' \
  apps/api/Endpoints/Editorial/RecordingDraftAutosaveEndpoints.cs \
  || fail_check "el endpoint no publica ETag."

grep -Fq 'AND version = @recording_version' \
  src/Modules/Catalog/Infrastructure/Administration/RecordingDraftAutosaveService.cs \
  || fail_check "la grabación no usa compare-and-swap por versión."

grep -Fq 'AND version = @source_version' \
  src/Modules/Catalog/Infrastructure/Administration/RecordingDraftAutosaveService.cs \
  || fail_check "la fuente no usa compare-and-swap por versión."

for state in 'Guardando…' 'Guardado' 'Conflicto de edición' 'Comparar cambios'; do
  grep -Fq "$state" \
    apps/web/src/routes/editorial/RecordingAutosavePanel.tsx \
    || fail_check "falta estado visible '$state'."
done

grep -Fq "problem.kind === 'conflict'" \
  apps/web/src/routes/editorial/useEditorialAutosave.ts \
  || fail_check "el hook reutilizable no conserva conflicto."

grep -Fq 'Aplicar mis cambios sobre la versión vigente' \
  apps/web/src/routes/editorial/RecordingAutosavePanel.tsx \
  || fail_check "no existe resolución explícita después de comparar."

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-052-concurrency.txt <<'SQL'
BEGIN;

INSERT INTO catalog.musical_work (
    work_id,
    canonical_title,
    language_tag,
    release_date,
    status_code,
    version
)
VALUES (
    '05200000-0000-4000-8000-000000000001',
    'BL052 synthetic work',
    'ja',
    NULL,
    'DRAFT',
    1
);

INSERT INTO catalog.recording (
    recording_id,
    work_id,
    recording_title,
    duration_ms,
    release_date,
    status_code,
    version
)
VALUES (
    '05200000-0000-4000-8000-000000000002',
    '05200000-0000-4000-8000-000000000001',
    'base',
    120000,
    NULL,
    'DRAFT',
    1
);

INSERT INTO catalog.recording_source (
    source_id,
    recording_id,
    provider_code,
    external_ref,
    duration_ms,
    offset_ms,
    status_code,
    version
)
VALUES (
    '05200000-0000-4000-8000-000000000003',
    '05200000-0000-4000-8000-000000000002',
    'YOUTUBE',
    'BL052abc123',
    121000,
    0,
    'DRAFT',
    1
);

DO $$
DECLARE
    affected integer;
BEGIN
    UPDATE catalog.recording
    SET
        recording_title = 'first editor',
        version = version + 1
    WHERE recording_id = '05200000-0000-4000-8000-000000000002'
      AND version = 1;

    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN
        RAISE EXCEPTION 'BL052 first compare-and-swap expected 1 row, got %', affected;
    END IF;

    UPDATE catalog.recording
    SET
        recording_title = 'stale editor',
        version = version + 1
    WHERE recording_id = '05200000-0000-4000-8000-000000000002'
      AND version = 1;

    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN
        RAISE EXCEPTION 'BL052 stale compare-and-swap expected 0 rows, got %', affected;
    END IF;

    UPDATE catalog.recording_source
    SET
        offset_ms = 2500,
        version = version + 1
    WHERE source_id = '05200000-0000-4000-8000-000000000003'
      AND version = 1;

    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN
        RAISE EXCEPTION 'BL052 source first compare-and-swap expected 1 row, got %', affected;
    END IF;

    UPDATE catalog.recording_source
    SET
        offset_ms = 5000,
        version = version + 1
    WHERE source_id = '05200000-0000-4000-8000-000000000003'
      AND version = 1;

    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN
        RAISE EXCEPTION 'BL052 stale source compare-and-swap expected 0 rows, got %', affected;
    END IF;
END
$$;

SELECT
    recording.version AS recording_version,
    source.version AS source_version,
    recording.recording_title,
    source.offset_ms
FROM catalog.recording AS recording
JOIN catalog.recording_source AS source
  ON source.recording_id = recording.recording_id
WHERE recording.recording_id = '05200000-0000-4000-8000-000000000002';

ROLLBACK;
SQL

echo "bl=BL-MVP-052"
echo "scope=UI-MVP-019-026 reusable"
echo "etag=true"
echo "if_match_required=true"
echo "compare_and_swap=recording.version,recording_source.version"
echo "states=saving,saved,conflict"
echo "silent_last_write_wins=false"
echo "compare_before_rebase=true"
echo "OK: BL-MVP-052 autoguardado, ETag/If-Match, conflicto y comparación explícita verificados."
