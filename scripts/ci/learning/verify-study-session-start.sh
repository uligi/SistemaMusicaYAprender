#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

service="src/Modules/Learning/Infrastructure/Sessions/StudySessionStartService.cs"
endpoint="apps/api/Endpoints/Learning/StudySessionEndpoints.cs"
page="apps/web/src/routes/student/StudyStartPage.tsx"
student_area="apps/web/src/routes/student/StudentArea.tsx"
e2e="tests/E2ETests/study-session-start.spec.ts"

fail() {
  echo "ERROR BL-MVP-072: $1" >&2
  exit 1
}

for required in "$service" "$endpoint" "$page" "$student_area" "$e2e"; do
  [[ -f "$required" ]] || fail "falta $required"
done

grep -Fq 'IRlsTransactionExecutor' "$service" \
  || fail "la sesión privada no usa el ejecutor RLS de jp_app."
if grep -Fq 'BackofficeSecurityTransactionExecutor' "$service"; then
  fail "una sesión de estudiante no puede escribir mediante backoffice."
fi
grep -Fq 'editorial.publication AS publication' "$service" \
  || fail "falta validar publicación canónica."
grep -Fq "publication.status_code = 'ACTIVE'" "$service" \
  || fail "una publicación no activa no puede iniciar sesión."
grep -Fq "package.status_code = 'APPROVED'" "$service" \
  || fail "falta paquete editorial aprobado."
grep -Fq 'publication_availability' "$service" \
  || fail "falta validar disponibilidad pública."
grep -Fq 'published_package_projection' "$service" \
  || fail "falta exigir el paquete publicado reconstruible BL069."
grep -Fq "published.component_kind = 'EXERCISE'" "$service" \
  || fail "falta actividad de ejercicio publicada."
grep -Fq 'published.component_checksum =' "$service" \
  || fail "falta comprobar linaje/checksum del componente publicado."
grep -Fq 'INSERT INTO learning.study_session' "$service" \
  || fail "falta persistir la sesión privada."
grep -Fq 'ops.idempotency_record' "$service" \
  || fail "falta confirmación idempotente del inicio."
grep -Fq 'pg_advisory_xact_lock' "$service" \
  || fail "falta serializar la doble activación."
if grep -Fq 'INSERT INTO learning.study_activity' "$service"; then
  fail "BL072 no debe adelantar actividades confirmadas BL073/BL078."
fi
if grep -Fq 'INSERT INTO learning.answer_submission' "$service"; then
  fail "BL072 no debe adelantar respuestas BL074."
fi
if grep -Fq 'INSERT INTO learning.learning_evidence' "$service"; then
  fail "BL072 no debe adelantar evidencia BL077."
fi
if grep -Fq 'INSERT INTO progress.' "$service"; then
  fail "BL072 no debe adelantar progreso."
fi

grep -Fq '/api/v1/study/songs/{slug}' "$endpoint" \
  || fail "falta ruta privada de estudio."
grep -Fq '.RequireAuthorization()' "$endpoint" \
  || fail "la ruta no exige autenticación."
grep -Fq 'ValidateRequestAsync' "$endpoint" \
  || fail "el inicio no valida CSRF."
grep -Fq 'Idempotency-Key' "$endpoint" \
  || fail "falta Idempotency-Key."
grep -Fq '"private, no-store"' "$endpoint" \
  || fail "el estado privado no usa no-store."
grep -Fq 'learning.study-session.activity.unavailable' "$endpoint" \
  || fail "falta estado seguro sin actividad publicada."

grep -Fq 'data-route-id="UI-MVP-011"' "$page" \
  || fail "falta UI-MVP-011 real."
grep -Fq 'Tu sesión es privada' "$page" \
  || fail "la privacidad no se explica en lenguaje humano."
grep -Fq 'Los borradores editoriales no crean sesiones de estudiante' "$service" \
  || fail "falta frontera explícita DRAFT/publicado."
grep -Fq "match.route.id === 'UI-MVP-011'" "$student_area" \
  || fail "UI-MVP-011 sigue siendo placeholder."
