#!/usr/bin/env bash
set -euo pipefail

mkdir -p secrets/local

openssl rand -hex 32 > secrets/local/postgres_password
printf 'ci-%s' "$(openssl rand -hex 16)" > secrets/local/object_store_access_key
openssl rand -hex 32 > secrets/local/object_store_secret_key

echo "OK: secretos efimeros de CI preparados para validar Docker Compose."
