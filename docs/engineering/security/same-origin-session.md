# Sesión de mismo origen — BL-MVP-026

## Alcance y trazabilidad

BL-MVP-026 implementa CU-MVP-03 y UI-MVP-007, con trazabilidad principal a CE-01 y CE-11, RNF-049, RNF-052, RNF-056 a RNF-058 y RNF-065. Usa la credencial Argon2id de BL-MVP-028 y el estado activo/verificado de BL-MVP-025.

El alcance termina en autenticación, cookie, CSRF y validación de sesión. Cierre de sesión, controles de abuso, permisos efectivos, recuperación, MFA y auditoría completa pertenecen a BL-MVP-027, BL-MVP-029, BL-MVP-030 y BL-MVP-033.

## Flujo de autenticación

1. La interfaz obtiene un token de solicitud desde `GET /api/v1/auth/csrf`; la respuesta usa `Cache-Control: no-store`.
2. El navegador conserva la cookie antifalsificación `__Host-MusicaAprender.Csrf` y envía el token por `X-CSRF-TOKEN`.
3. `POST /api/v1/auth/login` normaliza el correo con la protección existente y resuelve una credencial solo si la cuenta está activa y verificada.
4. Siempre se ejecuta una verificación Argon2id. Para correo inválido, cuenta inexistente o credencial no utilizable se verifica un derivado señuelo con la misma política.
5. Un resultado válido crea un identificador aleatorio de 256 bits. PostgreSQL conserva exclusivamente `SHA-256(identificador)`.
6. ASP.NET Core protege el identificador del almacén de tickets antes de emitirlo en la cookie de autenticación.
7. Cada solicitud con cookie vuelve a resolver la fila y rechaza cuenta no activa, revocación, inactividad o vencimiento absoluto.

## Contrato de cookies

| Cookie                          | HttpOnly | Secure  | SameSite | Path | Domain  | Persistencia                      |
| ------------------------------- | -------- | ------- | -------- | ---- | ------- | --------------------------------- |
| `__Host-MusicaAprender.Csrf`    | Sí       | Siempre | Strict   | `/`  | Ausente | Token antifalsificación protegido |
| `__Host-MusicaAprender.Session` | Sí       | Siempre | Strict   | `/`  | Ausente | Ticket protegido con clave opaca  |

El prefijo `__Host-` obliga a mantener `Secure`, `Path=/` y ausencia de `Domain`. La aplicación web usa solicitudes de mismo origen con `credentials: same-origin`; no configura CORS general ni guarda tokens en `localStorage`, `sessionStorage` o la URL.

En Docker Compose local, Nginx usa una configuración montada específica y cifra el salto hacia Kestrel en `https://api:8443`. El certificado y su clave se generan en `secrets/local`, permanecen fuera de Git y se montan como secretos. El proxy local no valida la cadena autofirmada porque la red es efímera y controlada; producción debe usar TLS de borde y certificados administrados. El smoke llama `/api/v1` a través de la web para verificar el mismo límite de origen que utiliza el navegador.

## Persistencia y vencimiento

`security.session` conserva:

- UUID interno de sesión y cuenta propietaria;
- hash SHA-256 de 32 bytes del identificador opaco;
- `assurance_level = PASSWORD`;
- creación, vencimiento por inactividad y vencimiento absoluto;
- instante de revocación nullable.

La política del MVP fija 12 horas de inactividad y 30 días absolutos. BL-MVP-026 no renueva automáticamente `idle_expires_at`; por tanto, 12 horas es un límite superior conservador. La renovación controlada y los límites de sesiones se incorporan en BL-MVP-029.

## Acceso mínimo a PostgreSQL

Las búsquedas previas a conocer la cuenta y la validación por hash requieren tres funciones `SECURITY DEFINER` con `search_path = pg_catalog`:

- `security.resolve_active_password_credential(bytea)`;
- `security.resolve_active_session(bytea)`;
- `security.revoke_active_session(bytea)`.

Las funciones rechazan longitudes inesperadas, no quedan disponibles para `PUBLIC` y solo conceden `EXECUTE` a `jp_app`. La creación de la fila de sesión continúa bajo la política RLS del propietario y el contexto transaccional `app.account_id`.

## Respuesta no enumerable

Correo desconocido, contraseña incorrecta y cuenta no activa producen el mismo `401`, título, detalle y código `identity.login.failed`. La API no devuelve `account_id`, `session_id`, hash, token ni causa interna. Los límites de frecuencia y otras defensas contra abuso se agregan en BL-MVP-029 sin cambiar este contrato público.

## Evidencia

Las pruebas unitarias cubren aleatoriedad, formato Base64URL, hash determinista y material inválido. Playwright cubre teclado, pegado, `autocomplete`, foco, limpieza y almacenamiento cliente vacío. El smoke real crea una credencial Argon2id, autentica una cuenta activa, valida cookies y CSRF sobre el salto HTTPS local, inspecciona la fila hash y demuestra el rechazo de credenciales inválidas, cuenta bloqueada, sesión vencida y sesión revocada.
