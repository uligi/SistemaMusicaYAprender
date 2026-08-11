# BL-MVP-033 — Eventos de seguridad y auditoría primaria

**Fase:** F1 — Identidad, acceso y configuración  
**Tipo:** Habilitador · **SP:** 8  
**Traza:** CU-MVP-02, CU-MVP-03, CU-MVP-23 a CU-MVP-25; CE-14; OBS  
**Base:** `51c49e039e5b244dd8b4f2b27254ed4899bdc1b4`

Resultado: éxitos, fallos y denegaciones conservan sujeto, acción, objeto, resultado, tiempo y correlación en registros protegidos.

## Alcance

BL-MVP-033 consolida la captura primaria ya iniciada en registro, verificación, login y administración de roles. Agrega un escritor común para `security.security_event` y `security.audit_event`, registra alta de cuenta, ciclo de sesión, MFA y decisiones de autorización/assurance, y mantiene las decisiones de rol de BL-MVP-031.

Los eventos no guardan correo, contraseña, token ni secreto MFA. Los casos anónimos o no enumerables usan un fingerprint pseudónimo de 32 bytes. Las decisiones de autorización conservan un objeto canónico, acción/permiso evaluado, rol efectivo, resultado y `correlation_id`.

`security.security_event` y `security.audit_event` ya son append-only por el DDL publicado; el smoke verifica que UPDATE/DELETE fallen y que `jp_login_readonly` no pueda consultarlas.

## Frontera

Este BL implementa **auditoría primaria**, no la experiencia completa de investigación de CU-MVP-25. La consulta avanzada, sellado/exportación de evidencia, verificación integral de cadena y operación completa de retención continúan en los PBI posteriores que completan CU-MVP-25, incluido BL-MVP-090.

No modifica el SQL maestro ni la migración inicial y no agrega una segunda fuente canónica.
