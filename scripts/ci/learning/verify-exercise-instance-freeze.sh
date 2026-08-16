#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

service="src/Modules/Learning/Infrastructure/Sessions/StudyExerciseFlowService.cs"
endpoint="apps/api/Endpoints/Learning/StudyExerciseEndpoints.cs"
page="apps/web/src/routes/student/StudyExercisePage.tsx"
start_page="apps/web/src/routes/student/StudyStartPage.tsx"
student_area="apps/web/src/routes/student/StudentArea.tsx"
e2e="tests/E2ETests/study-exercise-flow.spec.ts"

fail() {
  echo "ERROR BL-MVP-073: $1" >&2
  exit 1
}

for required in "$service" "$endpoint" "$page" "$start_page" "$student_area" "$e2e"; do
  [[ -f "$required" ]] || fail "falta $required"
done

grep -Fq 'IRlsTransactionExecutor' "$service" \
  || fail "la instancia privada no usa RLS/jp_app."
if grep -Fq 'BackofficeSecurityTransactionExecutor' "$service"; then
  fail "la instancia de estudiante no puede usar backoffice."
fi
grep -Fq 'INSERT INTO learning.exercise_instance (' "$service" \
  || fail "falta congelar exercise_instance."
grep -Fq 'INSERT INTO learning.exercise_instance_item (' "$service" \
  || fail "falta copiar elementos visibles de la instancia."
grep -Fq "'DELIVERED'" "$service" \
  || fail "falta estado entregado congelado."
grep -Fq 'RandomNumberGenerator.GetBytes' "$service" \
  || fail "falta semilla única para fijar el orden."
grep -Fq 'BuildOrderKey' "$service" \
  || fail "falta fijar el orden una sola vez."
grep -Fq 'ReadExistingInstanceIdAsync' "$service" \
  || fail "reabrir debe reutilizar la instancia existente."
grep -Fq 'published.component_checksum = component.checksum' "$service" \
  || fail "falta revalidar componente publicado exacto."
grep -Fq "definition.exercise_type = 'FILL_BLANK_OPTIONS'" "$service" \
  || fail "BL073 debe entregar completar espacios compatible."
if grep -Fq 'solution_spec' "$endpoint" || grep -Fq 'expected_value' "$endpoint"; then
  fail "el contrato estudiante no puede exponer solución."
fi
if grep -Fq 'solution_spec' "$page" || grep -Fq 'expected_value' "$page"; then
  fail "la UI estudiante no puede exponer solución."
fi
if grep -Fq 'INSERT INTO learning.evaluation_result' "$service"; then
  fail "BL073/074 no deben adelantar evaluación BL075."
fi
if grep -Fq 'INSERT INTO learning.learning_evidence' "$service"; then
  fail "BL073/074 no deben adelantar evidencia BL077."
fi
if grep -Fq 'INSERT INTO progress.' "$service"; then
  fail "BL073/074 no deben adelantar progreso."
fi

grep -Fq '/sessions/{studySessionId:guid}/instances' "$endpoint" \
  || fail "falta endpoint para preparar/reabrir instancia."
grep -Fq 'ValidateRequestAsync' "$endpoint" \
  || fail "crear la instancia no valida CSRF."
grep -Fq '"private, no-store"' "$endpoint" \
  || fail "el ejercicio privado no usa no-store."
grep -Fq 'data-route-id={routeId}' "$page" \
  || fail "falta UI-MVP-012/013 real."
grep -Fq "match.route.id === 'UI-MVP-012'" "$student_area" \
  || fail "UI-MVP-012 sigue siendo placeholder."
grep -Fq 'Continuar con el ejercicio' "$start_page" \
  || fail "UI-MVP-011 no continúa a BL073."
grep -Fq 'conserva exactamente revisión, contexto y orden' "$e2e" \
  || fail "falta prueba E2E de reapertura congelada."

node scripts/frontend/verify-design-tokens.mjs >/dev/null \
  || fail "los estilos BL073 violan tokens visuales."

: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

if [[ "${BL073_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
    to_regclass('learning.exercise_instance') IS NOT NULL,
    to_regclass('learning.exercise_instance_item') IS NOT NULL,
    has_table_privilege('jp_app', 'learning.exercise_instance', 'SELECT,INSERT,UPDATE'),
    has_table_privilege('jp_app', 'learning.exercise_instance_item', 'SELECT,INSERT,UPDATE'),
    to_regclass('learning.ux_learning_exercise_instance_01') IS NOT NULL,
    to_regclass('learning.ux_learning_exercise_instance_item_01') IS NOT NULL;

SELECT COUNT(*)
FROM pg_policies
WHERE schemaname = 'learning'
  AND (
      (tablename = 'exercise_instance' AND policyname = 'p_exercise_instance_owner')
      OR
      (tablename = 'exercise_instance_item' AND policyname = 'p_exercise_instance_item_owner')
  );
SQL
)"

first_line="$(printf '%s\n' "$db_result" | sed -n '1p')"
policy_count="$(printf '%s\n' "$db_result" | tail -n 1)"

[[ "$first_line" == "t|t|t|t|t|t" ]] \
  || fail "tablas/privilegios/índices BL073 incompletos: $first_line"
[[ "$policy_count" == "2" ]] \
  || fail "faltan políticas RLS owner de instancia."

echo "bl=BL-MVP-073"
echo "ui=UI-MVP-011,UI-MVP-012"
echo "frozen_revision=true"
echo "frozen_option_order=true"
echo "frozen_context=true"
echo "reopen_reuses_instance=true"
echo "student_solution_exposed=false"
echo "rls_owner=true"
echo "csrf=true"
echo "private_no_store=true"
echo "evaluation_written=false"
echo "evidence_written=false"
echo "progress_written=false"
echo "OK: BL-MVP-073 instancia congelada y reanudable verificada."
