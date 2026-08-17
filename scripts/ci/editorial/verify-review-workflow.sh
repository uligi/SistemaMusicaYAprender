#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

service="src/Modules/Editorial/Infrastructure/Administration/EditorialReviewWorkflowService.cs"
endpoint="apps/api/Endpoints/Administration/EditorialReviewWorkflowEndpoints.cs"
page="apps/web/src/routes/administration/EditorialReviewPage.tsx"
css="apps/web/src/routes/administration/editorial-review.css"
area="apps/web/src/routes/administration/AdministrationArea.tsx"
routes="apps/web/src/app/router/route-manifest.ts"

for path in "$service" "$endpoint" "$page" "$css" "$area" "$routes"; do
  test -f "$path" || { echo "Falta $path" >&2; exit 1; }
done

grep -q "editorial.review_assignment" "$service"
grep -q "editorial.review_decision" "$service"
grep -q "conflict_declared = true" "$service"
grep -q "EDITORIAL.REVIEW.ASSIGN" "$service"
grep -q "EDITORIAL.REVIEW.CONFLICT" "$service"
grep -q "EDITORIAL.REVIEW.DECIDE" "$service"
grep -q "RequireRecentPrivilegedAssurance" "$endpoint"
grep -q "IfMatch" "$endpoint"
grep -q "UI-MVP-027" "$page"
grep -q "BL-MVP-050" "$page"
grep -q "var(--ma-color-" "$css"

if grep -Eq '#[0-9A-Fa-f]{3,8}|rgb\(|rgba\(' "$css"; then
  echo "BL049 no debe introducir colores crudos: usa tokens semánticos." >&2
  exit 1
fi

if grep -Eq 'INSERT INTO editorial\.publication|INSERT INTO editorial\.publication_component|UPDATE editorial\.publication|DELETE FROM editorial\.publication' "$service"; then
  echo "BL049 cruzó la frontera: no puede publicar." >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
s = Path("src/Modules/Editorial/Infrastructure/Administration/EditorialReviewWorkflowService.cs").read_text(encoding="utf-8")
checks = {
    "assignment_is_explicit": "ReviewerId" in s and "INSERT INTO editorial.review_assignment" in s,
    "conflict_is_blocking": "assignment.ConflictDeclared" in s and "editorial.review.decision.conflict" in s,
    "decision_is_insert_only": "INSERT INTO editorial.review_decision" in s and "DELETE FROM editorial.review_decision" not in s,
    "rejection_reason": "NormalizeReason(command.Reason)" in s,
    "publication_boundary": "INSERT INTO editorial.publication" not in s and "publication_component" not in s,
    "optimistic_concurrency": "EnsureIfMatch" in s and "pg_advisory_xact_lock" in s,
}
for k, v in checks.items():
    print(f"{k}={str(v).lower()}")
    if not v:
        raise SystemExit(1)
PY

echo "BL-MVP-049 review workflow static verifier: GREEN"
