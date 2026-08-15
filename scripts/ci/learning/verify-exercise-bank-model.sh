#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${PGHOST:?PGHOST requerido}"
: "${PGPORT:?PGPORT requerido}"
: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"
: "${PGPASSWORD:?PGPASSWORD requerido}"

if [[ "${BL070_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
  echo "ERROR: BL-MVP-070: $1" >&2
  exit 1
}

service="src/Modules/Learning/Infrastructure/Administration/ExerciseBankAdministrationService.cs"
endpoint="apps/api/Endpoints/Editorial/ExerciseBankAdministrationEndpoints.cs"
page="apps/web/src/routes/editorial/ExerciseBankPage.tsx"
test_file="tests/E2ETests/exercise-bank-model.spec.ts"

grep -Fq "learning.exercise_definition" "$service" \
  || fail_check "falta identidad estable del ejercicio."
grep -Fq "learning.exercise_revision" "$service" \
  || fail_check "faltan revisiones versionadas."
grep -Fq "learning.exercise_item" "$service" \
  || fail_check "faltan opciones/elementos ordenados."
grep -Fq "content.lyrics_revision" "$service" \
  || fail_check "falta contexto de revisión fuente."
grep -Fq "EXERCISE_REVISION" "$service" \
  || fail_check "falta procedencia por revisión."
grep -Fq "acceptedItemOrders" "$service" \
  || fail_check "falta solución explícita versionada."
grep -Fq "difficulty" "$service" \
  || fail_check "falta dificultad editorial."
grep -Fq "explanation" "$service" \
  || fail_check "falta explicación educativa."
grep -Fq "ReadyForReview" "$service" \
  || fail_check "falta señal de integridad para revisión."

grep -Fq "/exercise-bank" "$endpoint" \
  || fail_check "falta API editorial del banco."
grep -Fq "RequireEffectivePermission" "$endpoint" \
  || fail_check "falta autorización efectiva."
grep -Fq '"EDITORIAL.DRAFT"' "$endpoint" \
  || fail_check "UI-MVP-025 debe exigir capacidad editorial."
grep -Fq 'moduleCode: "M08"' "$endpoint" \
  || fail_check "el banco no está autorizado bajo M08."

grep -Fq 'data-route-id="UI-MVP-025"' "$page" \
  || fail_check "UI-MVP-025 no está materializada."
grep -Fq "Banco de ejercicios" "$page" \
  || fail_check "falta superficie editorial del banco."
grep -Fq "BL-MVP-071" "$page" \
  || fail_check "falta límite explícito con la autoría siguiente."

if grep -Eiq 'MapPost|MapPut|MapPatch|MapDelete' "$endpoint"; then
  fail_check "BL070 modela y lee; la autoría/escritura corresponde a BL071."
fi

if grep -Eiq 'INSERT INTO|UPDATE learning\.|DELETE FROM learning\.' "$service"; then
  fail_check "BL070 no debe escribir el banco con el rol backoffice de solo lectura en learning."
fi

if grep -Eiq 'openai|anthropic|gemini|deepl|google[[:space:]_-]*translate|dictionaryapi|jisho' \
  "$service" "$endpoint" "$page"; then
  fail_check "M08 no debe usar servicios lingüísticos externos."
fi

grep -Fq "AxeBuilder" "$test_file" \
  || fail_check "falta evidencia de accesibilidad."
grep -Fq "320" "$test_file" \
  || fail_check "falta evidencia de reflujo 320px."
grep -Fq "no adelanta la autoría BL071" "$test_file" \
  || fail_check "falta frontera de alcance BL070/071."

mkdir -p artifacts/postgres

"${psql_base[@]}" > artifacts/postgres/bl-mvp-070-exercise-bank-model.txt <<'SQL'
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
    '07000000-0000-4000-8000-000000000001',
    'BL070 synthetic work',
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
    '07000000-0000-4000-8000-000000000002',
    '07000000-0000-4000-8000-000000000001',
    'BL070 synthetic recording',
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
    '07000000-0000-4000-8000-000000000010',
    '07000000-0000-4000-8000-000000000002',
    3,
    NULL,
    'DRAFT',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa',
    decode(repeat('70', 32), 'hex'),
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
    '07000000-0000-4000-8000-000000000020',
    '07000000-0000-4000-8000-000000000010',
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
    '07000000-0000-4000-8000-000000000030',
    '07000000-0000-4000-8000-000000000020',
    1,
    convert_from(decode('e4bd95e5baa6e381a7e38282e58fabe381b6', 'hex'), 'UTF8'),
    convert_from(decode('e4bd95e5baa6e381a7e38282e58fabe381b6', 'hex'), 'UTF8'),
    NULL
);

