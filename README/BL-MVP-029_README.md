# BL-MVP-029 — Controlar abuso, bloqueo y límites de sesión

## Definición normativa

- Fase: F1 — Identidad, acceso y configuración.
- Épica: EP-03 — Identidad, seguridad y autorización.
- Tipo: Habilitador.
- Traza: CU-MVP-03; SEG; DIS.
- Story Points: 5.
- Dependencias: BL-MVP-026 y BL-MVP-028.
- Resultado: intentos repetidos reciben límites y una respuesta no enumerativa; expiración
  absoluta/inactividad y revocación quedan verificables.

## Política aplicada

RNF-MVP-053 se implementa como una ventana móvil configurable, sin bloqueo persistente explotable:

- 5 fallos por clave seudónima de cuenta en 15 minutos;
- 20 fallos por dirección de cliente seudonimizada en 15 minutos;
- el sexto intento de la misma cuenta y el vigesimoprimero del mismo cliente reciben HTTP 429;
- `Retry-After` informa una espera acotada sin revelar qué dimensión llegó al límite;
- al salir los fallos de la ventana, el acceso vuelve a evaluarse automáticamente;
- cuenta conocida, cuenta desconocida y contraseña incorrecta conservan el mismo 401 antes del
  límite.

No se cambia `security.account.status_code` para aplicar el límite. El control es temporal y no crea
un bloqueo permanente que un tercero pueda explotar contra otra persona.

## Privacidad y evidencia

Se incorpora `identity_login_abuse_key`, una clave HMAC-SHA-256 separada y montada únicamente en la
API. Correo e IP no se escriben en `security.security_event`; se guardan huellas de 32 bytes con
separación de propósito.

Los eventos usados por este corte son:

- `LOGIN_FAILURE_ACCOUNT` / `REJECTED`;
- `LOGIN_FAILURE_CLIENT` / `REJECTED`;
- `LOGIN_RATE_LIMITED` / `THROTTLED`;
- `LOGIN_SUCCESS` / `SUCCESS`.

Todos estos eventos usan una huella seudónima. BL-MVP-033 completará la auditoría primaria con
sujeto y objeto cuando corresponda.

`security.security_event` ya existe en el diseño físico y es append-only. BL-MVP-029 no agrega
tablas, columnas ni índices, y no modifica el SQL maestro ni la migración inicial.

El smoke conserva sus eventos y demás evidencia append-only. Cada ejecución usa correlación, cuenta y
direcciones sintéticas distintas para no depender de borrar ni deshabilitar protecciones físicas.

## Concurrencia

La comprobación de cada intento toma locks transaccionales de PostgreSQL derivados de las dos
huellas. El orden de los locks es estable para evitar interbloqueos. La evaluación, la verificación
Argon2id y el registro de un fallo se mantienen dentro de esa transacción, evitando que solicitudes
concurrentes salten silenciosamente los contadores en una única base compartida.

## Dirección del cliente

El proxy same-origin sobrescribe `X-Musica-Client-Address` con `$remote_addr`. La API solo confía
ese encabezado cuando `Security:LoginAbuse:TrustClientAddressHeader=true`; fuera de un proxy
confiable debe permanecer `false` y se usa `RemoteIpAddress`.

## Sesión

BL-MVP-029 conserva y verifica los límites de estudiante ya materializados por BL-MVP-026:

- inactividad: máximo 12 horas;
- duración absoluta: máximo 30 días;
- sesión revocada: no vuelve a autenticar.

No hay sliding expiration ni extensión del vencimiento absoluto.

## Evidencia automatizada

- Unit: huellas deterministas, de 32 bytes y separadas por propósito.
- Playwright/axe: HTTP 429 se presenta como espera recuperable y no revela si el límite fue cuenta
  o IP.
- Smoke API/PostgreSQL:
  - 5 fallos de cuenta -> 401; siguiente -> 429;
  - cuenta desconocida produce el mismo 401/429;
  - 20 fallos desde un cliente con claves distintas -> siguiente 429;
  - recuperación automática mediante una ventana reducida solo para el smoke;
  - eventos seudonimizados de 32 bytes;
  - sesión STUDENT <=12 h / <=30 días;
  - revocación posterior -> 401.
- CI ejecuta el smoke BL-MVP-029 después de BL-MVP-027.

## Fuera de alcance

- permisos efectivos y scopes: BL-MVP-030;
- gestión de roles: BL-MVP-031;
- MFA/reautenticación privilegiada: BL-MVP-032;
- auditoría primaria completa: BL-MVP-033;
- recuperación de contraseña;
- bloqueo permanente de cuentas;
- cambios al SQL maestro, migración inicial o esquema físico.
