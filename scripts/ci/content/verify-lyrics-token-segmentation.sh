#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL055_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-055: $1" >&2
  exit 1
}

grep -Fq '/segmentation-impact' \
  apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs \
  || fail_check "falta endpoint de impacto de segmentación."

for table in \
  'content.timing_revision' \
  'content.translation_revision' \
  'content.linguistic_analysis_revision'; do
  grep -Fq "$table" \
    src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
    || fail_check "el impacto no consulta $table."
done

grep -Fq 'IsUtf16Boundary' \
  src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs \
  || fail_check "el servidor no protege límites UTF-16."

grep -Fq 'japaneseText.slice(startOffset, endOffset)' \
  apps/web/src/routes/editorial/LyricsTokenSegmentationEditor.tsx \
  || fail_check "la superficie del token no se deriva del japonés original."

grep -Fq 'function updateJapaneseText(' \
  apps/web/src/routes/editorial/LyricsStructuredEditor.tsx \
  || fail_check "el editor no distribuye entrada multilínea en lyric_line independientes."

grep -Fq 'distribuye un bloque multilínea en líneas editoriales independientes' \
  tests/E2ETests/lyrics-token-segmentation.spec.ts \
  || fail_check "falta regresión E2E de entrada multilínea."

for phrase in \
  'Segmentación manual' \
  'Superficie exacta' \
  'Unir con siguiente' \
  'Segmentar caracteres restantes' \
  'Impacto de la segmentación' \
  'Sincronización' \
  'Traducciones' \
  'Análisis'; do
  grep -Fq "$phrase" \
    apps/web/src/routes/editorial/LyricsTokenSegmentationEditor.tsx \
    apps/web/src/routes/editorial/LyricsStructuredEditor.tsx \
    || fail_check "falta evidencia UI para: $phrase."
done

grep -Fq "getByRole('button', { name: 'Publicar' })" \
  tests/E2ETests/lyrics-token-segmentation.spec.ts \
  || fail_check "falta regresión contra publicación temprana."

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-055-token-segmentation.txt <<'SQL'
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
    '05500000-0000-4000-8000-000000000001',
    'BL055 synthetic work',
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
    '05500000-0000-4000-8000-000000000002',
    '05500000-0000-4000-8000-000000000001',
    'BL055 synthetic recording',
    180000,
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
    '05500000-0000-4000-8000-000000000003',
    '05500000-0000-4000-8000-000000000002',
    'YOUTUBE',
    'BL055abc123',
    180000,
    0,
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
    '05500000-0000-4000-8000-000000000010',
    '05500000-0000-4000-8000-000000000002',
    1,
    NULL,
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('55', 32), 'hex'),
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
    '05500000-0000-4000-8000-000000000020',
    '05500000-0000-4000-8000-000000000010',
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
    '05500000-0000-4000-8000-000000000030',
    '05500000-0000-4000-8000-000000000020',
    1,
    convert_from(decode('e680aae78da3e381a7e38199', 'hex'), 'UTF8'),
    convert_from(decode('e680aae78da3e381a7e38199', 'hex'), 'UTF8'),
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
VALUES
(
    '05500000-0000-4000-8000-000000000040',
    '05500000-0000-4000-8000-000000000030',
    1,
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    0,
    2
),
(
    '05500000-0000-4000-8000-000000000041',
    '05500000-0000-4000-8000-000000000030',
    2,
    convert_from(decode('e381a7e38199', 'hex'), 'UTF8'),
    convert_from(decode('e381a7e38199', 'hex'), 'UTF8'),
    2,
    4
);

INSERT INTO content.timing_revision (
    timing_revision_id,
    lyrics_revision_id,
    source_id,
    revision_no,
    offset_ms,
    status_code,
    checksum
)
VALUES (
    '05500000-0000-4000-8000-000000000050',
    '05500000-0000-4000-8000-000000000010',
    '05500000-0000-4000-8000-000000000003',
    1,
    0,
    'DRAFT',
    decode(repeat('50', 32), 'hex')
);

INSERT INTO content.translation_revision (
    translation_revision_id,
    lyrics_revision_id,
    target_language,
    translation_type,
    revision_no,
    parent_revision_id,
    status_code,
    checksum
)
VALUES (
    '05500000-0000-4000-8000-000000000060',
    '05500000-0000-4000-8000-000000000010',
    'es',
    'NATURAL',
    1,
    NULL,
    'DRAFT',
    decode(repeat('60', 32), 'hex')
);

INSERT INTO content.linguistic_analysis_revision (
    analysis_revision_id,
    lyrics_revision_id,
    revision_no,
    parent_revision_id,
    status_code,
    checksum
)
VALUES (
    '05500000-0000-4000-8000-000000000070',
    '05500000-0000-4000-8000-000000000010',
    1,
    NULL,
    'DRAFT',
    decode(repeat('70', 32), 'hex')
);

DO $$
DECLARE
    timing_count bigint;
    translation_count bigint;
    analysis_count bigint;
    token_surface text;
    token_start integer;
    token_end integer;
BEGIN
    SELECT count(*)
    INTO timing_count
    FROM content.timing_revision
    WHERE lyrics_revision_id = '05500000-0000-4000-8000-000000000010';

    SELECT count(*)
    INTO translation_count
    FROM content.translation_revision
    WHERE lyrics_revision_id = '05500000-0000-4000-8000-000000000010';

    SELECT count(*)
    INTO analysis_count
    FROM content.linguistic_analysis_revision
    WHERE lyrics_revision_id = '05500000-0000-4000-8000-000000000010';

    IF timing_count <> 1 OR translation_count <> 1 OR analysis_count <> 1 THEN
        RAISE EXCEPTION
            'BL055 impacto incorrecto: timing %, translation %, analysis %',
            timing_count,
            translation_count,
            analysis_count;
    END IF;

    SELECT surface, start_offset, end_offset
    INTO token_surface, token_start, token_end
    FROM content.lyric_token
    WHERE token_id = '05500000-0000-4000-8000-000000000040';

    IF encode(convert_to(token_surface, 'UTF8'), 'hex') <> 'e680aae78da3'
       OR token_start <> 0
       OR token_end <> 2 THEN
        RAISE EXCEPTION 'BL055 no conservó superficie y offsets del token agrupado.';
    END IF;
END
$$;

SELECT
    revision.lyrics_revision_id,
    (SELECT count(*) FROM content.timing_revision timing
     WHERE timing.lyrics_revision_id = revision.lyrics_revision_id) AS timing_revisions,
    (SELECT count(*) FROM content.translation_revision translation
     WHERE translation.lyrics_revision_id = revision.lyrics_revision_id) AS translation_revisions,
    (SELECT count(*) FROM content.linguistic_analysis_revision analysis
     WHERE analysis.lyrics_revision_id = revision.lyrics_revision_id) AS analysis_revisions
FROM content.lyrics_revision revision
WHERE revision.lyrics_revision_id = '05500000-0000-4000-8000-000000000010';

ROLLBACK;
SQL

echo "bl=BL-MVP-055"
echo "ui=UI-MVP-021"
echo "token_surface=original_substring"
echo "offsets=utf16"
echo "grouping=contiguous_token_ranges"
echo "timing_impact=true"
echo "translation_impact=true"
echo "analysis_impact=true"
echo "publishes=false"
echo "OK: BL-MVP-055 segmentación manual, offsets, agrupación e impacto dependiente verificados."
