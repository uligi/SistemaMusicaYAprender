#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL064_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-064: $1" >&2
  exit 1
}

service="src/Modules/Content/Infrastructure/Administration/LinguisticAnalysisRevisionAdministrationService.cs"
endpoint="apps/api/Endpoints/Editorial/LinguisticAnalysisRevisionAdministrationEndpoints.cs"
page="apps/web/src/routes/editorial/LinguisticAnalysisStructurePage.tsx"

grep -Fq 'data-route-id="UI-MVP-024"' "$page" \
  || fail_check "UI-MVP-024 no está materializada."

grep -Fq 'linguistic_analysis_revision' "$service" \
  || fail_check "falta revisión de análisis lingüístico."

grep -Fq 'section.lyrics_revision_id = @lyrics_revision_id' "$service" \
  || fail_check "falta contención exacta de token/linea por revisión japonesa."

grep -Fq 'start_section.lyrics_revision_id = @lyrics_revision_id' "$service" \
  || fail_check "falta guard exacto para token inicial de gramática."

grep -Fq 'end_section.lyrics_revision_id = @lyrics_revision_id' "$service" \
  || fail_check "falta guard exacto para token final de gramática."

grep -Fq 'content.token_reading' "$service" \
  || fail_check "faltan lecturas contextuales."

grep -Fq 'content.vocabulary_occurrence' "$service" \
  || fail_check "faltan ocurrencias/sentidos de vocabulario."

grep -Fq 'content.morphology_annotation' "$service" \
  || fail_check "falta morfología contextual."

grep -Fq 'content.grammar_occurrence' "$service" \
  || fail_check "falta gramática contextual."

grep -Fq 'content.grammar_explanation' "$service" \
  || fail_check "faltan explicaciones localizadas."

grep -Fq "LINGUISTIC_ANALYSIS_REVISION" "$service" \
  || fail_check "falta procedencia de revisión."

grep -Fq 'hasStaleRevision' "$page" \
  || fail_check "falta estado explícito de fuente obsoleta."

grep -Fq 'RequireAnyEffectivePermission' "$endpoint" \
  || fail_check "falta autorización efectiva."

if grep -Eiq 'openai|anthropic|gemini|deepl|google[[:space:]_-]*translate|microsoft[[:space:]_-]*translator|libretranslate' \
  "$service" "$endpoint" "$page"; then
  fail_check "BL064 no debe usar servicios lingüísticos externos."
fi

if grep -Eiq 'MapPost|INSERT INTO|UPDATE content\.|DELETE FROM' "$endpoint" "$service"; then
  fail_check "BL064 es read-only y no debe escribir análisis."
fi

if grep -Eiq 'Publicar|publish' "$page"; then
  fail_check "BL064 no debe adelantar publicación."
fi

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-064-analysis-model.txt <<'SQL'
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
    '06400000-0000-4000-8000-000000000001',
    'BL064 synthetic work',
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
    '06400000-0000-4000-8000-000000000002',
    '06400000-0000-4000-8000-000000000001',
    'BL064 synthetic recording',
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
    '06400000-0000-4000-8000-000000000010',
    '06400000-0000-4000-8000-000000000002',
    1,
    NULL,
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('64', 32), 'hex'),
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
    '06400000-0000-4000-8000-000000000020',
    '06400000-0000-4000-8000-000000000010',
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
    '06400000-0000-4000-8000-000000000030',
    '06400000-0000-4000-8000-000000000020',
    1,
    convert_from(decode('e4bd95e5baa6e381a7e38282e58fabe381b6', 'hex'), 'UTF8'),
    convert_from(decode('e4bd95e5baa6e381a7e38282e58fabe381b6', 'hex'), 'UTF8'),
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
    '06400000-0000-4000-8000-000000000040',
    '06400000-0000-4000-8000-000000000030',
    1,
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    0,
    4
),
(
    '06400000-0000-4000-8000-000000000041',
    '06400000-0000-4000-8000-000000000030',
    2,
    convert_from(decode('e58fabe381b6', 'hex'), 'UTF8'),
    convert_from(decode('e58fabe381b6', 'hex'), 'UTF8'),
    4,
    6
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
    '06400000-0000-4000-8000-000000000050',
    '06400000-0000-4000-8000-000000000010',
    1,
    NULL,
    'DRAFT',
    decode(repeat('65', 32), 'hex')
);

