#!/usr/bin/env bash
set -euo pipefail

mkdir -p secrets/local

openssl rand -hex 32 > secrets/local/postgres_password
openssl rand -hex 32 > secrets/local/postgres_migrator_password
openssl rand -hex 32 > secrets/local/postgres_api_password
openssl rand -hex 32 > secrets/local/postgres_backoffice_password
openssl rand -hex 32 > secrets/local/postgres_worker_password
openssl rand -hex 32 > secrets/local/postgres_readonly_password
printf 'ci-%s' "$(openssl rand -hex 16)" > secrets/local/object_store_access_key
openssl rand -hex 32 > secrets/local/object_store_secret_key
openssl rand -hex 32 > secrets/local/object_store_encryption_key

echo "OK: secretos efimeros de CI preparados para identidades separadas y Docker Compose."
