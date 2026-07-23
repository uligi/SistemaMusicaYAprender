#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
violations=0

while IFS= read -r -d '' project; do
  while IFS= read -r reference; do
    normalized="${reference//\\//}"
    if [[ "$normalized" == *"/Modules/"* ]]; then
      echo "Referencia prohibida: ${project#$repo_root/} -> $reference" >&2
      violations=1
    fi
  done < <(grep -oE 'ProjectReference Include="[^"]+"' "$project" | sed -E 's/.*Include="([^"]+)"/\1/' || true)
done < <(find "$repo_root/src/Modules" -name '*.csproj' -print0)

if [[ "$violations" -ne 0 ]]; then
  exit 1
fi

echo "OK: no existen ProjectReference directos entre módulos."