INSERT INTO content.token_reading (
    token_reading_id,
    analysis_revision_id,
    token_id,
    reading_kana,
    furigana,
    romaji,
    reading_type
)
VALUES (
    '06400000-0000-4000-8000-000000000051',
    '06400000-0000-4000-8000-000000000050',
    '06400000-0000-4000-8000-000000000041',
    convert_from(decode('e38195e38191e381b6', 'hex'), 'UTF8'),
    convert_from(decode('e58fab5be38195e381915de381b6', 'hex'), 'UTF8'),
    'sakebu',
    'CONTEXTUAL'
);

INSERT INTO content.vocabulary_entry (
    vocabulary_id,
    lemma,
    reading,
    part_of_speech,
    sense_key,
    status_code,
    version
)
VALUES (
    '06400000-0000-4000-8000-000000000060',
    convert_from(decode('e58fabe381b6', 'hex'), 'UTF8'),
    convert_from(decode('e38195e38191e381b6', 'hex'), 'UTF8'),
    'VERB',
    'SHOUT',
    'ACTIVE',
    1
);

INSERT INTO content.vocabulary_sense (
    sense_id,
    vocabulary_id,
    language_tag,
    definition,
    usage_note,
    display_order
)
VALUES (
    '06400000-0000-4000-8000-000000000061',
    '06400000-0000-4000-8000-000000000060',
    'es',
    'gritar; llamar en voz alta',
    'Sentido contextual de prueba.',
    0
);

INSERT INTO content.vocabulary_occurrence (
    occurrence_id,
    analysis_revision_id,
    token_id,
    vocabulary_id,
    inflection,
    confidence_code
)
VALUES (
    '06400000-0000-4000-8000-000000000062',
    '06400000-0000-4000-8000-000000000050',
    '06400000-0000-4000-8000-000000000041',
    '06400000-0000-4000-8000-000000000060',
    NULL,
    'CONFIRMED'
);

INSERT INTO content.morphology_annotation (
    annotation_id,
    analysis_revision_id,
    token_id,
    lemma,
    pos_code,
    conjugation_code,
    features
)
VALUES (
    '06400000-0000-4000-8000-000000000070',
    '06400000-0000-4000-8000-000000000050',
    '06400000-0000-4000-8000-000000000041',
    convert_from(decode('e58fabe381b6', 'hex'), 'UTF8'),
    'VERB',
    'DICTIONARY_FORM',
    '{"politeness":"plain"}'::jsonb
);

INSERT INTO content.grammar_point (
    grammar_point_id,
    grammar_code,
    title,
    level_code,
    status_code,
    version
)
VALUES (
    '06400000-0000-4000-8000-000000000080',
    'DEMO.EMPHATIC',
    convert_from(decode('e381a7e3828220656e66c3a17469636f', 'hex'), 'UTF8'),
    'JLPT.N3',
    'ACTIVE',
    1
);

INSERT INTO content.grammar_explanation (
    explanation_id,
    grammar_point_id,
    language_tag,
    explanation,
    examples,
    revision_no
)
VALUES (
    '06400000-0000-4000-8000-000000000081',
    '06400000-0000-4000-8000-000000000080',
    'es',
    convert_from(decode('e381a7e382822070756564652061706f7274617220c3a96e666173697320656e206573746120636f6e73747275636369c3b36e20636f6e7465787475616c2e', 'hex'), 'UTF8'),
    NULL,
    1
);

INSERT INTO content.grammar_occurrence (
    occurrence_id,
    analysis_revision_id,
    grammar_point_id,
    line_id,
    start_token_id,
    end_token_id,
    note
)
VALUES (
    '06400000-0000-4000-8000-000000000082',
    '06400000-0000-4000-8000-000000000050',
    '06400000-0000-4000-8000-000000000080',
    '06400000-0000-4000-8000-000000000030',
    '06400000-0000-4000-8000-000000000040',
    '06400000-0000-4000-8000-000000000040',
    'Ancla gramatical exacta.'
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
    '06400000-0000-4000-8000-000000000090',
    'EDITORIAL',
    'BL064 synthetic linguistic review',
    'analysis revision 1',
    CURRENT_TIMESTAMP,
    decode(repeat('66', 32), 'hex')
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
    '06400000-0000-4000-8000-000000000091',
    'LINGUISTIC_ANALYSIS_REVISION',
    '06400000-0000-4000-8000-000000000050',
    '06400000-0000-4000-8000-000000000090',
    'ANALYSIS_SOURCE',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa'
);

