#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

fail() {
  echo "ERROR: FIX-MVP-USERNAME-DIRECTORY-001: $1" >&2
  exit 1
}

grep -Fq '202608180001_UsernameIdentityDirectory' \
  tools/DatabaseMigrator/Migrations/UsernameIdentityDirectory.cs \
  || fail "falta la migración forward-only de username."

grep -Fq 'uq_identity_user_profile_username' \
  tools/DatabaseMigrator/Migrations/UsernameIdentityDirectory.cs \
  || fail "falta unicidad física del username."

grep -Fq 'UsernamePolicy.Validate' \
  apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs \
  || fail "registro no valida username en servidor."

grep -Fq 'Username' \
  apps/api/Endpoints/Identity/PersonalAccountRegistrationRequest.cs \
  || fail "contrato de registro no recibe username."

grep -Fq '/api/v1/profile/username' \
  apps/api/Endpoints/Identity/PersonalUsernameEndpoints.cs \
  || fail "falta claim autenticado del username."

grep -Fq '/api/v1/security/account-directory' \
  apps/api/Endpoints/Security/RoleAssignmentEndpoints.cs \
  || fail "falta directorio administrativo."

grep -Fq 'RequireRecentPrivilegedAssurance()' \
  apps/api/Endpoints/Security/RoleAssignmentEndpoints.cs \
  || fail "el directorio no conserva la puerta MFA."

grep -Fq 'SECURITY.MANAGE_ROLES' \
  src/Modules/Security/Infrastructure/Administration/RoleAssignmentAdministrationService.cs \
  || fail "el directorio no conserva defensa de autorización."

grep -Fq 'Buscar cuenta por nombre de usuario' \
  apps/web/src/routes/administration/AccountDirectoryPicker.tsx \
  || fail "Roles y accesos no usa el selector humano."

if grep -Fq 'Pega el UUID de la cuenta' \
  apps/web/src/routes/administration/RoleManagementPage.tsx; then
  fail "la UI administrativa todavía exige UUID manual."
fi

grep -Fq 'profile.username' \
  src/Modules/Editorial/Infrastructure/Administration/EditorialReviewWorkflowService.cs \
  || fail "revisión editorial no resuelve etiquetas por username."

if grep -Fq 'ReviewerLabel(Guid accountId)' \
  src/Modules/Editorial/Infrastructure/Administration/EditorialReviewWorkflowService.cs; then
  fail "continúa activa la etiqueta sintética basada en UUID."
fi

if grep -Eqi 'email_cipher|email_lookup_hash|credential_hash|credential_parameters' \
  apps/web/src/routes/administration/AccountDirectoryPicker.tsx \
  src/Modules/Security/Infrastructure/Administration/RoleAssignmentAdministrationService.cs; then
  fail "el directorio contiene referencias a identidad sensible."
fi

if [[ -n "${PGHOST:-}" && -n "${PGPORT:-}" && -n "${PGUSER:-}" \
      && -n "${PGDATABASE:-}" && -n "${PGPASSWORD:-}" ]]; then
  psql_base=(
    psql
    --host="$PGHOST"
    --port="$PGPORT"
    --username="$PGUSER"
    --dbname="$PGDATABASE"
    --no-password
    --tuples-only
    --no-align
    --set=ON_ERROR_STOP=1
  )

  column_ok="$("${psql_base[@]}" --command="
SELECT count(*) = 1
FROM information_schema.columns
WHERE table_schema = 'identity'
  AND table_name = 'user_profile'
  AND column_name = 'username'
  AND character_maximum_length = 32;
" | tr -d '[:space:]')"
  [[ "$column_ok" == "t" ]] || fail "la base no contiene identity.user_profile.username."

  index_ok="$("${psql_base[@]}" --command="
SELECT to_regclass('identity.uq_identity_user_profile_username') IS NOT NULL;
" | tr -d '[:space:]')"
  [[ "$index_ok" == "t" ]] || fail "la base no contiene el índice único de username."
fi

echo "username_policy=true"
echo "registration_username=true"
echo "personal_claim=true"
echo "admin_directory_safe=true"
echo "reviewer_labels=true"
echo "FIX-MVP-USERNAME-DIRECTORY-001 static verifier: GREEN"
