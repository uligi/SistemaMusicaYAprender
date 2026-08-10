# BL-MVP-015 — Outbox, inbox e idempotencia común

## Resultado aceptable

> Una decisión y su evento se confirman juntos; reintentos no duplican efectos y los fallos quedan observables.

## Trazabilidad

- DIS.
- OBS.
- RNF-MVP-031 — máximo 3 intentos, retroceso exponencial con jitter y 0 efectos duplicados.
- RNF-MVP-035 — 0 duplicados en 1.000 repeticiones por tipo de operación crítica.
- Modelo lógico — decisión canónica, idempotencia y outbox se confirman en una transacción; efecto e inbox se confirman juntos.

## Decisión de arquitectura

Los módulos **no comparten `DbContext`, repositorios genéricos ni entidades mutables**.

La infraestructura de confiabilidad usa puertos explícitos sobre la misma
`NpgsqlConnection`/`NpgsqlTransaction` que ya abre `RlsTransactionExecutor`:

- `ReliableOperationExecutor` reserva y finaliza la clave de idempotencia.
- El callback propietario realiza la decisión de negocio dentro de esa transacción.
- `TransactionalOutboxWriter` inserta los eventos devueltos por la decisión antes del `COMMIT`.
- Si la escritura del outbox falla, la decisión y la reserva idempotente hacen `ROLLBACK`.
- Un reintento con la misma clave y el mismo digest reutiliza la respuesta sin volver a ejecutar la decisión.
- La misma clave con un digest distinto se rechaza como conflicto.

La implementación no añade una migración ni modifica el SQL maestro de BL-MVP-011.

## Outbox e inbox

El worker reclama un evento mediante `FOR UPDATE SKIP LOCKED`.

Cada consumidor se ejecuta por `InboxConsumerExecutor`:

1. inserta `(consumer_code, event_id)` como `PROCESSING`;
2. ejecuta el efecto;
3. marca el inbox como `PROCESSED`;
4. todo ocurre dentro de la transacción del despacho.

Una entrega repetida encuentra la PK del inbox y no vuelve a ejecutar el efecto.

El dispatcher usa un `SAVEPOINT` alrededor de los efectos. Si un consumidor falla, revierte los
efectos de ese intento pero conserva el bloqueo del evento para registrar el fallo de forma atómica.

## Reintentos y observabilidad

Los estados del outbox usados por la infraestructura son:

- `PENDING`
- `RETRY_WAIT`
- `PROCESSED`
- `REVIEW`

Cada evento usa un `background_job` determinista con `job_id = event_id`. Cada intento terminado
produce un `job_attempt` append-only.

La política de reintento es:

- máximo 3 intentos;
- base exponencial de 1 s y 2 s entre los tres intentos;
- jitter determinista por evento/intento;
- después del tercer fallo el evento queda en `REVIEW`;
- el digest de error usa SHA-256 del tipo/código seguro, nunca del mensaje potencialmente sensible.

El worker no sondea el outbox mientras no exista ningún consumidor registrado. Esto evita consumir
eventos antes de que el módulo receptor esté disponible.

## Permisos

BL-MVP-015 no amplía grants:

- `jp_app` ya puede leer/insertar/actualizar `ops.idempotency_record` y `ops.outbox_message`.
- `jp_worker` ya posee DML sobre `ops`.
- ningún runtime recibe `jp_owner`, `jp_migrator`, `SUPERUSER` o `BYPASSRLS`.

## Evidencia reproducible

`scripts/database/verify-reliability.ps1` y su equivalente de CI verifican con PostgreSQL 18 real:

1. fallo al insertar el outbox revierte también la decisión y la reserva idempotente;
2. decisión + outbox + respuesta idempotente se confirman juntos;
3. 1.000 repeticiones de la misma clave producen 0 duplicados;
4. la misma clave con otro digest se rechaza;
5. una redelivery del mismo evento ejecuta el efecto una sola vez por el inbox;
6. los fallos generan 3 `job_attempt`, usan `RETRY_WAIT` y terminan en `REVIEW`;
7. no queda inbox parcial tras un intento fallido;
8. los errores se conservan como código y digest sin registrar payload ni mensaje sensible.
