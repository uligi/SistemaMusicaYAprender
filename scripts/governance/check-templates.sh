#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

issue=".github/ISSUE_TEMPLATE/implementation.yml"
config=".github/ISSUE_TEMPLATE/config.yml"
pr=".github/pull_request_template.md"

for file in "$issue" "$config" "$pr"; do
  [[ -f "$file" ]] || { echo "ERROR: falta archivo de gobierno requerido: $file" >&2; exit 1; }
done

issue_markers=(
  "id: backlog_id"
  "id: phase"
  "id: epic"
  "id: traceability"
  "id: acceptance"
  "id: data_permissions"
  "id: dependencies"
  "id: data_risk"
  "id: security_risk"
  "id: evidence"
  "id: done"
)

for marker in "${issue_markers[@]}"; do
  grep -Fq "$marker" "$issue" || { echo "ERROR: plantilla de issue sin campo $marker" >&2; exit 1; }
done

required_count="$(grep -Ec 'required:[[:space:]]*true' "$issue")"
if [[ "$required_count" -lt 11 ]]; then
  echo "ERROR: plantilla de issue con menos campos obligatorios de los esperados ($required_count < 11)." >&2
  exit 1
fi

pr_markers=(
  "## Issue / backlog"
  "## Trazabilidad"
  "## Datos y permisos"
  "## Riesgos"
  "## Pruebas ejecutadas"
  "## Evidencia"
  "## Revisión requerida"
  "## Definition of Done"
)

for marker in "${pr_markers[@]}"; do
  grep -Fq "$marker" "$pr" || { echo "ERROR: plantilla de PR sin seccion $marker" >&2; exit 1; }
done

echo "OK: plantillas de issue, PR y trazabilidad BL-MVP-005 verificadas."
