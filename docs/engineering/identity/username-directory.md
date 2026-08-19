# FIX-MVP-USERNAME-DIRECTORY-001 — username y directorio administrativo

## Objetivo

Eliminar UUID y correo de los flujos humanos de administración sin cambiar la identidad técnica.

- `account_id` sigue siendo la PK/FK interna y el valor autorizado por servidor.
- `identity.user_profile.username` es el identificador humano estable.
- `display_name` permanece opcional y separado.
- el login continúa por correo en este correctivo.

## Reglas

`username` se normaliza a minúsculas, mide entre 3 y 32 caracteres y solo admite `a-z`,
`0-9`, `.`, `_` y `-`. Debe empezar y terminar con letra o número. El índice
`uq_identity_user_profile_username` impide duplicados de forma física.

Cuentas anteriores a la migración conservan `username = NULL` y pueden fijarlo una sola vez desde
Preferencias. Las cuentas nuevas lo eligen durante el registro.

## Privacidad

Roles y accesos usa un directorio mínimo protegido por `SECURITY.MANAGE_ROLES` y MFA reciente.
La respuesta contiene solamente:

- `accountId`;
- `username`;
- `displayName` opcional;
- estado de cuenta;
- roles vigentes.

No consulta ni expone `email_cipher`, `email_lookup_hash`, credenciales ni secretos MFA.

## Revisión editorial

El workflow de revisión continúa almacenando `reviewer_id = account_id`. La etiqueta visible se
resuelve desde `username`; si una cuenta heredada todavía no lo ha fijado, usa `display_name` o una
etiqueta neutra de compatibilidad.

Las restricciones de independencia no cambian: quien creó o sometió el paquete no puede actuar como
revisor independiente.

## Compatibilidad

La migración es forward-only y deja `username` nullable solo para permitir transición de cuentas
anteriores. No se modifica la migración física inicial.
