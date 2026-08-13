# Modelo de revisiones y segmentos de sincronización

BL-MVP-056 utiliza exclusivamente las tablas físicas P0 `content.timing_revision` y `content.timing_segment`.

## Fuente y revisión exactas

Una revisión temporal pertenece simultáneamente a una `lyrics_revision` y una `recording_source`. Antes de crearla
se verifica que ambos objetos pertenezcan a la misma grabación. La numeración se calcula por combinación
`lyrics_revision_id + source_id`, de modo que dos videos o fuentes de la misma grabación nunca comparten
silenciosamente una revisión temporal.

## Milisegundos y duración

`start_ms`, `end_ms` y `offset_ms` son enteros en milisegundos. El servicio exige:

- `start_ms >= 0`;
- `end_ms > start_ms`;
- `start_ms + offset_ms >= 0`;
- `end_ms + offset_ms <= recording_source.duration_ms`.

Si la fuente no tiene duración confirmada, la UI puede mostrarla pero el backend rechaza confirmar una revisión.

## Línea y token sobre el esquema físico

El diseño físico P0 asocia `timing_segment` con `line_id`, no incorpora `token_id`. BL056 conserva la línea base
sin añadir columnas fuera del contrato y utiliza una representación determinista:

- precisión LINE: un segmento para la línea;
- precisión TOKEN: exactamente un segmento por token canónico de la línea, en el mismo orden;
- el `display_order` sigue siendo global dentro de la revisión;
- la lectura reconstruye el token asociado usando el orden estable de `lyric_token.token_no`.

No se permiten subconjuntos arbitrarios de tokens en una línea con precisión detallada. Así no existe una
asociación implícita ambigua. Una línea con un solo token tiene un único intervalo válido tanto como línea como
token.

## Solapamientos

Los tokens de una misma línea no se solapan. Dos líneas consecutivas pueden solaparse únicamente si ambas tienen
`speaker_label` no vacío y distinto, dato persistido que expresa voces simultáneas diferenciadas. De lo contrario,
el backend rechaza la revisión e identifica las líneas.

## Alcance del BL

UI-MVP-022 es una vista estructural y segura. BL056 no añade controles de marcado, drag, desplazamiento ni
previsualización audiovisual; esas operaciones corresponden a BL-MVP-057. Tampoco carga YouTube ni publica.
