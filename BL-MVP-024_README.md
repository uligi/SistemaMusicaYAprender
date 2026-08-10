# BL-MVP-024 — Registrar consentimientos vigentes y versionados

## Definición normativa

- Fase: F1 — Identidad, acceso y configuración.
- Épica: EP-03 — Identidad, seguridad y autorización.
- Tipo: Historia.
- Traza: `CU-MVP-02`, `CU-MVP-04`; `UI-MVP-005`, `UI-MVP-008`; `CE-11`, `CE-14`.
- Story Points: 5.
- Dependencias: BL-MVP-023 y BL-MVP-035.
- Resultado: **la activación exige términos y privacidad vigentes; cada aceptación conserva versión, fecha, estado y actor.**

## Corte funcional

El registro publica y exige dos finalidades obligatorias:

- `TERMS_OF_USE`, versión `2026-08-10`;
- `PRIVACY_POLICY`, versión `2026-08-10`.

`GET /api/v1/auth/registration-consents` expone las versiones vigentes sin datos personales. `POST /api/v1/auth/register` acepta únicamente una decisión afirmativa y exacta por finalidad. Una aceptación ausente, duplicada, desconocida, negativa u obsoleta devuelve `400` y no crea cuenta.

Para una identidad nueva, cuenta `PENDING`, perfil mínimo y dos filas append-only de `identity.consent_record` se confirman en una sola transacción. El actor/sujeto es `account_id`; PostgreSQL asigna la fecha; el digest idempotente cubre correo, finalidades, versiones y decisiones. Replays y duplicados mantienen la respuesta pública no enumerativa y no duplican aceptaciones.

La ruta `/registro` obtiene el catálogo vigente antes de habilitar el envío, presenta dos controles independientes con versión visible, conserva foco y datos al corregir y funciona con teclado a 320 px.

## Límites

- BL-MVP-025 implementará el token de un uso y revalidará estos prerrequisitos al activar.
- BL-MVP-028 incorporará contraseña y Argon2id.
- BL-MVP-033 completará auditoría primaria.
- BL-MVP-036 incorporará administración mutable de versiones.
- El texto jurídico final requiere aprobación legal/editorial; BL-MVP-024 registra identificadores técnicos y no inventa cláusulas.
- La retirada de consentimientos opcionales en `UI-MVP-008` requiere sesión y queda para el incremento correspondiente; el modelo append-only ya admite decisiones posteriores sin reescritura.

## Evidencia automatizada

- Playwright/axe: catálogo, teclado, foco, consentimientos obligatorios, error asociado, reflujo a 320 px y respuesta genérica.
- API/PostgreSQL reales: dos versiones vigentes, atomicidad, dos evidencias, replay, duplicado, conflicto de digest y rechazos negativos.
- Inmutabilidad comprobada contra el trigger append-only.
- Evidencia: `artifacts/postgres/personal-registration-summary.txt`.

## Instalación

- Guía: `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-024.md`.
- Instalador: `scripts/apply-bl-mvp-024.ps1`.

El instalador no ejecuta `git add`, commit ni push. La historia solo queda lista para publicar después de la puerta completa, los siete servicios y la verificación real sin omisiones.
