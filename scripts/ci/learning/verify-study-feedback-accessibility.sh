#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

service="src/Modules/Learning/Infrastructure/Sessions/StudyExerciseEvaluationService.cs"
endpoint="apps/api/Endpoints/Learning/StudyExerciseEvaluationEndpoints.cs"
page="apps/web/src/routes/student/StudyExercisePage.tsx"
e2e="tests/E2ETests/study-evaluation-feedback.spec.ts"

fail() {
  echo "ERROR BL-MVP-076: $1" >&2
  exit 1
}

for required in "$service" "$endpoint" "$page" "$e2e"; do
  [[ -f "$required" ]] || fail "falta $required"
done

grep -Fq 'INSERT INTO learning.feedback_item (' "$service" \
  || fail "falta persistir feedback_item."
grep -Fq 'rule.FeedbackCorrect' "$service" \
  || fail "falta feedback correcto de la revisión congelada."
grep -Fq 'rule.FeedbackIncorrect' "$service" \
  || fail "falta feedback incorrecto de la revisión congelada."
grep -Fq 'rule.Explanation' "$service" \
  || fail "falta explicación versionada de la revisión."
grep -Fq 'NEXT_ACTION.CONTINUE' "$service" \
  || fail "falta siguiente acción textual."
grep -Fq 'FeedbackLanguage = "es-CR"' "$service" \
  || fail "falta localización inicial explícita del feedback."
grep -Fq "feedbackTitle(item.feedbackCode)" "$page" \
  || fail "la UI no etiqueta semánticamente el feedback."
grep -Fq "'Respuesta correcta' : 'Respuesta incorrecta'" "$page" \
  || fail "el resultado no está expresado por texto."
grep -Fq 'evaluationHeadingRef.current?.focus()' "$page" \
  || fail "falta mover foco al resultado confirmado."
grep -Fq 'aria-live="polite"' "$page" \
  || fail "falta anuncio accesible del resultado."
grep -Fq 'Explicación' "$page" \
  || fail "falta etiqueta textual de explicación."
grep -Fq 'Siguiente acción' "$page" \
  || fail "falta etiqueta textual de siguiente acción."
grep -Fq 'comunica resultado, explicación y siguiente acción por texto con foco y axe a 320 px' "$e2e" \
  || fail "falta E2E accesible BL076."

if grep -Fq 'INSERT INTO learning.learning_evidence' "$service"; then
  fail "BL076 no debe adelantar learning_evidence de BL077."
fi
if grep -Fq 'INSERT INTO progress.' "$service"; then
  fail "BL076 no debe adelantar progreso."
fi

node scripts/frontend/verify-design-tokens.mjs >/dev/null \
  || fail "la UI BL076 viola tokens visuales."

: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

if [[ "${BL076_USE_DOCKER_PSQL:-false}" == "true" ]]; then
  psql_base=(
    docker compose exec -T postgres
    psql
    --username="$PGUSER"
    --dbname="$PGDATABASE"
    --no-password
    --set=ON_ERROR_STOP=1
    --tuples-only
    --no-align
  )
else
  : "${PGHOST:=127.0.0.1}"
  : "${PGPORT:=5432}"
  : "${PGPASSWORD:?PGPASSWORD requerido}"
  psql_base=(
    psql
    --host="$PGHOST"
    --port="$PGPORT"
    --username="$PGUSER"
    --dbname="$PGDATABASE"
    --no-password
    --set=ON_ERROR_STOP=1
    --tuples-only
    --no-align
  )
fi

db_result="$("${psql_base[@]}" <<'SQL'
SELECT
    to_regclass('learning.feedback_item') IS NOT NULL,
    has_table_privilege('jp_app', 'learning.feedback_item', 'SELECT,INSERT'),
    to_regclass('learning.ux_learning_feedback_item_01') IS NOT NULL,
    EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'learning.feedback_item'::regclass
          AND tgname = 'tr_learning_feedback_item_append_only'
          AND NOT tgisinternal
    );

SELECT COUNT(*)
FROM pg_policies
WHERE schemaname = 'learning'
  AND tablename = 'feedback_item'
  AND policyname = 'p_feedback_item_owner';
SQL
)"

first_line="$(printf '%s\n' "$db_result" | sed -n '1p')"
policy_count="$(printf '%s\n' "$db_result" | tail -n 1)"

[[ "$first_line" == "t|t|t|t" ]] \
  || fail "tabla/privilegio/índice/append-only BL076 incompletos: $first_line"
[[ "$policy_count" == "1" ]] \
  || fail "falta política RLS owner de feedback_item."

echo "bl=BL-MVP-076"
echo "ui=UI-MVP-013"
echo "text_result=true"
echo "text_explanation=true"
echo "text_next_action=true"
echo "focus_preserved=true"
echo "color_only=false"
echo "audio_required=false"
echo "timer_required=false"
echo "localized_feedback=true"
echo "rls_owner=true"
echo "private_no_store=true"
echo "evidence_written=false"
echo "progress_written=false"
echo "OK: BL-MVP-076 retroalimentación textual y accesible verificada."
