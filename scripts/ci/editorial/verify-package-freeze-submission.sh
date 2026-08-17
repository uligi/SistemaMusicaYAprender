#!/usr/bin/env bash
set -euo pipefail

service="src/Modules/Editorial/Infrastructure/Administration/EducationalPackageSubmissionService.cs"
assembly_service="src/Modules/Editorial/Infrastructure/Administration/CompatibleEducationalPackageService.cs"
endpoints="apps/api/Endpoints/Editorial/CompatibleEducationalPackageEndpoints.cs"
page="apps/web/src/routes/editorial/CompatiblePackagePage.tsx"
page_css="apps/web/src/routes/editorial/compatible-package.css"
navigation="apps/web/src/routes/editorial/SongContextNavigation.tsx"
area="apps/web/src/routes/editorial/EditorialArea.tsx"
schema="database/postgresql/migrations/sql/01_initial_schema.sql"
e2e="tests/E2ETests/package-freeze-submission.spec.ts"

for path in \
  "$service" \
  "$assembly_service" \
  "$endpoints" \
  "$page" \
  "$page_css" \
  "$navigation" \
  "$area" \
  "$schema" \
  "$e2e"; do
  test -f "$path"
done

grep -Fq "ChecklistVersion = \"BL-MVP-048.v1\"" "$service"
grep -Fq "status_code = 'SUBMITTED'" "$service"
grep -Fq "frozen_at = CURRENT_TIMESTAMP" "$service"
grep -Fq "INSERT INTO editorial.review_submission" "$service"
grep -Fq "ValidateDraftForSubmissionAsync" "$service"
grep -Fq "BuildPackageChecksum" "$service"
grep -Fq "HasActiveRightsAsync" "$service"
grep -Fq "HasExerciseProvenanceAsync" "$service"
grep -Fq "EDITORIAL.PACKAGE.SUBMIT" "$service"
grep -Fq "pg_advisory_xact_lock" "$service"
grep -Fq "EDITORIAL.SUBMIT" "$service"

if grep -Eq "INSERT INTO editorial\.(review_assignment|review_decision|publication|publication_component)" "$service"; then
  echo "ERROR: BL048 no debe adelantar BL049/050."
  exit 1
fi

grep -Fq "/compatible-package/submit" "$endpoints"
grep -Fq "If-Match" "$endpoints"
grep -Fq "ValidateRequestAsync" "$endpoints"
grep -Fq "SubmitPermissions" "$endpoints"

grep -Fq "Congelar y someter a revisión" "$page"
grep -Fq "No publica contenido" "$page"
grep -Fq "latestSubmission" "$page"
grep -Fq "Tienes cambios sin guardar" "$page"

grep -Fq "max-width: none" "$page_css"
grep -Fq "compatible-package__workspace" "$page_css"
grep -Fq "grid-template-columns" "$page_css"
grep -Fq "position: sticky" "$page_css"

grep -Fq "UI-MVP-026" "$navigation"
grep -Fq "Paquete y revisión" "$navigation"
grep -Fq "/editorial/paquetes/" "$navigation"
grep -Fq "<SongWorkspace match={match}>" "$area"

grep -Fq "guard_package_component_mutable" "$schema"
grep -Fq "v_status IS DISTINCT FROM 'DRAFT'" "$schema"
grep -Fq "ux_editorial_review_submission_01" "$schema"

grep -Fq "MAX(package_no), 0) + 1" "$assembly_service"
grep -Fq "status_code = 'DRAFT'" "$assembly_service"
grep -Fq "frozen_at IS NULL" "$assembly_service"

grep -Fq "BL-MVP-048" "$e2e"
grep -Fq "Congelar y someter a revisión" "$e2e"
grep -Fq "Paquete y revisión" "$e2e"
grep -Fq "AxeBuilder" "$e2e"

echo "OK: BL-MVP-048 congelación y sometimiento verificados."
echo "freeze=package-components-and-checksum"
echo "submission=editorial.review_submission"
echo "new-edits=new-draft"
echo "navigation=song-context"
echo "desktop-layout=full-workspace"
echo "final-publication=false"