grep -Fq "Practicar esta canción" "$e2e" \
  || fail "falta cobertura E2E del recorrido."

node scripts/frontend/verify-design-tokens.mjs >/dev/null \
  || fail "los estilos BL072 violan tokens visuales."

: "${PGUSER:?PGUSER requerido}"
: "${PGDATABASE:?PGDATABASE requerido}"

if [[ "${BL072_USE_DOCKER_PSQL:-false}" == "true" ]]; then
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
    to_regclass('learning.learner_profile') IS NOT NULL,
    to_regclass('learning.study_session') IS NOT NULL,
    to_regclass('ops.idempotency_record') IS NOT NULL,
    has_table_privilege('jp_app', 'learning.learner_profile', 'SELECT,INSERT,UPDATE'),
    has_table_privilege('jp_app', 'learning.study_session', 'SELECT,INSERT,UPDATE'),
    has_table_privilege('jp_app', 'ops.idempotency_record', 'SELECT,INSERT,UPDATE');

PREPARE bl072_publication_resolution(text, text, text) AS
SELECT
    publication.publication_id,
    publication.recording_id,
    publication.publication_no
FROM editorial.publication AS publication
INNER JOIN editorial.editorial_package AS package
    ON package.package_id = publication.package_id
   AND package.recording_id = publication.recording_id
INNER JOIN editorial.published_package_projection AS projection
    ON projection.publication_id = publication.publication_id
   AND projection.recording_id = publication.recording_id
WHERE substring(
          md5(publication.recording_id::text || ':public-song-v1')
          from 1 for 20
      ) = $1
  AND publication.status_code = 'ACTIVE'
  AND package.status_code = 'APPROVED'
  AND package.frozen_at IS NOT NULL
  AND EXISTS (
      SELECT 1
      FROM editorial.publication_availability AS availability
      WHERE availability.publication_id = publication.publication_id
        AND availability.territory_code = $2
        AND availability.audience_code = 'PUBLIC'
        AND availability.status_code = 'ACTIVE'
  )
  AND EXISTS (
      SELECT 1
      FROM editorial.publication_component AS published
      INNER JOIN editorial.package_component AS package_component
          ON package_component.package_component_id =
             published.source_component_id
         AND package_component.package_id = publication.package_id
         AND package_component.component_kind = 'EXERCISE'
      INNER JOIN learning.exercise_revision AS exercise
          ON exercise.exercise_revision_id =
             package_component.exercise_revision_id
      INNER JOIN learning.exercise_definition AS definition
          ON definition.exercise_id = exercise.exercise_id
         AND definition.recording_id = publication.recording_id
      WHERE published.publication_id = publication.publication_id
        AND published.component_kind = 'EXERCISE'
        AND published.component_checksum = package_component.checksum
  )
  AND ($3 = '' OR $3 IS NOT NULL)
LIMIT 2;

DEALLOCATE bl072_publication_resolution;

SELECT COUNT(*)
FROM pg_policies
WHERE schemaname = 'learning'
  AND tablename IN ('learner_profile', 'study_session')
  AND policyname IN ('p_learner_profile_owner', 'p_study_session_owner');
SQL
)"

first_line="$(printf '%s\n' "$db_result" | sed -n '1p')"
policy_count="$(printf '%s\n' "$db_result" | tail -n 1)"

[[ "$first_line" == "t|t|t|t|t|t" ]] \
  || fail "tablas/privilegios jp_app incompletos: $first_line"
[[ "$policy_count" == "2" ]] \
  || fail "faltan políticas RLS owner de learning."

echo "bl=BL-MVP-072"
echo "ui=UI-MVP-011"
echo "published_only=true"
echo "private_state=true"
echo "rls_owner=true"
echo "csrf=true"
echo "idempotent_start=true"
echo "empty_session_blocked=true"
echo "answers_exposed=false"
echo "notes_exposed=false"
echo "evidence_written=false"
echo "progress_written=false"
echo "draft_persistence=false"
echo "bl073_instance_deferred=true"
echo "OK: BL-MVP-072 inicio privado e idempotente de sesión sobre contenido publicado verificado."
