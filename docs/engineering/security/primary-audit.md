# Auditoría primaria protegida

BL-MVP-033 consolida eventos de seguridad y decisiones auditables sin crear una segunda fuente de verdad.

## Dos registros con finalidad distinta

`security.security_event` representa resultados de seguridad: registro, verificación, login, sesión, MFA y decisión de autorización. Puede conservar `account_id` cuando el sujeto es conocido dentro del contexto RLS; los flujos no enumerables usan `account_id = NULL` y un fingerprint pseudónimo de 32 bytes.

`security.audit_event` representa decisiones protegidas con actor, rol efectivo, objeto, acción, digest antes/después cuando aplica, motivo, tiempo y correlación. Las decisiones de autorización se registran como un par correlacionado: el resultado en `security_event` y el contexto de actor/objeto/acción en `audit_event`.

## Integridad y privacidad

Ambas tablas ya usan triggers append-only. BL-MVP-033 no introduce UPDATE/DELETE normal sobre esos registros. `jp_login_readonly` no recibe acceso a las tablas privadas.

No se persisten correos, contraseñas, tokens de sesión, códigos TOTP ni secretos MFA dentro de los eventos. Los digests son SHA-256 de representaciones canónicas no secretas de la decisión.

La operación protegida falla cerrada si una decisión de autorización no puede registrar su auditoría primaria.

## Correlación

Cuando `X-Correlation-Id` es UUID, se conserva exactamente. Para identificadores seguros no UUID se deriva un UUID estable mediante SHA-256. Las marcas de tiempo se generan con `CURRENT_TIMESTAMP` en PostgreSQL.

## Límite de BL-MVP-033

Este incremento cubre la **captura primaria** y su protección append-only. No declara completos CA-MVP-145 a CA-MVP-150 ni CU-MVP-25 completo: la consulta de investigación, sellado/exportación, verificación de integridad de cadena y operación de retención se completan en backlog posterior, incluido BL-MVP-090.