INSERT INTO learning.competency (
    competency_id,
    competency_code,
    domain_code,
    title,
    definition,
    version
)
VALUES (
    '07000000-0000-4000-8000-000000000040',
    'VOCAB.CONTEXT',
    'VOCABULARY',
    'Vocabulario en contexto',
    'Reconoce el sentido de una expresión dentro de la canción.',
    1
);

INSERT INTO learning.exercise_definition (
    exercise_id,
    recording_id,
    line_id,
    exercise_type,
    competency_id,
    status_code,
    version
)
VALUES (
    '07000000-0000-4000-8000-000000000050',
    '07000000-0000-4000-8000-000000000002',
    '07000000-0000-4000-8000-000000000030',
    'FILL_BLANK_OPTIONS',
    '07000000-0000-4000-8000-000000000040',
    'DRAFT',
    1
);

INSERT INTO learning.exercise_revision (
    exercise_revision_id,
    exercise_id,
    revision_no,
    prompt,
    solution_spec,
    status_code,
    checksum,
    version
)
VALUES (
    '07000000-0000-4000-8000-000000000060',
    '07000000-0000-4000-8000-000000000050',
    2,
    'Completa la expresión que significa una y otra vez.',
    '{
       "schemaVersion": 1,
       "answerModel": "SINGLE_CHOICE",
       "acceptedItemOrders": [1],
       "explanation": "La expresión conserva el sentido contextual de repetición.",
       "feedback": {
         "correct": "Correcto: identificaste la expresión contextual.",
         "incorrect": "Revisa la línea y compara las opciones."
       },
       "difficulty": {
         "code": "BEGINNER",
         "justification": "Una línea y tres opciones diferenciadas."
       }
     }'::jsonb,
    'DRAFT',
    decode(repeat('71', 32), 'hex'),
    1
);

INSERT INTO learning.exercise_item (
    exercise_item_id,
    exercise_revision_id,
    item_type,
    item_order,
    prompt_fragment,
    expected_value,
    metadata
)
VALUES
(
    '07000000-0000-4000-8000-000000000061',
    '07000000-0000-4000-8000-000000000060',
    'OPTION',
    1,
    convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8'),
    to_jsonb(convert_from(decode('e4bd95e5baa6e381a7e38282', 'hex'), 'UTF8')),
    '{"role":"option"}'::jsonb
),
(
    '07000000-0000-4000-8000-000000000062',
    '07000000-0000-4000-8000-000000000060',
    'OPTION',
    2,
    convert_from(decode('e58fabe381b6', 'hex'), 'UTF8'),
    to_jsonb(convert_from(decode('e58fabe381b6', 'hex'), 'UTF8')),
    '{"role":"option"}'::jsonb
),
(
    '07000000-0000-4000-8000-000000000063',
    '07000000-0000-4000-8000-000000000060',
    'OPTION',
    3,
    convert_from(decode('e680aae78da3', 'hex'), 'UTF8'),
    to_jsonb(convert_from(decode('e680aae78da3', 'hex'), 'UTF8')),
    '{"role":"option"}'::jsonb
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
    '07000000-0000-4000-8000-000000000070',
    'EDITORIAL',
    'Ficha pedagógica BL070',
    'línea 1',
    CURRENT_TIMESTAMP,
    decode(repeat('72', 32), 'hex')
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
    '07000000-0000-4000-8000-000000000071',
    'EXERCISE_REVISION',
    '07000000-0000-4000-8000-000000000060',
    '07000000-0000-4000-8000-000000000070',
    'EXERCISE_SOURCE',
    '3a35b4fd-5e67-5686-9669-d5e78e20feaa'
);

