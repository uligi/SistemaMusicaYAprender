#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL061_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-061: $1" >&2
  exit 1
}

grep -Fq 'data-route-id="UI-MVP-023"' \
  apps/web/src/routes/editorial/TranslationStructurePage.tsx \
  || fail_check "UI-MVP-023 no está materializada."

grep -Fq 'translation_revision' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "falta lectura de revisiones de traducción."

grep -Fq 'target_language' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "falta idioma objetivo explícito."

grep -Fq 'VariantCode == "LITERAL"' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "falta cobertura literal independiente."

grep -Fq 'VariantCode == "NATURAL"' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "falta cobertura natural independiente."

grep -Fq 'HasManyToManyAlignment' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "falta señal de alineación N:M."

grep -Fq "TRANSLATION_REVISION" \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "falta procedencia de la revisión."

grep -Fq 'hasStaleRevision' \
  apps/web/src/routes/editorial/TranslationStructurePage.tsx \
  || fail_check "falta degradación explícita ante cambio de letra."

grep -Fq 'AND section.lyrics_revision_id = @lyrics_revision_id' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "las líneas traducidas deben limitarse a la revisión japonesa exacta."

grep -Fq 'anchor_section.lyrics_revision_id = @lyrics_revision_id' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "la línea ancla de cada alineación debe pertenecer a la revisión japonesa exacta."

grep -Fq 'token_section.lyrics_revision_id = @lyrics_revision_id' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "el token de cada alineación debe pertenecer a la revisión japonesa exacta."

grep -Fq 'note_line_section.lyrics_revision_id = @lyrics_revision_id' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "las notas por línea deben permanecer en la revisión japonesa exacta."

grep -Fq 'note_token_section.lyrics_revision_id = @lyrics_revision_id' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  || fail_check "las notas por token deben permanecer en la revisión japonesa exacta."

if grep -Eiq 'deepl|google[[:space:]_-]*translate|microsoft[[:space:]_-]*translator|libretranslate|openai' \
  src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs \
  apps/api/Endpoints/Editorial/TranslationRevisionAdministrationEndpoints.cs \
  apps/web/src/routes/editorial/TranslationStructurePage.tsx; then
  fail_check "BL061 no debe depender de un traductor o servicio lingüístico externo."
fi

if grep -Fq 'Publicar revisión' apps/web/src/routes/editorial/TranslationStructurePage.tsx; then
  fail_check "BL061 no debe adelantar publicación."
fi

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-061-translation-model.txt <<'SQL'
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
    '06100000-0000-4000-8000-000000000001',
    'BL061 synthetic work',
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
    '06100000-0000-4000-8000-000000000002',
    '06100000-0000-4000-8000-000000000001',
    'BL061 synthetic recording',
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
    '06100000-0000-4000-8000-000000000010',
    '06100000-0000-4000-8000-000000000002',
    1,
    NULL,
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('61', 32), 'hex'),
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
    '06100000-0000-4000-8000-000000000020',
    '06100000-0000-4000-8000-000000000010',
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
    '06100000-0000-4000-8000-000000000030',
    '06100000-0000-4000-8000-000000000020',
    1,
    convert_from(decode('e4bd95e5baa6e381a7e38282e58fabE381b6', 'hex'), 'UTF8'),
    convert_from(decode('e4bd95e5baa6e381a7e38282e58fabe381b6', 'hex'), 'UTF8'),
    NULL
),
(
    '06100000-0000-4000-8000-000000000031',
    '06100000-0000-4000-8000-000000000020',
    2,
    convert_from(decode('e38193e38193e381abe6ae8be38197e381a6e3818ae3818de3819fe38184e38293e381a0e38288', 'hex'), 'UTF8'),
    convert_from(decode('e38193e38193e381abe6ae8be38197e381a6e3818ae3818de3819fe38184e38293e381a0e38288', 'hex'), 'UTF8'),
    NULL
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
    '06100000-0000-4000-8000-000000000040',
    '06100000-0000-4000-8000-000000000030',
    1,
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    0,
    4
),
(
    '06100000-0000-4000-8000-000000000041',
    '06100000-0000-4000-8000-000000000030',
    2,
    convert_from(decode('e58fabe381b6', 'hex'), 'UTF8'),
    convert_from(decode('e58fabe381b6', 'hex'), 'UTF8'),
    4,
    6
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
    '06100000-0000-4000-8000-000000000050',
    '06100000-0000-4000-8000-000000000010',
    'es',
    'HUMAN',
    1,
    NULL,
    'DRAFT',
    decode(repeat('62', 32), 'hex')
);

