#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/restore-and-build.sh"
dotnet run --project tests/ArchitectureTests/MusicaAprender.ArchitectureTests.csproj --no-restore
"$ROOT/scripts/check-module-boundaries.sh"

echo "OK: puerta local BL-MVP-003 aprobada."
