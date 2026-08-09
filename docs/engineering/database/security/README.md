# Seguridad PostgreSQL — BL-MVP-012/013

## Identidades y mínimo privilegio — BL-MVP-012

BL-MVP-012 implementa la separación entre identidad de autenticación (`LOGIN`) y rol de permisos (`NOLOGIN`).

La línea base física ya define los grants de `jp_app`, `jp_backoffice`, `jp_worker` y `jp_readonly`.
Los grants no se duplican sobre usuarios LOGIN: cada identidad recibe exactamente un membership.

```text
jp_login_migrator -> jp_migrator -> jp_owner
jp_login_api -> jp_app
jp_login_backoffice -> jp_backoffice
jp_login_worker -> jp_worker
jp_login_readonly -> jp_readonly
```

La API no recibe ni `jp_migrator` ni `jp_owner`.

`DatabaseMigrator` se ejecuta con `jp_login_migrator`. `jp_migrator` recibe `CREATE` únicamente
sobre `public` para administrar `__EFMigrationsHistory`; el DDL físico usa `SET LOCAL ROLE jp_owner`
para crear/poseer los nueve schemas.

API y Worker siguen sin ejecutar `Database.Migrate()` al arrancar.

Evidencia BL-MVP-012:

- `database/postgresql/security/access-matrix.json`
- `database/postgresql/tests/verify_login_identities.sql`
- `tools/DatabaseAccessVerifier`
- `scripts/database/verify-database-access.ps1`
- `scripts/ci/database/verify-database-access.sh`

## Contexto transaccional RLS — BL-MVP-013

Las políticas de `jp_app` ya usan `security.current_account_id()`, que lee `app.account_id`.
BL-MVP-013 formaliza el contrato de contexto para cada operación personal:

```text
app.account_id
app.role_code
app.correlation_id
```

Los valores se aplican con `set_config(..., true)`, equivalente transaccional a `SET LOCAL`.
La elección evita interpolar valores en SQL y garantiza que el contexto no sobreviva a `COMMIT` o `ROLLBACK`.

Componentes:

- `DatabaseSessionContext`: validación fail-closed de cuenta, rol y correlación.
- `RlsTransactionContext`: aplicación parametrizada de los tres settings.
- `RlsTransactionExecutor`: conexión + transacción + contexto antes de la operación.
- `HttpDatabaseSessionContextFactory`: puente desde identidad HTTP/correlación hacia el contrato DB.
- `DatabaseContextVerifier`: pruebas reales con `jp_login_api` y pool de una conexión.

Evidencia BL-MVP-013:

- `database/postgresql/tests/rls/prepare_transaction_context_fixture.sql`
- `database/postgresql/tests/rls/cleanup_transaction_context_fixture.sql`
- `tools/DatabaseContextVerifier`
- `scripts/database/verify-transaction-context.ps1`
- `scripts/ci/database/verify-transaction-context.sh`
- `artifacts/postgres/transaction-context-summary.txt` en CI

Las pruebas demuestran denegación de lectura/escritura entre dos cuentas y limpieza del contexto
al reutilizar exactamente la misma sesión PostgreSQL, tanto después de commit como de rollback.
