#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

"$SCRIPT_DIR/restore-and-build.sh"

dotnet test tests/UnitTests/MusicaAprender.UnitTests.csproj --no-build --no-restore
dotnet run --project tests/ArchitectureTests/MusicaAprender.ArchitectureTests.csproj --no-build --no-restore
"$SCRIPT_DIR/check-module-boundaries.sh"

echo "OK: puerta local BL-MVP-004 aprobada."