INSERT INTO content.translation_line (
    translation_line_id,
    translation_revision_id,
    line_id,
    translated_text,
    variant_code,
    display_order
)
VALUES
(
    '06100000-0000-4000-8000-000000000060',
    '06100000-0000-4000-8000-000000000050',
    '06100000-0000-4000-8000-000000000030',
    'Grito una y otra vez',
    'LITERAL',
    0
),
(
    '06100000-0000-4000-8000-000000000061',
    '06100000-0000-4000-8000-000000000050',
    '06100000-0000-4000-8000-000000000030',
    'Sigo gritando, una vez más',
    'NATURAL',
    1
),
(
    '06100000-0000-4000-8000-000000000062',
    '06100000-0000-4000-8000-000000000050',
    '06100000-0000-4000-8000-000000000031',
    'Quiero dejarlo aquí',
    'LITERAL',
    2
),
(
    '06100000-0000-4000-8000-000000000063',
    '06100000-0000-4000-8000-000000000050',
    '06100000-0000-4000-8000-000000000031',
    'Quiero que esto permanezca aquí',
    'NATURAL',
    3
);

INSERT INTO content.token_alignment (
    alignment_id,
    translation_line_id,
    token_id,
    target_start,
    target_end,
    alignment_type
)
VALUES
(
    '06100000-0000-4000-8000-000000000070',
    '06100000-0000-4000-8000-000000000060',
    '06100000-0000-4000-8000-000000000040',
    0,
    17,
    'APPROXIMATE'
),
(
    '06100000-0000-4000-8000-000000000071',
    '06100000-0000-4000-8000-000000000060',
    '06100000-0000-4000-8000-000000000041',
    0,
    17,
    'MERGED'
),
(
    '06100000-0000-4000-8000-000000000072',
    '06100000-0000-4000-8000-000000000061',
    '06100000-0000-4000-8000-000000000040',
    0,
    26,
    'APPROXIMATE'
),
(
    '06100000-0000-4000-8000-000000000073',
    '06100000-0000-4000-8000-000000000061',
    '06100000-0000-4000-8000-000000000041',
    0,
    26,
    'APPROXIMATE'
);

INSERT INTO catalog.source_reference (
    source_reference_id,
    source_type,
    citation,
    locator,
    retrieved_at,
    checksum
)
VALUES (
    '06100000-0000-4000-8000-000000000080',
    'EDITORIAL',
    'BL061 synthetic translation decision',
    'revision 1',
    CURRENT_TIMESTAMP,
    decode(repeat('63', 32), 'hex')
);

INSERT INTO content.translation_note (
    note_id,
    translation_revision_id,
    line_id,
    token_id,
    note_type,
    note_text,
    source_reference_id
)
VALUES (
    '06100000-0000-4000-8000-000000000081',
    '06100000-0000-4000-8000-000000000050',
    '06100000-0000-4000-8000-000000000030',
    NULL,
    'EDITORIAL',
    'La repetición conserva el énfasis del original.',
    '06100000-0000-4000-8000-000000000080'
);

INSERT INTO editorial.provenance_record (
    provenance_id,
    object_type,
    object_id,
    source_reference_id,
    contribution_type,
    recorded_by
)
VALUES (
    '06100000-0000-4000-8000-000000000082',
    'TRANSLATION_REVISION',
    '06100000-0000-4000-8000-000000000050',
    '06100000-0000-4000-8000-000000000080',
    'TRANSLATION_SOURCE',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa'
);

