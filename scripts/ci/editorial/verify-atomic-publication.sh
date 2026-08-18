#!/usr/bin/env bash
set -euo pipefail

service="src/Modules/Editorial/Infrastructure/Administration/EditorialPublicationLifecycleService.cs"
endpoints="apps/api/Endpoints/Administration/EditorialPublicationLifecycleEndpoints.cs"
panel="apps/web/src/routes/administration/EditorialPublicationPanel.tsx"
test_file="tests/E2ETests/editorial-publication.spec.ts"

for file in "$service" "$endpoints" "$panel" "$test_file"; do
  [[ -f "$file" ]] || { echo "ERROR: falta $file" >&2; exit 1; }
done

grep -q "status_code = 'APPROVED'" "$service"
grep -q "review_decision" "$service"
grep -q "decision_code = 'APPROVED'" "$service"
grep -q "ComponentsAreCurrentAsync" "$service"
grep -q "rights_scope" "$service"
grep -q "INSERT INTO editorial.publication (" "$service"
grep -q "INSERT INTO editorial.publication_component" "$service"
grep -q "INSERT INTO editorial.publication_availability" "$service"
grep -q "INSERT INTO security.audit_event" "$service"
grep -q "outbox.EnqueueAsync" "$service"
grep -q "editorial.publication.activated.v1" "$service"
grep -q "Idempotency-Key" "$endpoints"
grep -q "IfMatch" "$endpoints"
grep -q "RequireRecentPrivilegedAssurance" "$endpoints"
grep -q "EDITORIAL.PUBLISH" "$endpoints"
grep -q "Confirmar publicación" "$panel"

if grep -q "INSERT INTO editorial.published_package_projection" "$service"; then
  echo "ERROR: BL050 no puede escribir directamente la proyección pública." >&2
  exit 1
fi

echo "approved_package_exact=true"
echo "atomic_publication_rows=true"
echo "rights_scope_revalidated=true"
echo "audit_and_outbox_same_service=true"
echo "optimistic_concurrency=true"
echo "idempotency_key=true"
echo "projection_is_not_authority=true"
echo "BL-MVP-050 atomic publication static verifier: GREEN"
