#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

component="apps/web/src/routes/student/StudySessionJourney.tsx"
start="apps/web/src/routes/student/StudyStartPage.tsx"
exercise="apps/web/src/routes/student/StudyExercisePage.tsx"
lifecycle_service="src/Modules/Learning/Infrastructure/Sessions/StudySessionLifecycleService.cs"
session_endpoints="apps/api/Endpoints/Learning/StudySessionEndpoints.cs"
flow_service="src/Modules/Learning/Infrastructure/Sessions/StudyExerciseFlowService.cs"
evaluation_service="src/Modules/Learning/Infrastructure/Sessions/StudyExerciseEvaluationService.cs"
evidence_service="src/Modules/Learning/Infrastructure/Sessions/StudyLearningEvidenceService.cs"
e2e="tests/E2ETests/study-session-experience.spec.ts"
workflow=".github/workflows/ci.yml"

fail() {
  echo "ERROR BL-MVP-078: $*" >&2
  exit 1
}

for file in "$component" "$start" "$exercise" "$lifecycle_service" "$session_endpoints" "$flow_service" "$evaluation_service" "$evidence_service" "$e2e" "$workflow"; do
  [[ -f "$file" ]] || fail "falta $file"
done

for label in Pendiente Guardado Confirmado; do
  grep -Fq "$label" "$component" || fail "falta estado educativo textual $label"
done

grep -Fq 'public sealed class StudySessionLifecycleService' "$lifecycle_service" \
  || fail "falta servicio autoritativo de ciclo de vida"
for action in PauseAsync ResumeAsync CompleteAsync; do
  grep -Fq "$action" "$lifecycle_service" || fail "falta transición $action"
done
grep -Fq 'status_code = @target_status' "$lifecycle_service" \
  || fail "el ciclo de vida no persiste status_code"
grep -Fq 'ended_at = CASE' "$lifecycle_service" \
  || fail "finalizar no persiste ended_at"
grep -Fq 'session.version = @expected_version' "$lifecycle_service" \
  || fail "falta concurrencia optimista por versión"
grep -Fq 'FOR UPDATE OF session' "$lifecycle_service" \
  || fail "lifecycle no serializa la fila study_session"

grep -Fq '/{studySessionId:guid}/pause' "$session_endpoints" || fail "falta endpoint pause"
grep -Fq '/{studySessionId:guid}/resume' "$session_endpoints" || fail "falta endpoint resume"
grep -Fq '/{studySessionId:guid}/complete' "$session_endpoints" || fail "falta endpoint complete"
grep -Fq 'If-Match' "$session_endpoints" || fail "falta precondición If-Match"
grep -Fq 'StatusCodes.Status412PreconditionFailed' "$session_endpoints" \
  || fail "falta 412 para versión obsoleta"

grep -Fq 'session.StatusCode' "$flow_service" || fail "falta lectura del estado de sesión al preparar"
grep -A4 -F 'session.StatusCode' "$flow_service" | grep -Fq '"ACTIVE"' \
  || fail "preparar una instancia nueva no exige sesión ACTIVE"
grep -Fq 'FOR UPDATE OF session' "$flow_service" \
  || fail "prepare/submission no serializan la fila study_session"
if grep -A8 -F 'public bool IsOpen =>' "$flow_service" | grep -Fq 'PAUSED'; then
  fail "una sesión PAUSED todavía aparece abierta para submission nueva"
fi

grep -Fq 'SessionAcceptsNewEducationalMutationAsync' "$evaluation_service" \
  || fail "evaluación nueva no está bloqueada por lifecycle"
grep -Fq 'FOR UPDATE OF session' "$evaluation_service" \
  || fail "evaluación no serializa la comprobación ACTIVE"
grep -Fq 'SessionAcceptsNewEducationalMutationAsync' "$evidence_service" \
  || fail "evidencia nueva no está bloqueada por lifecycle"
grep -Fq 'FOR UPDATE OF session' "$evidence_service" \
  || fail "evidencia no serializa la comprobación ACTIVE"

grep -Fq 'Continuar sesión' "$start" || fail "UI-MVP-011 no ofrece reanudación explícita"
grep -Fq 'Salir y continuar después' "$exercise" || fail "falta pausa/salida explícita"
grep -Fq 'Finalizar sesión' "$exercise" || fail "falta finalización accesible"
grep -Fq 'Sesión finalizada' "$exercise" || fail "falta resumen coherente al finalizar"
grep -Fq "statusCode !== 'ACTIVE'" "$exercise" \
  || fail "UI no bloquea mutaciones nuevas cuando la sesión no está ACTIVE"

if grep -Eq 'localStorage|sessionStorage' "$component" "$start" "$exercise"; then
  fail "la continuidad no puede depender de almacenamiento cliente"
fi
if grep -Eq '/progress|progress\.' "$component" "$start" "$exercise" "$lifecycle_service"; then
  fail "BL078 no puede escribir ni consultar progreso"
fi

grep -Fq 'Pendiente → Guardado → Confirmado' "$e2e" || fail "falta E2E del recorrido completo"
grep -Fq 'CA-MVP-053' "$e2e" || fail "falta E2E específico de pausa/continuación/finalización"
grep -Fq "keyboard.press('Enter')" "$e2e" || fail "CA-MVP-053 no prueba operación por teclado"
grep -Fq 'No hay un temporizador obligatorio' "$e2e" || fail "falta aserción de ausencia de temporizador obligatorio"
grep -Fq 'AxeBuilder' "$e2e" || fail "falta cobertura Axe"
grep -Fq 'innerWidth' "$e2e" || fail "falta cobertura móvil 320px"

grep -Fq 'bash scripts/ci/learning/verify-complete-study-session-experience.sh' "$workflow" \
  || fail "CI no ejecuta el verifier BL078"

echo "OK: BL-MVP-078 experiencia completa de sesión verificada (V3)."
echo "lifecycle=ACTIVE>PAUSED>ACTIVE>COMPLETED"
echo "concurrency=If-Match+version"
echo "journey=start>exercise>result"
echo "states=pending,saved,confirmed"
echo "paused-new-educational-writes=false"
echo "progress-written=false"
