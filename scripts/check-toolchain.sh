#!/usr/bin/env bash
set -euo pipefail

dotnet_version="$(dotnet --version)"
node_version="$(node --version)"
npm_version="$(npm --version)"

if [[ ! "$dotnet_version" =~ ^9\.0\.3[0-9]{2}$ ]]; then
  echo "Se requiere un SDK .NET de la banda 9.0.3xx. Encontrado: $dotnet_version" >&2
  exit 1
fi

if [[ "$node_version" != "v24.18.0" ]]; then
  echo "Se requiere Node.js v24.18.0. Encontrado: $node_version" >&2
  exit 1
fi

if [[ "$npm_version" != "11.16.0" ]]; then
  echo "Se requiere npm 11.16.0. Encontrado: $npm_version" >&2
  exit 1
fi

echo "Toolchain válida: .NET $dotnet_version | Node $node_version | npm $npm_version"
