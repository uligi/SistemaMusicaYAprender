# Obra, grabación y fuente de YouTube — BL-MVP-038

## Decisión de dominio

M02 mantiene tres identidades distintas:

- **obra**: composición musical canónica;
- **grabación**: interpretación/version concreta;
- **fuente**: referencia externa exacta usada para reproducir esa grabación.

El título, el nombre del artista y la URL visible no son claves.

## Persistencia existente

BL-MVP-038 usa sin migraciones nuevas:

- `catalog.musical_work`;
- `catalog.work_title`;
- `catalog.work_artist`;
- `catalog.recording`;
- `catalog.recording_source`;
- `catalog.recording_status_history`;
- `security.audit_event`.

El alta se confirma en una sola transacción. Si una escritura posterior falla, no quedan obra, grabación o fuente visibles de forma parcial.

## YouTube

La única integración de contenido externo permitida en runtime sigue siendo el reproductor IFrame. La administración del catálogo no consulta YouTube Data API.

El servidor normaliza localmente una URL admitida a un `external_ref` de video y persiste:

- `provider_code = YOUTUBE`;
- `external_ref`;
- duración conocida de la fuente, si existe;
- offset;
- estado y versión.

No persiste bytes audiovisuales.

### Correspondencia exacta

Sin una API externa autorizada, la identidad del video no prueba semánticamente qué grabación contiene. Por ello la operación exige una confirmación editorial explícita de correspondencia exacta y después enlaza la fuente mediante FK a la grabación concreta.

Esta confirmación es auditable y no habilita publicación. Derechos, procedencia y revisión continúan en BL-MVP-039/040 y M15.

## Duplicados

Dos reglas se aplican antes de crear:

1. `provider_code=YOUTUBE + external_ref` ya existente se trata como conflicto exacto;
2. título de obra parecido para el mismo artista produce advertencia mediante `pg_trgm`.

La segunda regla puede confirmarse para registrar una versión distinta. La primera no se ignora: el editor debe reutilizar o resolver la fuente existente.

Advisory locks transaccionales evitan que dos solicitudes concurrentes con distinta clave idempotente creen la misma fuente antes de observarse mutuamente.

## Idempotencia

Los UUID de obra, grabación, fuente, título inicial e historial inicial se derivan de:

- actor;
- operación estable;
- `Idempotency-Key`;
- clase del objeto.

El nombre y el título nunca participan como identidad primaria.

## Autorización

- crear/revisar duplicados: `EDITORIAL.DRAFT`, ámbito M02;
- leer UI-MVP-019: `EDITORIAL.DRAFT`, objetivo `recordingId` en M02.

El filtro de autorización del servidor registra la decisión antes de ejecutar el handler. La UI solo controla visibilidad y nunca sustituye esta autorización.

## Auditoría

La transacción de alta registra `security.audit_event`:

- `object_type = RECORDING`;
- `action_code = CATALOG.SONG_DRAFT.CREATE`;
- actor y rol efectivo;
- digest posterior del contrato normalizado;
- motivo;
- correlación.

## Estados

BL-MVP-038 crea obra, grabación y fuente en `DRAFT`. No crea una publicación ni una proyección pública.

El expediente UI-MVP-019 muestra explícitamente esos estados para evitar que una URL editorial conocida se interprete como contenido publicado.
