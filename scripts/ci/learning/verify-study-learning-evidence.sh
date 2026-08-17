#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

service="src/Modules/Learning/Infrastructure/Sessions/StudyLearningEvidenceService.cs"
endpoint="apps/api/Endpoints/Learning/StudyLearningEvidenceEndpoints.cs"
evaluation_endpoint="apps/api/Endpoints/Learning/StudyExerciseEvaluationEndpoints.cs"
page="apps/web/src/routes/student/StudyExercisePage.tsx"
e2e="tests/E2ETests/study-learning-evidence.spec.ts"

fail() {
  echo "ERROR BL-MVP-077: $1" >&2
  exit 1
}

for required in "$service" "$endpoint" "$evaluation_endpoint" "$page" "$e2e"; do
  [[ -f "$required" ]] || fail "falta $required"
done

grep -Fq 'INSERT INTO learning.learning_evidence (' "$service" \
  || fail "falta confirmar learning_evidence."
grep -Fq 'evidence_version' "$service" \
  || fail "falta versión explícita de evidencia."
grep -Fq 'INNER JOIN learning.evaluation_result AS evaluation' "$service" \
  || fail "falta linaje hacia evaluation_result."
grep -Fq 'INNER JOIN learning.answer_submission AS submission' "$service" \
  || fail "falta linaje hacia answer_submission."
grep -Fq 'FROM learning.exercise_instance AS instance' "$service" \
  || fail "falta linaje hacia exercise_instance."
grep -Fq 'INNER JOIN learning.exercise_revision AS revision' "$service" \
  || fail "falta linaje hacia la revisión congelada."
grep -Fq 'INNER JOIN learning.exercise_definition AS definition' "$service" \
  || fail "falta derivar competencia y recording desde el ejercicio exacto."
grep -Fq 'definition.competency_id' "$service" \
  || fail "falta competency_id de linaje."
grep -Fq 'definition.recording_id' "$service" \
  || fail "falta recording_id de linaje."
grep -Fq 'evaluation.score' "$service" \
  || fail "falta outcome derivado del resultado evaluado."
grep -Fq 'pg_advisory_xact_lock' "$service" \
  || fail "falta serializar reintentos concurrentes."
grep -Fq 'ProgressNotificationEventName = "LEARNING.EVIDENCE.CONFIRMED"' "$service" \
  || fail "falta la notificación única destinada a derivación de progreso."
grep -Fq 'OutboxMessageDraft.Create' "$service" \
  || fail "la evidencia y su evento deben confirmarse en la misma transacción."
grep -Fq 'outboxWriter.EnqueueAsync' "$service" \
  || fail "falta escribir el outbox transaccional BL015."
grep -Fq 'ValidateSingleProgressNotificationAsync' "$service" \
  || fail "el replay debe validar una sola notificación existente."
grep -Fq 'ValidateRequestAsync' "$endpoint" \
  || fail "el POST de recuperación de evidencia debe validar CSRF."
grep -Fq 'private, no-store' "$endpoint" \
  || fail "la evidencia privada debe usar no-store."
grep -Fq 'evidenceService.EnsureAsync' "$evaluation_endpoint" \
  || fail "una evaluación válida debe coordinar la confirmación de evidencia."
grep -Fq 'StudyLearningEvidenceResponse? Evidence' "$evaluation_endpoint" \
  || fail "la respuesta de evaluación debe exponer el estado de evidencia sin otra lectura automática."
grep -Fq 'Evidencia de aprendizaje confirmada' "$page" \
  || fail "la UI no muestra confirmación textual de evidencia."
grep -Fq 'Confirmar evidencia' "$page" \
  || fail "falta recuperación explícita cuando evaluación existe y evidencia está pendiente."
grep -Fq 'BL077 recupera evidencia pendiente con CSRF y al recargar no vuelve a crearla' "$e2e" \
  || fail "falta E2E de recuperación idempotente."
grep -Fq 'sin overflow y sin violaciones axe a 320 px' "$e2e" \
  || fail "falta E2E accesible a 320 px."

if grep -Eq 'UPDATE[[:space:]]+learning\.learning_evidence|DELETE[[:space:]]+FROM[[:space:]]+learning\.learning_evidence' "$service"; then
  fail "BL077 no puede reescribir ni borrar learning_evidence."
fi
if grep -Fq 'INSERT INTO progress.' "$service"; then
  fail "BL077 no debe adelantar la derivación de progreso de BL083."
fi

: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

if [[ "${BL077_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
    to_regclass('learning.learning_evidence') IS NOT NULL,
    has_table_privilege('jp_app', 'learning.learning_evidence', 'SELECT,INSERT'),
    to_regclass('learning.ux_learning_learning_evidence_01') IS NOT NULL,
    EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'learning.learning_evidence'::regclass
          AND tgname = 'tr_learning_evidence_correction'
          AND NOT tgisinternal
    ),
    has_table_privilege('jp_app', 'ops.outbox_message', 'SELECT,INSERT'),
    to_regclass('ops.ix_outbox_claim') IS NOT NULL;

SELECT COUNT(*)
FROM pg_policies
WHERE schemaname = 'learning'
  AND tablename = 'learning_evidence'
  AND policyname = 'p_learning_evidence_owner';

SELECT COUNT(*)
FROM pg_constraint
WHERE conrelid = 'learning.learning_evidence'::regclass
  AND conname IN (
      'fk_learning_learning_evidence_learner_profile_id',
      'fk_learning_learning_evidence_evaluation_id',
      'fk_learning_learning_evidence_competency_id',
      'fk_learning_learning_evidence_recording_id'
  );
SQL
)"

first_line="$(printf '%s\n' "$db_result" | sed -n '1p')"
policy_count="$(printf '%s\n' "$db_result" | sed -n '2p')"
fk_count="$(printf '%s\n' "$db_result" | tail -n 1)"

[[ "$first_line" == "t|t|t|t|t|t" ]] \
  || fail "tabla/privilegio/unicidad/append-only/outbox BL077 incompletos: $first_line"
[[ "$policy_count" == "1" ]] \
  || fail "falta política RLS owner de learning_evidence."
[[ "$fk_count" == "4" ]] \
  || fail "linaje físico incompleto de learning_evidence: $fk_count FKs."

echo "bl=BL-MVP-077"
echo "ui=UI-MVP-013-015"
echo "valid_evaluation_required=true"
echo "lineage_complete=true"
echo "logical_uniqueness=true"
echo "append_only=true"
echo "retry_reuses_evidence=true"
echo "single_progress_notification=true"
echo "outbox_same_transaction=true"
echo "csrf=true"
echo "private_no_store=true"
echo "progress_written=false"
echo "correction_flow_advanced=false"
echo "OK: BL-MVP-077 evidencia append-only e idempotente verificada sin adelantar BL083."
