#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/check-toolchain.sh"
dotnet tool restore
dotnet restore MusicaAprender.sln

if [[ ! -f package-lock.json ]]; then
  echo "Generando package-lock.json por primera vez..."
  npm install --package-lock-only
fi

npm ci
npm run typecheck
npm run build
dotnet build MusicaAprender.sln --no-restore

echo "Restauración y compilación reproducibles completadas."
