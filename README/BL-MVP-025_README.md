# BL-MVP-025 — Verificar la cuenta mediante token de un uso

## Definición normativa

- Fase: F1 — Identidad, acceso y configuración.
- Épica: EP-03 — Identidad, seguridad y autorización.
- Tipo: Historia.
- Traza: `CU-MVP-02`; `UI-MVP-006`; `CE-01`, `CE-14`.
- Story Points: 5.
- Dependencias: BL-MVP-017, BL-MVP-023 y BL-MVP-024.
- Resultado: **una cuenta `PENDING` pasa a `ACTIVE` solo mediante un código íntegro, vigente y consumible una vez, conservando los consentimientos obligatorios vigentes.**

## Corte funcional

El registro de BL-MVP-024 crea en su misma transacción un desafío de 30 minutos y un mensaje de correo en el outbox. PostgreSQL conserva únicamente `SHA-256(token)`; el token firmado se deriva en memoria con una clave HMAC separada y el worker lo incorpora a la plantilla `PERSONAL_ACCOUNT_VERIFICATION:v1:es`. El payload durable de correo contiene UUID opacos, nunca destinatario ni token.

`POST /api/v1/auth/verify-account` valida firma, referencias, hash, caducidad, estado y las versiones actuales de términos y privacidad. El éxito bloquea cuenta y desafío, consume todos los códigos pendientes de esa cuenta, marca `ACTIVE`/`verified_at` y agrega `ACCOUNT_VERIFICATION:SUCCEEDED` en una transacción. Repetir el mismo código ya exitoso devuelve el mismo resultado sin una segunda activación.

`POST /api/v1/auth/verification/resend` exige `Idempotency-Key` y siempre responde `202` con el mismo contrato, exista o no una cuenta pendiente. Una función PostgreSQL `SECURITY DEFINER`, de lectura mínima, `search_path` fijo y sin privilegio `PUBLIC`, resuelve internamente el hash del correo sin abrir una política RLS global.

La ruta `/verificar-cuenta` requiere que el usuario escriba el código. No acepta token en query, fragmento o path, ni utiliza `localStorage`/`sessionStorage`. Incluye reenvío, foco de corrección, teclado, lector de pantalla y reflujo a 320 CSS px.

## Propiedades de seguridad

- clave `identity_verification_token_key` de 32 bytes, separada de las claves de correo;
- HMAC-SHA-256 autenticado y comparación en tiempo constante;
- persistencia exclusiva del hash SHA-256 del token;
- vencimiento a los 30 minutos según reloj PostgreSQL;
- respuestas genéricas para token inválido/vencido y para reenvío;
- activación y consumo atómicos bajo RLS;
- revalidación de `TERMS_OF_USE` y `PRIVACY_POLICY` vigentes;
- evento de seguridad append-only sin token, correo ni credencial; y
- logs y artefactos automatizados sin valores sensibles.

## Límites

- BL-MVP-026 implementará el inicio de sesión.
- BL-MVP-028 incorporará la credencial y Argon2id; no se mezcla con este incremento.
- BL-MVP-030 incorporará recuperación de contraseña.
- BL-MVP-033 completará la auditoría primaria.
- No se modifica el SQL maestro, la migración inicial ni sus hashes: `security.account_verification` y sus políticas ya pertenecen al modelo aprobado.

## Evidencia automatizada

- Unit: material firmado, roundtrip de IDs/hash y rechazo de manipulación.
- Playwright/axe: ingreso manual, teclado, foco de error, ausencia de URL/storage, respuesta genérica y 320 px.
- API/worker/SMTP/PostgreSQL: entrega real, activación, replay, token manipulado, caducidad, prerrequisito obsoleto y reenvío no enumerable/idempotente.
- Evidencia segura: `artifacts/postgres/account-verification-summary.txt`.

## Instalación

- Guía: `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-025.md`.
- Instalador: `scripts/apply-bl-mvp-025.ps1`.

El instalador no ejecuta `git add`, commit ni push. La historia queda preparada, no cerrada: el cierre requiere puerta local completa, revisión manual y CI remoto verde.
