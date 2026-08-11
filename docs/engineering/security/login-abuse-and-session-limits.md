# Control de abuso de login y límites de sesión — BL-MVP-029

## Objetivo

Reducir automatización de credenciales sin introducir enumeración ni un bloqueo persistente
explotable contra otra persona.

## Contrato de login

Mientras una dimensión no alcance el límite, un fallo de credenciales conserva el contrato
`401 identity.login.failed`.

Cuando una dimensión ya tiene el número permitido de fallos dentro de la ventana, el siguiente
intento devuelve:

```text
HTTP 429
Retry-After: <segundos>
code: identity.login.rate-limited
```

La respuesta no dice si se limitó la clave de cuenta o la dirección del cliente.

## Política por defecto

| Dimensión                          | Fallos permitidos | Ventana |
| ---------------------------------- | ----------------: | ------: |
| Clave seudónima de cuenta          |                 5 |  15 min |
| Dirección de cliente seudonimizada |                20 |  15 min |

Las tres propiedades son configurables con límites defensivos. El modelo es una ventana móvil: no se
escribe un `locked_until` permanente ni se modifica el estado de la cuenta.

## Persistencia y privacidad

La fuente de evidencia es `security.security_event`, que ya pertenece al modelo aprobado. Los
eventos
de este habilitador se insertan con `account_id = NULL` y una huella HMAC-SHA-256. El éxito usa la
huella de cuenta como sujeto seudónimo. BL-MVP-033 completará la auditoría primaria con
sujeto/objeto
donde corresponda.

La clave `identity_login_abuse_key` está separada de las claves de correo, contraseña y
verificación.
No se guarda correo, contraseña, dirección IP ni token de sesión en el evento.

La evidencia de `security.security_event` no se elimina al finalizar el smoke. El fixture usa una
correlación y direcciones IPv6 de documentación aleatorias por ejecución para respetar el contrato
append-only sin contaminar el contador de una ejecución posterior.

## Concurrencia

Antes de contar fallos se toman dos `pg_advisory_xact_lock` derivados de las huellas. Los locks se
ordenan por su valor de 64 bits para evitar ciclos. El fallo se registra antes de confirmar la
transacción. El sexto fallo de cuenta no se registra como otro fallo: la solicitud posterior al
quinto es la que recibe 429.

## Proxy same-origin

El Nginx local sobrescribe:

```text
X-Musica-Client-Address: $remote_addr
```

y Compose habilita explícitamente la confianza en ese header. La opción debe estar deshabilitada en
una exposición directa de Kestrel o configurarse únicamente detrás de un proxy que sobrescriba el
valor recibido del cliente.

## Sesiones

No se cambia la política establecida por BL-MVP-026:

- `idle_expires_at <= created_at + 12 hours`;
- `absolute_expires_at <= created_at + 30 days`;
- `revoked_at IS NULL` es requisito de resolución.

BL-MVP-029 agrega evidencia explícita que comprueba esos límites y que una sesión revocada produce 401.

## Trazabilidad

- BL-MVP-029.
- CU-MVP-03.
- RNF-MVP-053 — Limitación de login.
- RNF-MVP-056 — Sesión de estudiante.
- RNF-MVP-057 — Cookies y CSRF, conservado por regresión.
- RNF-MVP-064 — eventos de autenticación y fallo, en el alcance limitado de este habilitador.
