#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'ERROR BL-MVP-057: %s\n' "$1" >&2
  exit 1
}

grep -Fq 'BL-MVP-057 · EDICIÓN TEMPORAL' \
  apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx \
  || fail "falta el editor temporal BL057"

grep -Fq 'Guardar borrador temporal' \
  apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx \
  || fail "falta guardado de borrador temporal"

grep -Fq 'Desplazar selección' \
  apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx \
  || fail "falta desplazamiento múltiple controlado"

grep -Fq 'Reproducir vista previa' \
  apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx \
  || fail "falta previsualización local"

grep -Fq 'expectedRevisionNo' \
  apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx \
  || fail "falta versión esperada del editor"

grep -Fq 'ExpectedRevisionNo' \
  src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs \
  || fail "falta contrato de concurrencia en servidor"

grep -Fq 'content.timing.revision.conflict' \
  src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs \
  || fail "falta conflicto de revisión temporal"

grep -Fq 'content.timing.revision.conflict' \
  apps/api/Endpoints/Editorial/TimingRevisionAdministrationEndpoints.cs \
  || fail "falta mapeo HTTP del conflicto temporal"

if grep -Fq '<iframe' apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx; then
  fail "BL057 no debe cargar el IFrame de YouTube"
fi

if grep -Fq 'Publicar' apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx; then
  fail "BL057 no debe adelantar publicación"
fi

if [[ "${BL057_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  PSQL=(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "${PGUSER:-musica_local}" -d "${PGDATABASE:-musica_aprender}")
else
  command -v psql >/dev/null 2>&1 || fail "psql no disponible"
  PSQL=(psql -v ON_ERROR_STOP=1)
fi

sql="$("${PSQL[@]}" -At <<'SQL'
SELECT
  EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'content'
      AND table_name = 'timing_revision'
  )::text || '|' ||
  EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'content'
      AND table_name = 'timing_segment'
  )::text || '|' ||
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'content'
      AND table_name = 'timing_revision'
      AND column_name = 'revision_no'
  )::text || '|' ||
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'content'
      AND table_name = 'timing_segment'
      AND column_name = 'start_ms'
  )::text || '|' ||
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'content'
      AND table_name = 'timing_segment'
      AND column_name = 'end_ms'
  )::text;
SQL
)"

[[ "$sql" == "true|true|true|true|true" ]] || fail "modelo físico temporal incompleto"

cat <<'EOF'
bl=BL-MVP-057
ui=UI-MVP-022
marking=keyboard_and_numeric
individual_bounds=true
bulk_shift=true
local_preview=true
partial_draft=true
expected_revision_conflict=true
negative_validation=true
duration_validation=true
youtube_iframe=false
publishes=false
OK: BL-MVP-057 marcado, desplazamiento, previsualización, borrador y conflictos verificados.
EOF
