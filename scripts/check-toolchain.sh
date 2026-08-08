#!/usr/bin/env bash
set -euo pipefail
fail() { echo "ERROR: $1" >&2; exit 1; }

dotnet_version="$(dotnet --version)"
[[ "$dotnet_version" =~ ^9\.0\.3[0-9]{2}$ ]] || fail "Se requiere un SDK .NET 9.0.3xx. Encontrado: $dotnet_version"

node_version="$(node --version)"
[[ "$node_version" == "v24.18.0" ]] || fail "Se requiere Node.js v24.18.0. Encontrado: $node_version"

npm_version="$(npm --version)"
[[ "$npm_version" == "11.16.0" ]] || fail "Se requiere npm 11.16.0. Encontrado: $npm_version"

echo "Toolchain válida: .NET $dotnet_version | Node $node_version | npm $npm_version"
