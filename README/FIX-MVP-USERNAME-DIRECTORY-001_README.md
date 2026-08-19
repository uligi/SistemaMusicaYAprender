# FIX-MVP-USERNAME-DIRECTORY-001

Correctivo previo a BL-MVP-080.

Entrega:

- username estable y único en `identity.user_profile`;
- username obligatorio en el flujo web de registro y validado en API;
- claim único para cuentas existentes desde Preferencias;
- directorio administrativo por `@username`, sin correo;
- Roles y accesos deja de requerir UUID manual;
- revisores se muestran por `@username`;
- `account_id` continúa siendo la identidad técnica;
- permiso `SECURITY.MANAGE_ROLES` + MFA reciente se conservan;
- migración forward-only independiente de `InitialPhysicalSchema`.

No amplía el login para aceptar username y no permite renombrado ordinario.
