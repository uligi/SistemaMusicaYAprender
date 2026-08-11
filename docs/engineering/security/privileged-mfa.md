# MFA y reautenticación privilegiada — BL-MVP-032

## Alcance

BL-MVP-032 añade un segundo factor TOTP y una verificación reforzada reciente para operaciones
administrativas. El permiso efectivo sigue siendo obligatorio: MFA no crea permisos y el permiso no
sustituye MFA.

La implementación reutiliza las estructuras físicas existentes `security.mfa_method`,
`security.session` y `ops.idempotency_record`; no crea una segunda fuente canónica de seguridad.

## Factor TOTP

El método P0 es TOTP de seis dígitos, periodo de 30 segundos y tolerancia técnica de una ventana
anterior o posterior. `GET /api/v1/security/mfa/policy` publica el catálogo permitido y la versión
`MFA-POLICY-1`, incluyendo assurance requerida, intentos y vigencia reciente.

La inscripción requiere sesión autenticada, reautenticación con contraseña actual, reto ligado a
cuenta/sesión/finalidad y a `MFA-POLICY-1`, con diez minutos de vigencia y confirmación
independiente con TOTP. Cada reto admite como máximo cinco intentos.

El secreto se muestra únicamente durante la inscripción. Antes de confirmar, PostgreSQL conserva
solo `SHA-256(secret)` como vínculo del reto. Después de confirmar, los bytes se almacenan con
`IObjectStore`, propietario `M18` y finalidad `MFA_TOTP_SECRET`. PostgreSQL conserva en
`security.mfa_method.secret_ref` una referencia opaca al descriptor cifrado, no el secreto.

## Step-up

Un actor con factor inscrito inicia un reto de cinco minutos ligado a la sesión y finalidad
`PRIVILEGED`. El reto se consume tras el éxito y no puede reutilizarse. El contador TOTP aceptado para
step-up también se reserva temporalmente para impedir usar de nuevo el mismo código.

Al confirmar, `security.session.assurance_level` pasa a `MFA` y se crea una aserción reciente por
sesión con vigencia máxima de 15 minutos. La sesión reforzada reduce además su límite de inactividad
a 15 minutos y su límite absoluto a ocho horas desde su creación.

El filtro `RequireRecentPrivilegedAssurance()` exige esa aserción en operaciones sensibles. Cuando
vence, la sesión no conserva privilegio por el mero hecho de haber usado MFA antes.

## Aplicación inicial

BL-MVP-032 aplica la puerta reforzada a la administración de asignaciones de roles. El futuro flujo
de auditoría protegida reutilizará el mismo filtro sin duplicar la lógica de MFA.

## Privacidad y mínimo privilegio

`jp_app` recibe DML únicamente sobre su propio `security.mfa_method`, protegido por RLS. No recibe
grants sobre asignaciones de roles. El secreto TOTP no se guarda en URL, `localStorage`,
configuración común ni PostgreSQL en claro. MinIO conserva el objeto cifrado conforme al contrato
privado ya existente.
