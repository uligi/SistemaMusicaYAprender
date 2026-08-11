# BL-MVP-030 — permisos efectivos, alcance y vigencia

BL-MVP-030 introduce la decisión de autorización de aplicación que complementa RLS.

## Autoridad

La cookie solo acredita una sesión revocable. No conserva roles efectivos como autoridad. En cada
operación protegida el servidor vuelve a consultar PostgreSQL.

Una cuenta `ACTIVE` y verificada conserva el rol base `STUDENT`. Los roles elevados proceden
exclusivamente de `security.role_assignment` vigente. BL-MVP-030 no ofrece una operación para crear,
editar o revocar esas asignaciones; esa administración pertenece a BL-MVP-031.

## Permiso efectivo

El motor combina:

1. cuenta activa y verificada;
2. rol `ACTIVE`;
3. asignación vigente cuando el rol no es el baseline `STUDENT`;
4. `security.role_permission` vigente;
5. permiso estable exacto;
6. ámbito aplicable.

No hay caché de decisiones. Una asignación que aparece, vence o se retira se refleja en la siguiente
operación sin exigir relogin.

La ausencia de coincidencia produce `NO_VALID_GRANT`. Un error de PostgreSQL no concede acceso.

## Ámbitos

`role_assignment.scope_id IS NULL` representa alcance global.

Los ámbitos tipados admitidos por el motor son:

- `GLOBAL`;
- `MODULE`, con `module_code`;
- `OBJECT`, con `object_id` y `module_code` opcional.

No se evalúa `definition` como lenguaje o expresión ejecutable. Un tipo desconocido o una forma
incoherente se deniega.

Jerarquía:

- global puede satisfacer global, módulo u objeto;
- módulo solo satisface su módulo y objetos dentro de él;
- objeto solo satisface el objeto exacto;
- un ámbito más estrecho nunca satisface una operación global.

## Interfaz

`GET /api/v1/auth/session` devuelve roles y `capabilities` recalculados para ayudar a la interfaz a
decidir qué enlaces mostrar. Esa lista puede sobreaproximar un permiso que existe solo en cierto
ámbito; por diseño no constituye autorización.

Las rutas de la interfaz usan los `permission_code` canónicos del servidor, no alias locales.

`GET /api/v1/security/authorization/catalog` es la primera consulta de servidor protegida por el
nuevo gate y exige `SECURITY.MANAGE_ROLES` con alcance global. Una asignación ADMIN limitada a
`MODULE=EDITORIAL` puede hacer visible la capacidad en la sesión, pero la consulta sigue recibiendo 403. Esto demuestra que ocultar o mostrar enlaces no sustituye la decisión server-side.

## Límites

No pertenece a BL-MVP-030:

- asignar/revocar roles o permisos: BL-MVP-031;
- MFA/reautenticación privilegiada: BL-MVP-032;
- auditoría primaria completa con sujeto/acción/objeto: BL-MVP-033;
- cambiar la matriz seed de roles/permisos;
- añadir un bypass ADMIN;
- desactivar RLS o ampliar privilegios de base.

RLS continúa aislando filas; autorización de caso de uso y alcance sigue siendo una capa adicional.
