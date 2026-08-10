# Verificación de cuenta con token de un uso

## Objetivo

BL-MVP-025 activa una cuenta personal pendiente únicamente después de demostrar posesión del correo mediante un código de vida corta. El diseño reutiliza `security.account_verification`, el outbox transaccional y la entrega SMTP versionada ya aprobados.

## Flujo

1. `POST /api/v1/auth/register` crea cuenta, perfil, consentimientos, desafío y evento de correo en una transacción.
2. La API deriva el token solo para calcular su hash; PostgreSQL conserva `SHA-256(token)`.
3. El worker recibe UUID opacos desde el outbox, lee el correo cifrado bajo `jp_worker`, deriva el mismo token en memoria y renderiza `PERSONAL_ACCOUNT_VERIFICATION:v1:es`.
4. El usuario abre `/verificar-cuenta` y escribe el código; la aplicación no lo toma de la URL.
5. La API valida HMAC e IDs, bloquea cuenta/desafío, compara el hash y revalida términos/privacidad.
6. Una transacción consume todos los desafíos pendientes, activa la cuenta y agrega el evento de seguridad.

## Formato y claves

El material binario contiene `account_id` (16 bytes), `verification_id` (16 bytes) y HMAC-SHA-256 (32 bytes), codificados como base64url canónico sin padding. La firma cubre un propósito versionado y ambos identificadores. La clave `identity_verification_token_key` tiene 32 bytes y no se reutiliza para búsqueda o cifrado del correo.

La vida útil se calcula en PostgreSQL como 30 minutos. La firma se compara en tiempo constante. Un token no canónico, manipulado, desconocido, consumido sin activación o vencido recibe el mismo problema de validación.

## Consumo e idempotencia

El primer consumo válido cambia `security.account.status_code` de `PENDING` a `ACTIVE`, fija `verified_at`, consume todos los desafíos abiertos y agrega `ACCOUNT_VERIFICATION:SUCCEEDED`. Repetir exactamente el token que produjo la activación devuelve éxito sin alterar marcas ni duplicar el evento.

Si las versiones aceptadas ya no coinciden con `RequiredRegistrationConsentPolicy`, la operación devuelve conflicto y no consume ni activa. El usuario debe iniciar nuevamente el registro con las versiones vigentes.

## Reenvío sin enumeración

`POST /api/v1/auth/verification/resend` exige una clave de idempotencia y responde siempre `202` con el mismo cuerpo para correo pendiente, activo, desconocido o inexistente. Solo una cuenta pendiente obtiene un desafío/outbox nuevo.

La búsqueda interna usa `security.resolve_pending_account_for_verification(bytea)`, una función `SECURITY DEFINER` que:

- recibe únicamente un HMAC de correo de 32 bytes;
- devuelve como máximo un UUID;
- limita el resultado a `PENDING` sin `verified_at`;
- fija `search_path = pg_catalog`;
- revoca `PUBLIC`; y
- concede solo `EXECUTE` a `jp_app`.

## Datos sensibles y observabilidad

- No se persiste el token reversible ni se incluye en outbox, jobs, eventos o logs.
- El correo cifrado permanece en `security.account`; el worker lo descifra solo al renderizar.
- El mensaje SMTP contiene el token por necesidad funcional y no se copia a la evidencia.
- La UI no usa query, fragmento, historial, `localStorage` ni `sessionStorage`.
- Los eventos de seguridad conservan cuenta, tipo, resultado, fecha y correlación, nunca token/correo.

## Operación y pruebas

`scripts/ci/identity/verify-account-verification.sh` cubre entrega SMTP real, activación, replay, manipulación, caducidad, prerrequisitos, reenvío no enumerable e idempotencia. Solo publica un resumen sin valores sensibles en `artifacts/postgres/account-verification-summary.txt`.

El incremento no altera `database/postgresql/master/MVP_PostgreSQL_18_Master.sql`, `database/postgresql/migrations/sql/01_initial_schema.sql` ni sus hashes. La función auxiliar vive en el script idempotente de acceso y se vuelve a aplicar después de la migración.
