# BL-MVP-023 — Registrar una cuenta personal

## Definición normativa

- Fase: F1 — Identidad, acceso y configuración.
- Épica: EP-03 — Identidad, seguridad y autorización.
- Tipo: Historia.
- Traza: `CU-MVP-02`; `UI-MVP-005`; `CE-01`, `CE-11`, `CE-13`, `CE-14`.
- Story Points: 8.
- Dependencias: BL-MVP-011, BL-MVP-014, BL-MVP-019, BL-MVP-020 y BL-MVP-021.
- Resultado: **datos válidos crean una sola cuenta y perfil; duplicados/reintentos no enumeran ni duplican identidades.**

## Corte funcional

`POST /api/v1/auth/register` recibe únicamente el correo mínimo y exige `Idempotency-Key`. La operación:

1. normaliza el correo sin conservar una copia normalizada en claro;
2. calcula HMAC-SHA-256 para igualdad y cifra el valor canónico con AES-256-GCM;
3. reserva idempotencia anónima durante 24 horas;
4. crea atómicamente `security.account` en estado `PENDING` e `identity.user_profile` mínimo;
5. devuelve siempre `202 RECEIVED`, tanto para una cuenta nueva como para un correo ya registrado.

La ruta `/registro` reemplaza el placeholder por un formulario accesible de correo. Conserva la misma clave durante reintentos de una solicitud, muestra errores asociados al campo, funciona a 320 px y no solicita todavía una contraseña.

## Límites de la historia

- BL-MVP-024 registrará consentimientos vigentes y versionados.
- BL-MVP-025 creará y consumirá el desafío de verificación de un uso.
- BL-MVP-028 incorporará la credencial y la política Argon2id.
- BL-MVP-033 completará los eventos de seguridad y la auditoría primaria de F1.
- BL-MVP-034 ampliará el perfil mínimo y las preferencias iniciales seguras.

El estado `PENDING` no habilita inicio de sesión ni acciones protegidas. La respuesta pública no incluye correo, `account_id`, estado de coincidencia ni otra señal de existencia.

## Evidencia automatizada

- Playwright + axe para teclado, foco, reflujo a 320 px, error asociado y estado genérico confirmado.
- `scripts/ci/identity/verify-personal-registration.sh` contra PostgreSQL y el API real: alta cuenta/perfil, HMAC único, cifrado presente, replay, duplicado, conflicto de digest, errores 400 y protección física del correo.
- Puerta completa de calidad, inventario Git y revisión del diff antes de publicar.

## Instalación local en Windows

- Guía: `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-023.md`.
- Instalador y puerta local: `scripts/apply-bl-mvp-023.ps1`.
- Diagnóstico y correcciones recuperables: `scripts/repair-bl-mvp-023.ps1`.

El instalador no ejecuta `git add`, commit o push. BL-MVP-023 solo queda listo para publicación cuando la puerta local, los siete servicios y la prueba sintética contra API/PostgreSQL terminan sin omisiones.
