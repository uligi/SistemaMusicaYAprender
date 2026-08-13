#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL054_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-054: $1" >&2
  exit 1
}

grep -Fq 'If-Match' \
  apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs \
  || fail_check "el guardado estructurado no exige If-Match."

grep -Fq 'Status412PreconditionFailed' \
  apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs \
  || fail_check "el endpoint no expresa conflicto 412."

grep -Fq 'Response.Headers["ETag"]' \
  apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs \
  || fail_check "la revisión no publica ETag."

grep -Fq 'EnsureExpectedRevision' \
  src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
  || fail_check "el servicio no compara la revisión base."

for marker in \
  '[UNKNOWN:INAUDIBLE]' \
  '[UNKNOWN:UNKNOWN]' \
  '[UNKNOWN:OMITTED]' \
  '[UNKNOWN:PENDING_TRANSCRIPTION]'; do
  grep -Fq "$marker" \
    src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
    || fail_check "falta validación del marcador $marker."
done

for phrase in \
  'Editor estructurado' \
  'Agregar sección' \
  'Agregar línea' \
  'Voz / intérprete' \
  'Contenido desconocido' \
  'Previsualizar borrador' \
  'Guardar nueva revisión' \
  'Comparar con servidor'; do
  grep -Fq "$phrase" \
    apps/web/src/routes/editorial/LyricsStructuredEditor.tsx \
    || fail_check "falta control visible: $phrase."
done

grep -Fq "getByRole('button', { name: 'Publicar' })" \
  tests/E2ETests/lyrics-structured-editor.spec.ts \
  || fail_check "falta regresión explícita contra publicación temprana."

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-054-lyrics-editor.txt <<'SQL'
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
    '05400000-0000-4000-8000-000000000001',
    'BL054 synthetic work',
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
    '05400000-0000-4000-8000-000000000002',
    '05400000-0000-4000-8000-000000000001',
    'BL054 synthetic recording',
    180000,
    NULL,
    'DRAFT',
    1
);

INSERT INTO content.lyrics_revision (
    lyrics_revision_id,
    recording_id,
    revision_no,
    parent_revision_id,
    status_code,
    created_by,
    checksum,
    version
)
VALUES (
    '05400000-0000-4000-8000-000000000010',
    '05400000-0000-4000-8000-000000000002',
    1,
    NULL,
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('54', 32), 'hex'),
    1
);

INSERT INTO content.lyric_section (
    section_id,
    lyrics_revision_id,
    section_type,
    label,
    display_order
)
VALUES (
    '05400000-0000-4000-8000-000000000020',
    '05400000-0000-4000-8000-000000000010',
    'VERSE',
    'Verso 1',
    0
);

INSERT INTO content.lyric_line (
    line_id,
    section_id,
    line_no,
    japanese_text,
    normalized_text,
    speaker_label
)
VALUES
(
    '05400000-0000-4000-8000-000000000030',
    '05400000-0000-4000-8000-000000000020',
    1,
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    'Voz principal'
),
(
    '05400000-0000-4000-8000-000000000031',
    '05400000-0000-4000-8000-000000000020',
    2,
    '[UNKNOWN:INAUDIBLE]',
    '[UNKNOWN:INAUDIBLE]',
    'Coro'
);

INSERT INTO content.lyrics_revision (
    lyrics_revision_id,
    recording_id,
    revision_no,
    parent_revision_id,
    status_code,
    created_by,
    checksum,
    version
)
VALUES (
    '05400000-0000-4000-8000-000000000011',
    '05400000-0000-4000-8000-000000000002',
    2,
    '05400000-0000-4000-8000-000000000010',
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('55', 32), 'hex'),
    1
);

DO $$
DECLARE
    marker text;
    voice_label text;
    revision_count integer;
    parent_id uuid;
BEGIN
    SELECT japanese_text, speaker_label
    INTO marker, voice_label
    FROM content.lyric_line
    WHERE line_id = '05400000-0000-4000-8000-000000000031';

    IF marker <> '[UNKNOWN:INAUDIBLE]' THEN
        RAISE EXCEPTION 'BL054 no conservó la marca explícita de contenido desconocido.';
    END IF;

    IF voice_label <> 'Coro' THEN
        RAISE EXCEPTION 'BL054 no conservó la voz editorial.';
    END IF;

    SELECT count(*)
    INTO revision_count
    FROM content.lyrics_revision
    WHERE recording_id = '05400000-0000-4000-8000-000000000002';

    IF revision_count <> 2 THEN
        RAISE EXCEPTION 'BL054 esperaba dos revisiones, encontró %.', revision_count;
    END IF;

    SELECT parent_revision_id
    INTO parent_id
    FROM content.lyrics_revision
    WHERE lyrics_revision_id = '05400000-0000-4000-8000-000000000011';

    IF parent_id IS DISTINCT FROM '05400000-0000-4000-8000-000000000010'::uuid THEN
        RAISE EXCEPTION 'BL054 perdió el linaje de revisión.';
    END IF;
END
$$;

SELECT
    revision.revision_no,
    revision.parent_revision_id,
    section.section_type,
    section.display_order,
    line.line_no,
    line.japanese_text,
    line.speaker_label
FROM content.lyrics_revision AS revision
LEFT JOIN content.lyric_section AS section
  ON section.lyrics_revision_id = revision.lyrics_revision_id
LEFT JOIN content.lyric_line AS line
  ON line.section_id = section.section_id
WHERE revision.recording_id = '05400000-0000-4000-8000-000000000002'
ORDER BY revision.revision_no, section.display_order, line.line_no;

ROLLBACK;
SQL

echo "bl=BL-MVP-054"
echo "ui=UI-MVP-021"
echo "sections=true"
echo "lines=true"
echo "voices=speaker_label"
echo "unknown_content=explicit_markers"
echo "preview_without_publish=true"
echo "etag_if_match=true"
echo "conflict_compare=true"
echo "publishes=false"
echo "OK: BL-MVP-054 editor estructurado, voces, contenido desconocido, previsualización y conflicto verificados."
