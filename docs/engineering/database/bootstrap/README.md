# Bootstrap PostgreSQL — BL-MVP-010

BL-MVP-010 integra la primera parte de la línea base física: roles de base y extensiones autorizadas.

## Extensiones

Solo se instalan en este incremento:

- `pg_trgm`
- `btree_gist`

Ambas se instalan en el esquema `public`.

## Roles base

Se crean seis roles `NOLOGIN`:

- `jp_owner`
- `jp_migrator`
- `jp_app`
- `jp_backoffice`
- `jp_worker`
- `jp_readonly`

Todos se crean sin superusuario, sin `CREATEDB`, sin `CREATEROLE`, sin replicación y sin `BYPASSRLS`.

`jp_migrator` recibe membresía de `jp_owner`.

Los roles de runtime `jp_app`, `jp_backoffice`, `jp_worker` y `jp_readonly` reciben:

`search_path = pg_catalog, public`

Las identidades `LOGIN` y la separación efectiva de migración/aplicación/solo lectura se implementan en BL-MVP-012.

## Privilegios públicos

El bootstrap ejecuta:

`REVOKE CREATE ON SCHEMA public FROM PUBLIC`

No se agregan privilegios adicionales fuera de la línea base física aprobada.

## Reproducibilidad

El mismo SQL sirve para dos escenarios:

1. **Base nueva:** Docker monta el archivo en `/docker-entrypoint-initdb.d/` y PostgreSQL lo ejecuta durante la creación inicial.
2. **Base existente:** `scripts/database/apply-bootstrap.ps1` lo ejecuta explícitamente con la identidad DBA local.

El archivo es idempotente. La verificación lo ejecuta nuevamente y confirma que el estado permanece correcto.

## Evidencia

`database/postgresql/tests/verify_bootstrap.sql` comprueba:

- exactamente los seis roles esperados;
- propiedades `NOLOGIN` y ausencia de privilegios administrativos;
- membresía `jp_migrator -> jp_owner`;
- `pg_trgm` y `btree_gist` instaladas en `public`;
- ausencia de `CREATE` para `PUBLIC` en el esquema `public`;
- `search_path` esperado en los cuatro roles de runtime.
