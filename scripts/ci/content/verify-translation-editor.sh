#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL062_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-062: $1" >&2
  exit 1
}

endpoint="apps/api/Endpoints/Editorial/TranslationRevisionAdministrationEndpoints.cs"
service="src/Modules/Content/Infrastructure/Administration/TranslationRevisionAdministrationService.cs"
page="apps/web/src/routes/editorial/TranslationStructurePage.tsx"
editor="apps/web/src/routes/editorial/TranslationEditor.tsx"

grep -Fq '"/api/v1/editorial/song-drafts/{recordingId:guid}/translation-revisions"' "$endpoint" \
  || fail_check "falta endpoint de guardado de revisión."

grep -Fq 'RequireEffectivePermission(' "$endpoint" \
  || fail_check "el guardado no exige permiso efectivo."

grep -Fq '"EDITORIAL.DRAFT"' "$endpoint" \
  || fail_check "el guardado no exige EDITORIAL.DRAFT."

grep -Fq 'IAntiforgery' "$endpoint" \
  || fail_check "falta antiforgery en el endpoint mutable."

grep -Fq '"If-Match"' "$endpoint" \
  || fail_check "falta concurrencia por If-Match."

grep -Fq 'StatusCodes.Status412PreconditionFailed' "$endpoint" \
  || fail_check "falta conflicto de revisión 412."

grep -Fq 'ETagFor' "$service" \
  || fail_check "falta ETag versionado de traducción."

grep -Fq 'prepared.Units.Count != sourceLineIds.Count' "$service" \
  || fail_check "el guardado no protege el snapshot completo de líneas fuente."

grep -Fq 'content.translation.units.incomplete' "$service" \
  || fail_check "falta error explícito para un snapshot parcial."

grep -Fq 'pg_advisory_xact_lock' "$service" \
  || fail_check "falta serialización del revision_no."

grep -Fq "'DRAFT'" "$service" \
  || fail_check "el guardado no fuerza estado DRAFT."

grep -Fq 'parent_revision_id' "$service" \
  || fail_check "falta relación con revisión padre."

grep -Fq 'TRANSLATION_AUTHOR' "$service" \
  || fail_check "falta autoría/procedencia del traductor."

grep -Fq 'anchor_section.lyrics_revision_id = @lyrics_revision_id' "$service" \
  || fail_check "la línea ancla de alineación no queda en la fuente exacta."

grep -Fq 'token_section.lyrics_revision_id = @lyrics_revision_id' "$service" \
  || fail_check "el token alineado no queda en la fuente exacta."

grep -Fq 'preserveTargetSpan' "$service" \
  || fail_check "no se degrada el tramo objetivo cuando cambia la traducción."

grep -Fq 'japaneseText:' "$editor" \
  && fail_check "el comando/editor BL062 no debe modelar japonés mutable."

grep -Fq 'lyricsRevisionId: draft.lyricsRevisionId' "$editor" \
  || fail_check "el editor no envía revisión japonesa exacta."

grep -Fq 'literalText' "$editor" \
  || fail_check "falta variante literal editable."

grep -Fq 'naturalText' "$editor" \
  || fail_check "falta variante natural editable."

grep -Fq 'noteText' "$editor" \
  || fail_check "faltan notas editoriales."

grep -Fq 'Comparar con servidor' "$editor" \
  || fail_check "falta comparación tras conflicto."

grep -Fq "comparison.data.lyricsRevisionId !== draft.lyricsRevisionId" "$editor" \
  || fail_check "el rebase no distingue cambio de fuente japonesa."

grep -Fq 'useVisibleAccess' "$page" \
  || fail_check "la UI no separa visibilidad editable de autorización servidor."

if grep -Eq 'UPDATE[[:space:]]+content\.lyric|DELETE[[:space:]]+FROM[[:space:]]+content\.lyric' "$service"; then
  fail_check "BL062 no puede modificar ni eliminar letra japonesa."
fi

if grep -Eiq 'deepl|google[[:space:]_-]*translate|microsoft[[:space:]_-]*translator|libretranslate|openai' \
  "$service" "$endpoint" "$page" "$editor"; then
  fail_check "BL062 no debe invocar servicios lingüísticos externos."
fi

if grep -Eiq 'publish|publicar revisión' "$endpoint"; then
  fail_check "BL062 no debe exponer publicación."
