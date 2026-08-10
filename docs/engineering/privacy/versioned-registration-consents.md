# Consentimientos versionados durante el registro

## Alcance

BL-MVP-024 extiende `POST /api/v1/auth/register` para exigir y conservar las aceptaciones obligatorias de registro. No activa la cuenta, no crea una credencial y no consume el token de verificación; esas responsabilidades permanecen en BL-MVP-025 y BL-MVP-028.

Finalidades vigentes del corte:

| Finalidad        | Título visible         | Versión      | Obligatoria |
| ---------------- | ---------------------- | ------------ | ----------- |
| `TERMS_OF_USE`   | Términos de uso        | `2026-08-10` | Sí          |
| `PRIVACY_POLICY` | Política de privacidad | `2026-08-10` | Sí          |

La versión es un identificador técnico estable de la publicación. El texto jurídico definitivo y su aprobación pertenecen al proceso legal/editorial; no se inventa ni se almacena como texto libre dentro de `identity.consent_record`.

## Contrato público

`GET /api/v1/auth/registration-consents` publica únicamente las versiones obligatorias vigentes, su título, finalidad y comienzo de vigencia. No devuelve datos personales ni decisiones de otras cuentas.

`POST /api/v1/auth/register` exige `Idempotency-Key` y un arreglo `consents` con una decisión afirmativa por finalidad y la versión exacta publicada. El servidor rechaza antes de reservar la operación si una aceptación:

- falta;
- aparece más de una vez;
- utiliza una finalidad desconocida;
- contiene una decisión negativa; o
- referencia una versión obsoleta.

## Persistencia e invariantes

Para una cuenta nueva, `security.account`, `identity.user_profile` y las dos filas de `identity.consent_record` se confirman en la misma transacción. Cada fila conserva `account_id` como actor/sujeto, `purpose_code`, `notice_version`, `decision=true` y `decided_at` generado por PostgreSQL.

Las evidencias son append-only mediante `tr_identity_consent_record_append_only`. Un replay con la misma clave y el mismo cuerpo reproduce la respuesta almacenada sin duplicarlas. Una identidad ya registrada recibe la misma respuesta genérica, pero no se le agregan aceptaciones anónimas nuevas.

El digest idempotente incluye el HMAC del correo y la lista canónica de finalidades, versiones y decisiones. Cambiar cualquiera de esos datos con la misma clave produce conflicto `409`.

## Fronteras posteriores

- BL-MVP-025 deberá revalidar que las aceptaciones obligatorias continúan vigentes antes de activar la cuenta mediante el token de un uso.
- BL-MVP-026 y BL-MVP-030 aportarán sesión y autorización para consultar o modificar datos propios.
- La retirada de consentimientos opcionales desde `UI-MVP-008` se implementará cuando exista sesión; nunca sobrescribirá una aceptación anterior.
- BL-MVP-033 completará la auditoría primaria correlacionada.
- BL-MVP-036 administrará publicación y sustitución mutable de configuraciones; este corte conserva una línea base controlada por versión del producto.

## Evidencia

- Playwright y axe comprueban carga de versiones, teclado, foco, aceptación explícita, error local, reflujo a 320 px y respuesta genérica.
- `scripts/ci/identity/verify-personal-registration.sh` prueba API y PostgreSQL reales: catálogo vigente, alta atómica, dos aceptaciones, replay, duplicado no enumerativo, versión obsoleta, aceptación ausente/rechazada e inmutabilidad.
- El resumen reproducible se escribe en `artifacts/postgres/personal-registration-summary.txt`.
