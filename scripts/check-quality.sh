#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

"$SCRIPT_DIR/security/check-no-secrets.sh"
"$SCRIPT_DIR/restore-and-build.sh"

dotnet test tests/UnitTests/MusicaAprender.UnitTests.csproj --no-build --no-restore
dotnet run --project tests/ArchitectureTests/MusicaAprender.ArchitectureTests.csproj --no-build --no-restore
"$SCRIPT_DIR/check-module-boundaries.sh"
"$SCRIPT_DIR/governance/check-templates.sh"

echo "OK: puerta local BL-MVP-009 aprobada."
