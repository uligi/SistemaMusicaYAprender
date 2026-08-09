#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

mapfile -t tracked_files < <(git ls-files)

for file in "${tracked_files[@]}"; do
  if [[ "$file" == secrets/* ]]; then
    echo "ERROR: Git rastrea un archivo bajo secrets/: $file" >&2
    exit 1
  fi

  if [[ "$file" =~ (^|/)\.env($|\.) ]] && [[ "$file" != ".env.example" ]]; then
    echo "ERROR: Git rastrea un archivo de ambiente prohibido: $file" >&2
    exit 1
  fi
done

patterns=(
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  'github_pat_[A-Za-z0-9_]{20,}'
  'gh[pousr]_[A-Za-z0-9]{20,}'
  'AKIA[0-9A-Z]{16}'
  'sk-[A-Za-z0-9_-]{24,}'
)

for pattern in "${patterns[@]}"; do
  if git grep -I -n -E -- "$pattern" -- \
      '*.cs' '*.ts' '*.tsx' '*.js' '*.json' '*.yml' '*.yaml' \
      '*.md' '*.ps1' '*.sh' '*.sql' '*.props' '*.csproj' '*.xml' \
      '*.conf' '*.txt' '*.example' 'Dockerfile' 2>/dev/null; then
    echo "ERROR: posible secreto o credencial prohibida detectada." >&2
    exit 1
  fi
done

if [[ -f ".env.example" ]]; then
  if grep -E '^[[:space:]]*[A-Za-z0-9_]*(PASSWORD|SECRET|TOKEN|PRIVATE_KEY|ACCESS_KEY)[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*.+$' .env.example; then
    echo "ERROR: .env.example contiene un valor para una clave sensible." >&2
    exit 1
  fi
fi

# En CI, si ya existen secretos efimeros para validar Compose, comprobamos sus
# valores reales sin codificarlos en este script.
if [[ -d "secrets/local" ]]; then
  while IFS= read -r -d '' secret_file; do
    secret_value="$(tr -d '\r\n' < "$secret_file")"

    if [[ ${#secret_value} -lt 16 ]]; then
      continue
    fi

    if git grep -I -n -F -- "$secret_value" -- \
        '*.cs' '*.ts' '*.tsx' '*.js' '*.json' '*.yml' '*.yaml' \
        '*.md' '*.ps1' '*.sh' '*.sql' '*.props' '*.csproj' '*.xml' \
        '*.conf' '*.txt' '*.example' 'Dockerfile' 2>/dev/null; then
      echo "ERROR: un valor del secret store aparece en el arbol rastreado." >&2
      exit 1
    fi
  done < <(find secrets/local -maxdepth 1 -type f -print0)
fi

echo "OK: no hay secretos rastreados ni valores del secret store en el repositorio."
