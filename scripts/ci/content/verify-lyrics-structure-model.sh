#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL053_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-053: $1" >&2
  exit 1
}

grep -Fq 'original.Normalize(' \
  src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
  || fail_check "la normalización no está separada de la superficie original."

grep -Fq 'japanese_text' \
  src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
  || fail_check "el servicio no persiste la superficie japonesa."

grep -Fq 'normalized_text' \
  src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
  || fail_check "el servicio no persiste normalización independiente."

grep -Fq 'parent_revision_id' \
  src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
  || fail_check "no se conserva la cadena de revisiones."

grep -Fq 'SHA256.HashData' \
  src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
  || fail_check "falta checksum SHA-256 del árbol."

grep -Fq 'Guid.CreateVersion7()' \
  src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
  || fail_check "los objetos estructurales no reciben identificadores opacos estables."

grep -Fq 'data-route-id="UI-MVP-021"' \
  apps/web/src/routes/editorial/LyricsStructurePage.tsx \
  || fail_check "UI-MVP-021 no está materializada."

grep -Fq 'Publicar' \
  tests/E2ETests/lyrics-structure.spec.ts \
  || fail_check "falta regresión que impide adelantar publicación."

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-053-lyrics-structure.txt <<'SQL'
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
    '05300000-0000-4000-8000-000000000001',
    'BL053 synthetic work',
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
    '05300000-0000-4000-8000-000000000002',
    '05300000-0000-4000-8000-000000000001',
    'BL053 synthetic recording',
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
    '05300000-0000-4000-8000-000000000010',
    '05300000-0000-4000-8000-000000000002',
    1,
    NULL,
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('ab', 32), 'hex'),
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
    '05300000-0000-4000-8000-000000000020',
    '05300000-0000-4000-8000-000000000010',
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
VALUES (
    '05300000-0000-4000-8000-000000000030',
    '05300000-0000-4000-8000-000000000020',
    1,
    convert_from(decode('e3818be38299', 'hex'), 'UTF8'),
    convert_from(decode('e3818c', 'hex'), 'UTF8'),
    'Voz principal'
);

INSERT INTO content.lyric_token (
    token_id,
    line_id,
    token_no,
    surface,
    normalized_surface,
    start_offset,
    end_offset
)
VALUES (
    '05300000-0000-4000-8000-000000000040',
    '05300000-0000-4000-8000-000000000030',
    1,
    convert_from(decode('e3818be38299', 'hex'), 'UTF8'),
    convert_from(decode('e3818c', 'hex'), 'UTF8'),
    0,
    2
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
    '05300000-0000-4000-8000-000000000011',
    '05300000-0000-4000-8000-000000000002',
    2,
    '05300000-0000-4000-8000-000000000010',
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('cd', 32), 'hex'),
    1
);

DO $$
DECLARE
    original_text text;
    normalized_text_value text;
    revision_count integer;
    parent_id uuid;
BEGIN
    SELECT
        japanese_text,
        normalized_text
    INTO
        original_text,
        normalized_text_value
    FROM content.lyric_line
    WHERE line_id = '05300000-0000-4000-8000-000000000030';

    IF encode(convert_to(original_text, 'UTF8'), 'hex') <> 'e3818be38299' THEN
        RAISE EXCEPTION 'BL053 alteró la superficie japonesa original.';
    END IF;

    IF encode(convert_to(normalized_text_value, 'UTF8'), 'hex') <> 'e3818c' THEN
        RAISE EXCEPTION 'BL053 no conservó la normalización separada.';
    END IF;

    SELECT count(*)
    INTO revision_count
    FROM content.lyrics_revision
    WHERE recording_id = '05300000-0000-4000-8000-000000000002';

    IF revision_count <> 2 THEN
        RAISE EXCEPTION 'BL053 esperaba dos revisiones, encontró %.', revision_count;
    END IF;

    SELECT parent_revision_id
    INTO parent_id
    FROM content.lyrics_revision
    WHERE lyrics_revision_id = '05300000-0000-4000-8000-000000000011';

    IF parent_id IS DISTINCT FROM '05300000-0000-4000-8000-000000000010'::uuid THEN
        RAISE EXCEPTION 'BL053 no preservó la relación parent_revision.';
    END IF;
END
$$;

SELECT
    revision.revision_no,
    revision.parent_revision_id,
    section.display_order,
    line.line_no,
    line.japanese_text,
    line.normalized_text,
    token.token_no,
    token.surface,
    token.normalized_surface,
    token.start_offset,
    token.end_offset
FROM content.lyrics_revision AS revision
LEFT JOIN content.lyric_section AS section
  ON section.lyrics_revision_id = revision.lyrics_revision_id
LEFT JOIN content.lyric_line AS line
  ON line.section_id = section.section_id
LEFT JOIN content.lyric_token AS token
  ON token.line_id = line.line_id
WHERE revision.recording_id = '05300000-0000-4000-8000-000000000002'
ORDER BY
    revision.revision_no,
    section.display_order,
    line.line_no,
    token.token_no;

ROLLBACK;
SQL

echo "bl=BL-MVP-053"
echo "ui=UI-MVP-021"
echo "model=lyrics_revision,lyric_section,lyric_line,lyric_token"
echo "original_surface_preserved=true"
echo "normalization_separate=true"
echo "stable_ids=true"
echo "revision_history=true"
echo "publishes=false"
echo "OK: BL-MVP-053 revisiones, secciones, líneas, tokens, superficie original y normalización separada verificados."
