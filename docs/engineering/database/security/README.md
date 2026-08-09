# Identidades PostgreSQL y mínimo privilegio — BL-MVP-012

BL-MVP-012 implementa la separación entre identidad de autenticación (`LOGIN`) y rol de permisos (`NOLOGIN`).

La línea base física ya define los grants de `jp_app`, `jp_backoffice`, `jp_worker` y `jp_readonly`.
Este backlog no duplica esos grants sobre usuarios LOGIN: cada identidad recibe exactamente un membership.

## Cadena

```text
jp_login_migrator -> jp_migrator -> jp_owner
jp_login_api -> jp_app
jp_login_backoffice -> jp_backoffice
jp_login_worker -> jp_worker
jp_login_readonly -> jp_readonly
```

La API no recibe ni `jp_migrator` ni `jp_owner`.

## Migraciones

`DatabaseMigrator` se ejecuta con `jp_login_migrator`. `jp_migrator` recibe `CREATE` únicamente
sobre `public` para administrar `__EFMigrationsHistory`; el DDL físico usa `SET LOCAL ROLE jp_owner`
para crear/poseer los nueve schemas.

API y Worker siguen sin ejecutar `Database.Migrate()` al arrancar.

## Evidencia

- `database/postgresql/security/access-matrix.json`
- `database/postgresql/tests/verify_login_identities.sql`
- `tools/DatabaseAccessVerifier`
- `scripts/database/verify-database-access.ps1`
- `scripts/ci/database/verify-database-access.sh`

Las pruebas incluyen autenticación real con cada secreto, positivos permitidos y negativos de
SET ROLE, DDL y escritura readonly.