DO $$
DECLARE
    exact_revision boolean;
    reading_ok boolean;
    vocabulary_ok boolean;
    morphology_ok boolean;
    grammar_ok boolean;
    provenance_ok boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM content.linguistic_analysis_revision AS analysis
        WHERE analysis.analysis_revision_id = '06400000-0000-4000-8000-000000000050'
          AND analysis.lyrics_revision_id = '06400000-0000-4000-8000-000000000010'
    ) INTO exact_revision;

    SELECT EXISTS (
        SELECT 1
        FROM content.token_reading AS reading
        JOIN content.lyric_token AS token ON token.token_id = reading.token_id
        JOIN content.lyric_line AS line ON line.line_id = token.line_id
        JOIN content.lyric_section AS section ON section.section_id = line.section_id
        WHERE reading.analysis_revision_id = '06400000-0000-4000-8000-000000000050'
          AND section.lyrics_revision_id = '06400000-0000-4000-8000-000000000010'
    ) INTO reading_ok;

    SELECT EXISTS (
        SELECT 1
        FROM content.vocabulary_occurrence AS occurrence
        JOIN content.vocabulary_entry AS entry ON entry.vocabulary_id = occurrence.vocabulary_id
        JOIN content.vocabulary_sense AS sense ON sense.vocabulary_id = entry.vocabulary_id
        JOIN content.lyric_token AS token ON token.token_id = occurrence.token_id
        JOIN content.lyric_line AS line ON line.line_id = token.line_id
        JOIN content.lyric_section AS section ON section.section_id = line.section_id
        WHERE occurrence.analysis_revision_id = '06400000-0000-4000-8000-000000000050'
          AND sense.language_tag = 'es'
          AND section.lyrics_revision_id = '06400000-0000-4000-8000-000000000010'
    ) INTO vocabulary_ok;

    SELECT EXISTS (
        SELECT 1
        FROM content.morphology_annotation AS annotation
        JOIN content.lyric_token AS token ON token.token_id = annotation.token_id
        JOIN content.lyric_line AS line ON line.line_id = token.line_id
        JOIN content.lyric_section AS section ON section.section_id = line.section_id
        WHERE annotation.analysis_revision_id = '06400000-0000-4000-8000-000000000050'
          AND section.lyrics_revision_id = '06400000-0000-4000-8000-000000000010'
    ) INTO morphology_ok;

    SELECT EXISTS (
        SELECT 1
        FROM content.grammar_occurrence AS occurrence
        JOIN content.lyric_line AS line ON line.line_id = occurrence.line_id
        JOIN content.lyric_section AS section ON section.section_id = line.section_id
        JOIN content.grammar_point AS point ON point.grammar_point_id = occurrence.grammar_point_id
        JOIN content.grammar_explanation AS explanation
          ON explanation.grammar_point_id = point.grammar_point_id
        WHERE occurrence.analysis_revision_id = '06400000-0000-4000-8000-000000000050'
          AND explanation.language_tag = 'es'
          AND section.lyrics_revision_id = '06400000-0000-4000-8000-000000000010'
    ) INTO grammar_ok;

    SELECT EXISTS (
        SELECT 1
        FROM editorial.provenance_record
        WHERE object_type = 'LINGUISTIC_ANALYSIS_REVISION'
          AND object_id = '06400000-0000-4000-8000-000000000050'
    ) INTO provenance_ok;

    IF NOT exact_revision
       OR NOT reading_ok
       OR NOT vocabulary_ok
       OR NOT morphology_ok
       OR NOT grammar_ok
       OR NOT provenance_ok THEN
        RAISE EXCEPTION 'BL064 smoke failed: exact=%, reading=%, vocabulary=%, morphology=%, grammar=%, provenance=%',
            exact_revision,
            reading_ok,
            vocabulary_ok,
            morphology_ok,
            grammar_ok,
            provenance_ok;
    END IF;
END $$;

ROLLBACK;
SQL

echo "bl=BL-MVP-064"
echo "ui=UI-MVP-024"
echo "model=linguistic_analysis_revision,token_reading,vocabulary_occurrence,morphology_annotation,grammar_occurrence"
echo "exact_lyrics_revision=true"
echo "token_revision_guard=true"
echo "line_revision_guard=true"
echo "readings=true"
echo "senses=true"
echo "morphology=true"
echo "grammar_explanations=true"
echo "provenance=true"
echo "source_change_stale=true"
echo "external_analysis_api=false"
echo "writes=false"
echo "publishes=false"
echo "OK: BL-MVP-064 revisión exacta, lecturas, sentidos, morfología, gramática y procedencia verificados."
