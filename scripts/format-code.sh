#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/check-toolchain.sh"
dotnet restore MusicaAprender.sln

if [[ ! -f package-lock.json ]]; then
  npm install --package-lock-only
fi

npm ci
dotnet format MusicaAprender.sln --no-restore
npm run format

echo "Formato aplicado a backend, frontend, documentación y SQL."
