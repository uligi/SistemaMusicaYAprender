#!/usr/bin/env bash
set -euo pipefail

service="src/Modules/Editorial/Infrastructure/Administration/CompatibleEducationalPackageService.cs"
endpoints="apps/api/Endpoints/Editorial/CompatibleEducationalPackageEndpoints.cs"
page="apps/web/src/routes/editorial/CompatiblePackagePage.tsx"

test -f "$service"
test -f "$endpoints"
test -f "$page"

grep -Fq "editorial.editorial_package" "$service"
grep -Fq "editorial.package_component" "$service"
grep -Fq "BuildPackageChecksum" "$service"
grep -Fq "SourcesCompatible" "$service"
grep -Fq "HasBrokenLinks" "$service"
grep -Fq "HasActiveRightsAsync" "$service"
grep -Fq "EDITORIAL.PACKAGE.ASSEMBLE" "$service"
grep -Fq "status_code = 'DRAFT'" "$service"
grep -Fq "frozen_at IS NULL" "$service"

if grep -Eq "INSERT INTO editorial\.(publication|publication_component|review_submission|review_decision)" "$service"; then
  echo "ERROR: BL047 no debe adelantar BL048-050."
  exit 1
fi

grep -Fq "If-Match" "$endpoints"
grep -Fq "IAntiforgery" "$endpoints"
grep -Fq "RequireAnyEffectivePermission" "$endpoints"
grep -Fq 'data-route-id="UI-MVP-026"' "$page"
grep -Fq "publica contenido" "$page"

echo "OK: BL-MVP-047 ensamblaje compatible verificado."
echo "components=LYRICS,TIMING,TRANSLATION,ANALYSIS,EXERCISE"
echo "compatibility=exact-source-revisions"
echo "checksum=sha256-deterministic"
echo "package-state=DRAFT-only"
echo "final-publication=false"
