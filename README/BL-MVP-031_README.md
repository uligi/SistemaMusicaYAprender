# BL-MVP-031 — Gestionar asignaciones de roles y permisos

## Historia

- Tipo: Historia
- Traza: CU-23; UI-029; CE-01,09,14
- SP: 8
- Dependencia: BL-MVP-030

Resultado aceptable:

> Un administrador autorizado asigna/revoca con motivo y vigencia; solapes inválidos se rechazan y
> todo cambio se audita.

## Implementación

La historia usa el motor efectivo de BL-MVP-030 y mantiene denegación predeterminada. Las operaciones
administrativas requieren `SECURITY.MANAGE_ROLES` global y se revalidan dentro de la transacción que
modifica `security.role_assignment`.

Para respetar mínimo privilegio, la API normal sigue conectada con `jp_login_api`/`jp_app`. Solo el
servicio de administración abre una conexión separada `jp_login_backoffice`, cuya credencial ya forma
parte del secret store y ahora se monta también en el contenedor API.

El grant:

- recibe cuenta objetivo, rol existente, alcance existente opcional, vencimiento opcional y motivo;
- inicia la vigencia con reloj PostgreSQL;
- rechaza autoasignación;
- rechaza cuenta no activa/verificada, rol inactivo, scope inexistente y vigencia inválida;
- devuelve el mismo registro ante un reintento exacto;
- rechaza solapes diferentes y conserva la exclusión GiST como barrera de concurrencia;
- inserta auditoría en la misma transacción.

El revoke no elimina la asignación: finaliza su vigencia y conserva un evento de auditoría con
before/after y motivo. Un segundo revoke es idempotente.

La pantalla `UI-MVP-029` deja de ser un placeholder en `/administracion/roles`.

## Límites

BL-MVP-031 no implementa MFA o reautenticación privilegiada; corresponde a BL-MVP-032. Tampoco crea
roles personalizados ni modifica el catálogo `role_permission`, ni implementa la consulta completa de
auditoría protegida de BL-MVP-033.

## Evidencia

El instalador ejecuta la puerta de calidad completa y después:

- regresión BL-MVP-030;
- smoke BL-MVP-031 con PostgreSQL real;
- grant/revoke;
- reintentos sin duplicar;
- solape rechazado;
- autoasignación bloqueada;
- dos eventos de auditoría para grant/revoke;
- vigencia retirada efectiva sin relogin.
