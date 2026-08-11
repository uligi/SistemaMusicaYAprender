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
openssl rand -hex 32 > secrets/local/identity_email_lookup_key
openssl rand -hex 32 > secrets/local/identity_email_encryption_key
openssl rand -hex 32 > secrets/local/identity_verification_token_key
openssl rand -hex 32 > secrets/local/identity_password_fingerprint_key
openssl rand -hex 32 > secrets/local/identity_login_abuse_key
openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -nodes \
  -days 2 \
  -subj '/CN=localhost' \
  -addext 'subjectAltName=DNS:localhost,DNS:api,IP:127.0.0.1' \
  -keyout secrets/local/aspnetcore_local_https.key \
  -out secrets/local/aspnetcore_local_https.pem \
  >/dev/null 2>&1

echo "OK: secretos efimeros de CI preparados para identidades, credenciales, abuso y Docker Compose."
