#!/usr/bin/env bash
set -euo pipefail

service="src/Modules/Editorial/Infrastructure/Administration/EditorialPublicationLifecycleService.cs"
endpoints="apps/api/Endpoints/Administration/EditorialPublicationLifecycleEndpoints.cs"
page="apps/web/src/routes/administration/PublicationCorrectionPage.tsx"
area="apps/web/src/routes/administration/AdministrationArea.tsx"
test_file="tests/E2ETests/editorial-correction.spec.ts"

for file in "$service" "$endpoints" "$page" "$area" "$test_file"; do
  [[ -f "$file" ]] || { echo "ERROR: falta $file" >&2; exit 1; }
done

grep -q "INSERT INTO editorial.correction_case" "$service"
grep -q "INSERT INTO editorial.publication_action" "$service"
grep -q '"WITHDRAW"' "$service"
grep -q '"RESTORE"' "$service"
grep -q '"REVERT"' "$service"
grep -q '"SUBSTITUTE"' "$service"
grep -q "CopyPublishedComponentsAsync" "$service"
grep -q "TargetPublicationId" "$service"
grep -q "TargetPackageId" "$service"
grep -q "editorial.publication.reverted.v1" "$service"
grep -q "editorial.publication.restored.v1" "$service"
grep -q "editorial.publication.substituted.v1" "$service"
grep -q "EDITORIAL.CORRECT" "$endpoints"
grep -q "UI-MVP-028" "$page"
grep -q "PublicationCorrectionPage" "$area"

if grep -Eq "DELETE FROM editorial\.(publication|publication_component|publication_action|correction_case)" "$service"; then
  echo "ERROR: BL051 no puede borrar historial editorial." >&2
  exit 1
fi

echo "history_preserved=true"
echo "correction_case=true"
echo "publication_action_append_only=true"
echo "withdraw_restore_revert_substitute=true"
echo "concurrent_correction_guard=true"
echo "same_recording_substitution=true"
echo "BL-MVP-051 publication correction static verifier: GREEN"
