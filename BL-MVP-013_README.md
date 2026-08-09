# BL-MVP-013 — Propagar contexto de cuenta, rol y correlación para RLS

## Resultado aceptable

> Cada transacción establece contexto seguro; pruebas demuestran denegación cruzada y limpieza al reutilizar conexiones.

## Diseño

La API dispone de un ejecutor transaccional único para operaciones protegidas por RLS:

- `app.account_id`
- `app.role_code`
- `app.correlation_id`

Los valores se escriben mediante `set_config(..., true)`, que tiene semántica local a la transacción equivalente a `SET LOCAL`, pero permite parametrizar los valores sin interpolar SQL.

`DatabaseSessionContext` valida los tres valores antes de abrir la operación. `RlsTransactionExecutor` abre la conexión, inicia la transacción, aplica el contexto y solo entonces ejecuta la operación.

El contexto desaparece al `COMMIT` o `ROLLBACK`; no se usa `SET` de sesión persistente.

## Integración HTTP

`HttpDatabaseSessionContextFactory` toma:

- cuenta: `account_id`, `ClaimTypes.NameIdentifier` o `sub`;
- rol activo: `active_role`, `ClaimTypes.Role` o `role`;
- correlación: `HttpContext.TraceIdentifier`, previamente normalizado por `CorrelationMiddleware`.

La autenticación completa se implementará en su backlog correspondiente. BL-MVP-013 deja el contrato fail-closed preparado para los endpoints que abran transacciones personales.

## Evidencia

`DatabaseContextVerifier` usa `jp_login_api`, pooling habilitado y `MaxPoolSize=1` para demostrar:

1. cuenta, rol y correlación existen dentro de la transacción;
2. los tres desaparecen después de `COMMIT` en la misma conexión física;
3. la cuenta A solo ve/modifica A;
4. la cuenta B solo ve/modifica B;
5. sin `app.account_id`, `jp_app` no ve las filas personales de prueba;
6. una conexión devuelta y prestada de nuevo no conserva el contexto anterior;
7. un `ROLLBACK` tampoco deja contexto residual;
8. valores de rol/correlación inseguros se rechazan antes de llegar a PostgreSQL.

Los fixtures son sintéticos, deterministas y se eliminan al terminar.

## Relación con BL-MVP-012

BL-MVP-013 no amplía grants, no entrega `jp_owner`/`jp_migrator` a runtime, no desactiva `FORCE RLS` y no usa `BYPASSRLS`.