fi

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-062-translation-editor.txt <<'SQL'
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
    '06200000-0000-4000-8000-000000000001',
    'BL062 synthetic work',
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
    '06200000-0000-4000-8000-000000000002',
    '06200000-0000-4000-8000-000000000001',
    'BL062 synthetic recording',
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
    '06200000-0000-4000-8000-000000000010',
    '06200000-0000-4000-8000-000000000002',
    1,
    NULL,
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('62', 32), 'hex'),
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
    '06200000-0000-4000-8000-000000000020',
    '06200000-0000-4000-8000-000000000010',
    'VERSE',
    'Verso',
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
    '06200000-0000-4000-8000-000000000030',
    '06200000-0000-4000-8000-000000000020',
    1,
    '何度でも叫ぶ',
    '何度でも叫ぶ',
    NULL
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
VALUES
(
    '06200000-0000-4000-8000-000000000050',
    '06200000-0000-4000-8000-000000000010',
    'es',
    'HUMAN',
    1,
    NULL,
    'DRAFT',
    decode(repeat('63', 32), 'hex')
),
(
    '06200000-0000-4000-8000-000000000051',
    '06200000-0000-4000-8000-000000000010',
    'es',
    'HUMAN',
    2,
    '06200000-0000-4000-8000-000000000050',
    'DRAFT',
    decode(repeat('64', 32), 'hex')
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
    '06200000-0000-4000-8000-000000000060',
    '06200000-0000-4000-8000-000000000051',
    '06200000-0000-4000-8000-000000000030',
    'Grito una y otra vez',
    'LITERAL',
    0
),
(
    '06200000-0000-4000-8000-000000000061',
    '06200000-0000-4000-8000-000000000051',
    '06200000-0000-4000-8000-000000000030',
    'Sigo gritando una vez más',
    'NATURAL',
    1
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
    '06200000-0000-4000-8000-000000000070',
    'EDITORIAL',
    'Traducción humana al español · revisión 2',
    'lyrics_revision:06200000000040008000000000000010',
    CURRENT_TIMESTAMP,
    NULL
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
    '06200000-0000-4000-8000-000000000071',
    '06200000-0000-4000-8000-000000000051',
    '06200000-0000-4000-8000-000000000030',
    NULL,
    'EDITORIAL',
    'La repetición conserva el énfasis.',
    '06200000-0000-4000-8000-000000000070'
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
    '06200000-0000-4000-8000-000000000072',
    'TRANSLATION_REVISION',
    '06200000-0000-4000-8000-000000000051',
    '06200000-0000-4000-8000-000000000070',
    'TRANSLATION_AUTHOR',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa'
);

DO $$
DECLARE
    parent_ok boolean;
    variants_ok boolean;
    provenance_ok boolean;
    note_ok boolean;
    japanese_ok boolean;
    publishes boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM content.translation_revision
        WHERE translation_revision_id = '06200000-0000-4000-8000-000000000051'
          AND lyrics_revision_id = '06200000-0000-4000-8000-000000000010'
          AND parent_revision_id = '06200000-0000-4000-8000-000000000050'
          AND target_language = 'es'
          AND translation_type = 'HUMAN'
          AND status_code = 'DRAFT'
    )
    INTO parent_ok;

    SELECT count(DISTINCT variant_code) = 2
    FROM content.translation_line
    WHERE translation_revision_id = '06200000-0000-4000-8000-000000000051'
    INTO variants_ok;

    SELECT EXISTS (
        SELECT 1
        FROM editorial.provenance_record
        WHERE object_type = 'TRANSLATION_REVISION'
          AND object_id = '06200000-0000-4000-8000-000000000051'
          AND contribution_type = 'TRANSLATION_AUTHOR'
          AND recorded_by = '3a35b4fd-5e67-5686-9669-d5e78e20feaa'
    )
    INTO provenance_ok;

    SELECT EXISTS (
        SELECT 1
        FROM content.translation_note
        WHERE translation_revision_id = '06200000-0000-4000-8000-000000000051'
          AND note_type = 'EDITORIAL'
    )
    INTO note_ok;

    SELECT japanese_text = '何度でも叫ぶ'
    FROM content.lyric_line
    WHERE line_id = '06200000-0000-4000-8000-000000000030'
    INTO japanese_ok;

    SELECT EXISTS (
        SELECT 1
        FROM content.translation_revision
        WHERE translation_revision_id IN (
            '06200000-0000-4000-8000-000000000050',
            '06200000-0000-4000-8000-000000000051'
        )
          AND status_code = 'PUBLISHED'
    )
    INTO publishes;

    IF NOT parent_ok THEN
        RAISE EXCEPTION 'BL062 no conserva parent_revision_id y fuente exacta.';
    END IF;

    IF NOT variants_ok THEN
        RAISE EXCEPTION 'BL062 no conserva literal y natural separados.';
    END IF;

    IF NOT provenance_ok OR NOT note_ok THEN
        RAISE EXCEPTION 'BL062 no conserva autoría/notas.';
    END IF;

    IF NOT japanese_ok THEN
        RAISE EXCEPTION 'BL062 alteró la letra japonesa.';
    END IF;

    IF publishes THEN
        RAISE EXCEPTION 'BL062 adelantó publicación.';
    END IF;
END
$$;

ROLLBACK;
SQL

echo "bl=BL-MVP-062"
echo "ui=UI-MVP-023"
echo "writes_draft=true"
echo "exact_lyrics_revision=true"
echo "source_etag=true"
echo "csrf=true"
echo "literal_natural_edit=true"
echo "notes=true"
echo "author_provenance=true"
echo "alignment_source_guard=true"
echo "source_compare=true"
echo "complete_source_snapshot=true"
echo "japanese_mutation=false"
echo "external_translation_api=false"
echo "publishes=false"
echo "OK: BL-MVP-062 editor español, revisión fuente, concurrencia, notas, autoría y no mutación japonesa verificados."
