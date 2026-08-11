# Administración de asignaciones de rol — BL-MVP-031

BL-MVP-031 implementa la administración de `security.role_assignment` sobre el motor de permisos
efectivos de BL-MVP-030.

## Reglas vinculantes

- Todas las rutas requieren `SECURITY.MANAGE_ROLES` con alcance global.
- El permiso se vuelve a comprobar dentro de la misma transacción privilegiada que modifica la
  asignación.
- El proceso normal de la API continúa usando `jp_login_api`/`jp_app`; únicamente la operación de
  administración abre el pool separado `jp_login_backoffice`.
- La credencial backoffice permanece en `/run/secrets/postgres_backoffice_password`.
- No se permite modificar las propias asignaciones del actor.
- Una asignación creada por este flujo comienza en `CURRENT_TIMESTAMP`.
- `valid_to`, cuando existe, debe ser posterior al inicio y se interpreta con rango `[inicio, fin)`.
- Los solapes para la misma cuenta, rol y alcance se rechazan; la exclusión GiST física continúa
  siendo la autoridad ante concurrencia.
- Repetir exactamente un grant vigente devuelve la asignación existente en lugar de duplicarla.
- Retirar una asignación vigente fija `valid_to = CURRENT_TIMESTAMP`; no borra la fila.
- Grant y revoke insertan `security.audit_event` en la misma transacción con actor, rol usado,
  objeto, acción, digest antes/después, motivo, momento y correlación.
- BL-MVP-031 administra asignaciones de roles existentes. No crea roles personalizados ni edita
  directamente `role_permission`; esas ampliaciones no se infieren de esta historia.
- MFA/reautenticación privilegiada permanece en BL-MVP-032.

## API

- `GET /api/v1/security/role-assignments/catalog`
- `GET /api/v1/security/role-assignments/{accountId}`
- `POST /api/v1/security/role-assignments`
- `POST /api/v1/security/role-assignments/{assignmentId}/revoke`

Las mutaciones validan CSRF y la autorización servidor no depende de que la ruta sea visible en la UI.

## UI

`/administracion/roles` (`UI-MVP-029`) permite introducir un `account_id`, elegir un rol y un alcance
existentes, definir vencimiento opcional y registrar el motivo. La búsqueda por correo no se añade a
esta historia para evitar ampliar exposición de identidad.

## Evidencia

`scripts/ci/security/verify-role-assignments.sh` comprueba autorización real, grant, reintento
idempotente, solape rechazado, revoke, reintento de revoke, auditoría y bloqueo de autoasignación.
