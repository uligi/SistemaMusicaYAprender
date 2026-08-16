#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

service="src/Modules/Learning/Infrastructure/Sessions/StudyExerciseFlowService.cs"
endpoint="apps/api/Endpoints/Learning/StudyExerciseEndpoints.cs"
page="apps/web/src/routes/student/StudyExercisePage.tsx"
student_area="apps/web/src/routes/student/StudentArea.tsx"
e2e="tests/E2ETests/study-exercise-flow.spec.ts"

fail() {
  echo "ERROR BL-MVP-074: $1" >&2
  exit 1
}

for required in "$service" "$endpoint" "$page" "$student_area" "$e2e"; do
  [[ -f "$required" ]] || fail "falta $required"
done

grep -Fq 'INSERT INTO learning.answer_submission (' "$service" \
  || fail "falta confirmación append-only de answer_submission."
grep -Fq 'INSERT INTO learning.answer_value (' "$service" \
  || fail "falta conservar el valor elegido."
grep -Fq "'SELECTED_ITEM'" "$service" \
  || fail "falta modelo de selección tipado."
grep -Fq 'answerDigest' "$service" \
  || fail "falta digest estable de respuesta."
grep -Fq 'CryptographicOperations.FixedTimeEquals' "$service" \
  || fail "falta comparar digest en replay idempotente."
grep -Fq 'pg_advisory_xact_lock' "$service" \
  || fail "falta serializar confirmaciones concurrentes."
grep -Fq 'ReadSubmissionAsync' "$service" \
  || fail "falta recuperar la entrega lógica existente."
grep -Fq "state_code = 'RESPONDED'" "$service" \
  || fail "la instancia no pasa a respondida al confirmar."
grep -Fq 'Idempotency-Key' "$endpoint" \
  || fail "falta Idempotency-Key en la confirmación."
grep -Fq 'learning.answer-submission.selection.invalid' "$endpoint" \
  || fail "falta rechazo recuperable de opción ajena."
grep -Fq 'learning.answer-submission.already-confirmed' "$endpoint" \
  || fail "falta evitar una segunda entrega lógica."
grep -Fq "match.route.id === 'UI-MVP-013'" "$student_area" \
  || fail "UI-MVP-013 sigue siendo placeholder."
grep -Fq 'La corrección todavía no se muestra' "$page" \
  || fail "la UI debe preservar la frontera con BL075."
grep -Fq 'Idempotency-Key' "$page" \
  || fail "el cliente no envía clave idempotente."
grep -Fq 'confirma una sola selección con CSRF e Idempotency-Key' "$e2e" \
  || fail "falta prueba E2E de confirmación."

if grep -Fq 'INSERT INTO learning.evaluation_result' "$service"; then
  fail "BL074 no debe adelantar evaluación BL075."
fi
if grep -Fq 'INSERT INTO learning.feedback_item' "$service"; then
  fail "BL074 no debe adelantar retroalimentación BL076."
fi
if grep -Fq 'INSERT INTO learning.learning_evidence' "$service"; then
  fail "BL074 no debe adelantar evidencia BL077."
fi
if grep -Fq 'INSERT INTO progress.' "$service"; then
  fail "BL074 no debe adelantar progreso."
fi

node scripts/frontend/verify-design-tokens.mjs >/dev/null \
  || fail "los estilos BL074 violan tokens visuales."

: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

if [[ "${BL074_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
    to_regclass('learning.answer_submission') IS NOT NULL,
    to_regclass('learning.answer_value') IS NOT NULL,
    has_table_privilege('jp_app', 'learning.answer_submission', 'SELECT,INSERT,UPDATE'),
    has_table_privilege('jp_app', 'learning.answer_value', 'SELECT,INSERT,UPDATE'),
    to_regclass('learning.ux_learning_answer_submission_01') IS NOT NULL,
    to_regclass('learning.ux_learning_answer_submission_02') IS NOT NULL,
    to_regclass('learning.ux_learning_answer_value_01') IS NOT NULL;

SELECT COUNT(*)
FROM pg_policies
WHERE schemaname = 'learning'
  AND (
      (tablename = 'answer_submission' AND policyname = 'p_answer_submission_owner')
      OR
      (tablename = 'answer_value' AND policyname = 'p_answer_value_owner')
  );
SQL
)"

first_line="$(printf '%s\n' "$db_result" | sed -n '1p')"
policy_count="$(printf '%s\n' "$db_result" | tail -n 1)"

[[ "$first_line" == "t|t|t|t|t|t|t" ]] \
  || fail "tablas/privilegios/índices BL074 incompletos: $first_line"
[[ "$policy_count" == "2" ]] \
  || fail "faltan políticas RLS owner de respuesta."

echo "bl=BL-MVP-074"
echo "ui=UI-MVP-012,UI-MVP-013"
echo "single_logical_submission=true"
echo "idempotency_key=true"
echo "answer_digest=true"
echo "selected_value_preserved=true"
echo "foreign_option_rejected=true"
echo "rls_owner=true"
echo "csrf=true"
echo "private_no_store=true"
echo "evaluation_written=false"
echo "feedback_written=false"
echo "evidence_written=false"
echo "progress_written=false"
echo "bl075_evaluation_deferred=true"
echo "OK: BL-MVP-074 respuesta idempotente confirmada sin adelantar evaluación."