DO $$
DECLARE
    exact_context boolean;
    revision_model boolean;
    options_ok boolean;
    provenance_ok boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM learning.exercise_definition AS definition
        INNER JOIN content.lyric_line AS line
            ON line.line_id = definition.line_id
        INNER JOIN content.lyric_section AS section
            ON section.section_id = line.section_id
        INNER JOIN content.lyrics_revision AS lyrics
            ON lyrics.lyrics_revision_id = section.lyrics_revision_id
        WHERE definition.exercise_id = '07000000-0000-4000-8000-000000000050'
          AND definition.recording_id = '07000000-0000-4000-8000-000000000002'
          AND definition.exercise_type = 'FILL_BLANK_OPTIONS'
          AND lyrics.lyrics_revision_id = '07000000-0000-4000-8000-000000000010'
          AND lyrics.revision_no = 3
    ) INTO exact_context;

    SELECT EXISTS (
        SELECT 1
        FROM learning.exercise_revision AS revision
        WHERE revision.exercise_revision_id = '07000000-0000-4000-8000-000000000060'
          AND revision.revision_no = 2
          AND revision.solution_spec ->> 'answerModel' = 'SINGLE_CHOICE'
          AND (revision.solution_spec ->> 'schemaVersion')::integer = 1
          AND revision.solution_spec #>> '{acceptedItemOrders,0}' = '1'
          AND length(revision.solution_spec ->> 'explanation') > 0
          AND revision.solution_spec #>> '{difficulty,code}' = 'BEGINNER'
          AND length(revision.solution_spec #>> '{difficulty,justification}') > 0
    ) INTO revision_model;

    SELECT
        count(*) = 3
        AND count(*) FILTER (WHERE item_order = 1) = 1
    FROM learning.exercise_item
    WHERE exercise_revision_id = '07000000-0000-4000-8000-000000000060'
      AND item_type = 'OPTION'
    INTO options_ok;

    SELECT EXISTS (
        SELECT 1
        FROM editorial.provenance_record AS provenance
        INNER JOIN catalog.source_reference AS source
            ON source.source_reference_id = provenance.source_reference_id
        WHERE provenance.object_type = 'EXERCISE_REVISION'
          AND provenance.object_id = '07000000-0000-4000-8000-000000000060'
          AND source.citation = 'Ficha pedagógica BL070'
    ) INTO provenance_ok;

    IF NOT exact_context THEN
        RAISE EXCEPTION 'BL070 no conserva contexto/revisión fuente exactos.';
    END IF;

    IF NOT revision_model THEN
        RAISE EXCEPTION 'BL070 no conserva solución, explicación o dificultad versionadas.';
    END IF;

    IF NOT options_ok THEN
        RAISE EXCEPTION 'BL070 no conserva opciones ordenadas.';
    END IF;

    IF NOT provenance_ok THEN
        RAISE EXCEPTION 'BL070 no conserva procedencia de revisión.';
    END IF;
END
$$;

ROLLBACK;
SQL

echo "bl=BL-MVP-070"
echo "ui=UI-MVP-025"
echo "exercise_identity=true"
echo "versioned_revision=true"
echo "exact_context=true"
echo "options=true"
echo "solution=true"
echo "explanation=true"
echo "editorial_difficulty=true"
echo "provenance=true"
echo "backoffice_learning_writes=false"
echo "bl071_authoring_deferred=true"
echo "external_linguistic_api=false"
echo "OK: BL-MVP-070 banco y revisiones de ejercicios modelados sin adelantar la autoría BL071."