DO $$
DECLARE
    exact_revision boolean;
    has_literal_and_natural boolean;
    translation_many_tokens boolean;
    token_many_translations boolean;
    has_provenance boolean;
    has_note boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM content.translation_revision
        WHERE translation_revision_id = '06100000-0000-4000-8000-000000000050'
          AND lyrics_revision_id = '06100000-0000-4000-8000-000000000010'
          AND target_language = 'es'
          AND translation_type = 'HUMAN'
    )
    INTO exact_revision;

    SELECT count(DISTINCT variant_code) = 2
    FROM content.translation_line
    WHERE translation_revision_id = '06100000-0000-4000-8000-000000000050'
      AND line_id = '06100000-0000-4000-8000-000000000030'
      AND variant_code IN ('LITERAL', 'NATURAL')
    INTO has_literal_and_natural;

    SELECT EXISTS (
        SELECT 1
        FROM content.token_alignment
        WHERE translation_line_id IN (
            '06100000-0000-4000-8000-000000000060',
            '06100000-0000-4000-8000-000000000061'
        )
        GROUP BY translation_line_id
        HAVING count(DISTINCT token_id) > 1
    )
    INTO translation_many_tokens;

    SELECT EXISTS (
        SELECT 1
        FROM content.token_alignment
        WHERE translation_line_id IN (
            '06100000-0000-4000-8000-000000000060',
            '06100000-0000-4000-8000-000000000061'
        )
        GROUP BY token_id
        HAVING count(DISTINCT translation_line_id) > 1
    )
    INTO token_many_translations;

    SELECT EXISTS (
        SELECT 1
        FROM editorial.provenance_record
        WHERE object_type = 'TRANSLATION_REVISION'
          AND object_id = '06100000-0000-4000-8000-000000000050'
          AND source_reference_id = '06100000-0000-4000-8000-000000000080'
    )
    INTO has_provenance;

    SELECT EXISTS (
        SELECT 1
        FROM content.translation_note
        WHERE translation_revision_id = '06100000-0000-4000-8000-000000000050'
          AND source_reference_id = '06100000-0000-4000-8000-000000000080'
    )
    INTO has_note;

    IF NOT exact_revision THEN
        RAISE EXCEPTION 'BL061 no conservó la revisión japonesa exacta.';
    END IF;

    IF NOT has_literal_and_natural THEN
        RAISE EXCEPTION 'BL061 no conservó literal y natural de forma independiente.';
    END IF;

    IF NOT translation_many_tokens OR NOT token_many_translations THEN
        RAISE EXCEPTION 'BL061 no demostró alineación N:M entre tokens y unidades traducidas.';
    END IF;

    IF NOT has_provenance OR NOT has_note THEN
        RAISE EXCEPTION 'BL061 no conservó notas y procedencia.';
    END IF;
END
$$;

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
    '06100000-0000-4000-8000-000000000011',
    '06100000-0000-4000-8000-000000000002',
    2,
    '06100000-0000-4000-8000-000000000010',
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('64', 32), 'hex'),
    1
);

DO $$
DECLARE
    latest_lyrics uuid;
    translation_lyrics uuid;
BEGIN
    SELECT lyrics_revision_id
    INTO latest_lyrics
    FROM content.lyrics_revision
    WHERE recording_id = '06100000-0000-4000-8000-000000000002'
    ORDER BY revision_no DESC
    LIMIT 1;

    SELECT lyrics_revision_id
    INTO translation_lyrics
    FROM content.translation_revision
    WHERE translation_revision_id = '06100000-0000-4000-8000-000000000050';

    IF latest_lyrics = translation_lyrics THEN
        RAISE EXCEPTION 'BL061 declaró compatible automáticamente una traducción de letra anterior.';
    END IF;
END
$$;

SELECT
    translation.target_language,
    translation.translation_type,
    translation.revision_no,
    translation.lyrics_revision_id,
    translated.variant_code,
    translated.display_order,
    count(alignment.alignment_id) AS alignment_count
FROM content.translation_revision AS translation
JOIN content.translation_line AS translated
  ON translated.translation_revision_id = translation.translation_revision_id
LEFT JOIN content.token_alignment AS alignment
  ON alignment.translation_line_id = translated.translation_line_id
WHERE translation.translation_revision_id = '06100000-0000-4000-8000-000000000050'
GROUP BY
    translation.target_language,
    translation.translation_type,
    translation.revision_no,
    translation.lyrics_revision_id,
    translated.variant_code,
    translated.display_order
ORDER BY translated.display_order;

ROLLBACK;
SQL

echo "bl=BL-MVP-061"
echo "ui=UI-MVP-023"
echo "model=translation_revision,translation_line,token_alignment,translation_note"
echo "exact_lyrics_revision=true"
echo "many_to_many=true"
echo "literal_natural=true"
echo "provenance=true"
echo "source_change_stale=true"
echo "cross_revision_mixing=false"
echo "external_translation_api=false"
echo "publishes=false"
echo "OK: BL-MVP-061 revisión exacta, literal/natural, alineación N:M, notas, procedencia y fuente obsoleta verificadas."
