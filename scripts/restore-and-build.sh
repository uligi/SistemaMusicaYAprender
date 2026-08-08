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
npm run format:check
npm run build

dotnet format MusicaAprender.sln --verify-no-changes --no-restore
dotnet build MusicaAprender.sln --no-restore

echo "Restauración, análisis, formato y compilación completados."
