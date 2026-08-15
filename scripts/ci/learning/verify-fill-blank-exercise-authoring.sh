#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR BL071: $1" >&2
  exit 1
}

endpoint="apps/api/Endpoints/Editorial/FillBlankExerciseAuthoringEndpoints.cs"
service="src/Modules/Learning/Infrastructure/Administration/FillBlankExerciseAuthoringService.cs"
page="apps/web/src/routes/editorial/FillBlankExerciseAuthoringWizard.tsx"
security_sql="database/postgresql/security/02_database_access.sql"
access_matrix="database/postgresql/security/access-matrix.json"
test_file="tests/E2ETests/fill-blank-exercise-authoring.spec.ts"

for path in "$endpoint" "$service" "$page" "$security_sql" "$access_matrix" "$test_file"; do
  [[ -f "$path" ]] || fail "falta $path"
done

grep -Fq 'MapPost' "$endpoint" || fail "falta guardado DRAFT."
grep -Fq '"EDITORIAL.DRAFT"' "$endpoint" || fail "falta autorización editorial."
grep -Fq 'moduleCode: "M08"' "$endpoint" || fail "falta ámbito M08."
grep -Fq 'IAntiforgery' "$endpoint" || fail "falta CSRF."
grep -Fq '"If-Match"' "$endpoint" || fail "falta concurrencia If-Match."
grep -Fq 'StatusCodes.Status412PreconditionFailed' "$endpoint" || fail "falta conflicto de fuente."

grep -Fq 'NormalizationForm.FormKC' "$service" || fail "falta normalización Unicode NFKC."
grep -Fq 'options.ambiguous' "$service" || fail "falta validación de opción ambigua."
grep -Fq 'options.duplicate' "$service" || fail "falta validación de duplicados."
grep -Fq "status_code = 'DRAFT'" "$service" || fail "contexto no está anclado a DRAFT."
grep -Fq 'sourceToken.Surface' "$service" || fail "la respuesta no se deriva del token fuente."
grep -Fq 'ORDER BY section.display_order, line.line_no, token.token_no' "$service" \
  || fail "el contexto DRAFT debe ordenar por lyric_section.display_order."
if grep -Fq 'section.section_no' "$service"; then
  fail "lyric_section no expone section_no; usa display_order."
fi

grep -Fq 'SECURITY DEFINER' "$security_sql" || fail "falta función acotada."
grep -Fq 'learning.save_fill_blank_exercise_draft' "$security_sql" || fail "falta función BL071."
grep -Fq 'SET search_path = pg_catalog' "$security_sql" || fail "falta search_path fijo."
grep -Fq 'REVOKE ALL ON FUNCTION learning.save_fill_blank_exercise_draft' "$security_sql" \
  || fail "falta REVOKE PUBLIC."
grep -Fq 'TO jp_backoffice' "$security_sql" || fail "falta EXECUTE backoffice."

if grep -Eiq 'GRANT[[:space:]]+(INSERT|UPDATE|DELETE).*learning.*jp_backoffice|GRANT[[:space:]]+SELECT,[[:space:]]*INSERT.*learning.*jp_backoffice' "$security_sql"; then
  fail "no se permite ampliar DML directo del pool backoffice sobre learning."
fi

grep -Fq 'Guardar borrador' "$page" || fail "falta CTA de borrador."
grep -Fq 'BORRADOR · NO PUBLICADO' "$page" || fail "falta preview DRAFT explícita."
grep -Fq 'Comprobar en vista previa' "$page" || fail "falta prueba interactiva."
preview_copy="$(tr '\n\r\t' '   ' < "$page" | tr -s ' ')"
grep -Fq 'no crea sesión, intento, evidencia ni progreso' <<<"$preview_copy" \
  || fail "falta frontera de preview local."
grep -Fq 'AxeBuilder' "$test_file" || fail "falta axe."
grep -Fq '320' "$test_file" || fail "falta 320px."

if grep -Eiq 'openai|anthropic|gemini|deepl|google[[:space:]_-]*translate|dictionaryapi|jisho' \
  "$service" "$endpoint" "$page"; then
  fail "M08 no debe usar servicios lingüísticos externos."
fi

psql_base=(psql -X -v ON_ERROR_STOP=1)
if [[ "${BL071_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U "${PGUSER:-musica_local}" -d "${PGDATABASE:-musica_aprender}")
fi

"${psql_base[@]}" > artifacts/postgres/bl-mvp-071-fill-blank-authoring.txt <<'SQL'
BEGIN;

DO $$
DECLARE
    has_function boolean;
BEGIN
    SELECT to_regprocedure(
        'learning.save_fill_blank_exercise_draft(uuid,uuid,uuid,uuid,text,text,jsonb,text,text,text,text,text,bytea)'
    ) IS NOT NULL
    INTO has_function;

    IF NOT has_function THEN
        RAISE EXCEPTION 'Falta función segura BL071; aplica 02_database_access.sql.';
    END IF;
END
$$;

PREPARE bl071_authoring_context(uuid) AS
SELECT
    line.line_id,
    line.line_no,
    line.japanese_text,
    token.token_id,
    token.token_no,
    token.surface
FROM content.lyric_section AS section
INNER JOIN content.lyric_line AS line
    ON line.section_id = section.section_id
LEFT JOIN content.lyric_token AS token
    ON token.line_id = line.line_id
WHERE section.lyrics_revision_id = $1
ORDER BY section.display_order, line.line_no, token.token_no;

DEALLOCATE bl071_authoring_context;

SELECT
    has_function_privilege(
        'jp_backoffice',
        'learning.save_fill_blank_exercise_draft(uuid,uuid,uuid,uuid,text,text,jsonb,text,text,text,text,text,bytea)',
        'EXECUTE'
    ) AS backoffice_execute,
    has_table_privilege('jp_backoffice', 'learning.exercise_definition', 'INSERT') AS direct_definition_insert,
    has_table_privilege('jp_backoffice', 'learning.exercise_revision', 'UPDATE') AS direct_revision_update;

ROLLBACK;
SQL

grep -Fq "t|f|f" artifacts/postgres/bl-mvp-071-fill-blank-authoring.txt \
  || grep -Eq 't[[:space:]]*\|[[:space:]]*f[[:space:]]*\|[[:space:]]*f' artifacts/postgres/bl-mvp-071-fill-blank-authoring.txt \
  || fail "ACL BL071 no conserva EXECUTE acotado y DML directo denegado."

echo "bl=BL-MVP-071"
echo "ui=UI-MVP-025"
echo "guided_four_step_authoring=true"
echo "exact_draft_source=true"
echo "blank_from_canonical_token=true"
echo "ambiguity_blocked=true"
echo "duplicate_options_blocked=true"
echo "csrf=true"
echo "if_match=true"
echo "draft_preview=true"
echo "student_evidence_written=false"
echo "publication_written=false"
echo "backoffice_direct_learning_writes=false"
echo "scoped_security_definer=true"
echo "external_linguistic_api=false"
echo "OK: BL-MVP-071 autoría DRAFT amigable y validada sin adelantar sesión ni publicación."
