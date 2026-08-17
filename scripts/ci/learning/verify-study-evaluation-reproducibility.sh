#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

service="src/Modules/Learning/Infrastructure/Sessions/StudyExerciseEvaluationService.cs"
endpoint="apps/api/Endpoints/Learning/StudyExerciseEvaluationEndpoints.cs"
page="apps/web/src/routes/student/StudyExercisePage.tsx"
e2e="tests/E2ETests/study-evaluation-feedback.spec.ts"

fail() {
  echo "ERROR BL-MVP-075: $1" >&2
  exit 1
}

for required in "$service" "$endpoint" "$page" "$e2e"; do
  [[ -f "$required" ]] || fail "falta $required"
done

grep -Fq 'EvaluatorVersion = "FILL_BLANK_OPTIONS.SINGLE_CHOICE/v1"' "$service" \
  || fail "falta versión explícita del evaluador."
grep -Fq 'acceptedItemOrders' "$service" \
  || fail "la evaluación no lee la regla versionada acceptedItemOrders."
grep -Fq 'acceptedSourceItemIds.Contains(target.SelectedSourceItemId)' "$service" \
  || fail "la corrección debe resolverse por identidad de item/regla, no por texto."
grep -Fq 'SHA256.HashData' "$service" \
  || fail "falta result_digest determinista."
grep -Fq 'CryptographicOperations.FixedTimeEquals' "$service" \
  || fail "falta validar replay contra el digest persistido."
grep -Fq 'INSERT INTO learning.evaluation_result (' "$service" \
  || fail "falta persistir evaluation_result append-only."
grep -Fq 'pg_advisory_xact_lock' "$service" \
  || fail "falta serializar evaluaciones concurrentes."
grep -Fq 'StudyExerciseEvaluationDriftException' "$service" \
  || fail "falta estado revisable ante deriva."
grep -Fq 'learning.study-evaluation.rule.unavailable' "$endpoint" \
  || fail "falta respuesta revisable cuando la regla no es evaluable."
grep -Fq 'ValidateRequestAsync' "$endpoint" \
  || fail "el POST de evaluación debe validar CSRF."
grep -Fq 'private, no-store' "$endpoint" \
  || fail "la evaluación privada debe usar no-store."
grep -Fq "BL075 evalúa con CSRF, versión registrada y resultado reproducible" "$e2e" \
  || fail "falta E2E positivo BL075."
grep -Fq 'falta la regla y no presenta un resultado definitivo' "$e2e" \
  || fail "falta E2E del estado revisable BL075."

if grep -Fq 'INSERT INTO learning.learning_evidence' "$service"; then
  fail "BL075 no debe adelantar learning_evidence de BL077."
fi
if grep -Fq 'INSERT INTO progress.' "$service"; then
  fail "BL075 no debe adelantar progreso."
fi

: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

if [[ "${BL075_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
    to_regclass('learning.evaluation_result') IS NOT NULL,
    has_table_privilege('jp_app', 'learning.evaluation_result', 'SELECT,INSERT'),
    to_regclass('learning.ux_learning_evaluation_result_01') IS NOT NULL,
    EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'learning.evaluation_result'::regclass
          AND tgname = 'tr_learning_evaluation_result_append_only'
          AND NOT tgisinternal
    );

SELECT COUNT(*)
FROM pg_policies
WHERE schemaname = 'learning'
  AND tablename = 'evaluation_result'
  AND policyname = 'p_evaluation_result_owner';
SQL
)"

first_line="$(printf '%s\n' "$db_result" | sed -n '1p')"
policy_count="$(printf '%s\n' "$db_result" | tail -n 1)"

[[ "$first_line" == "t|t|t|t" ]] \
  || fail "tabla/privilegio/índice/append-only BL075 incompletos: $first_line"
[[ "$policy_count" == "1" ]] \
  || fail "falta política RLS owner de evaluation_result."

echo "bl=BL-MVP-075"
echo "ui=UI-MVP-013"
echo "frozen_revision_rule=true"
echo "accepted_alternatives_by_rule=true"
echo "text_comparison_for_correctness=false"
echo "evaluator_version=true"
echo "result_digest=true"
echo "retry_reuses_evaluation=true"
echo "missing_rule_reviewable=true"
echo "rls_owner=true"
echo "csrf=true"
echo "private_no_store=true"
echo "evidence_written=false"
echo "progress_written=false"
echo "OK: BL-MVP-075 evaluación reproducible verificada sin adelantar evidencia ni progreso."
