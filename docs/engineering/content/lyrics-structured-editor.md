# Editor estructurado de letra japonesa

BL-MVP-054 convierte UI-MVP-021 en un editor funcional conservando el modelo append-only de BL053.

## Estructura editable

Cada borrador contiene secciones ordenadas. Cada sección contiene líneas ordenadas y cada línea puede indicar
`speaker_label` para voz principal, coro, respuesta, personaje u otra etiqueta editorial. BL054 no crea todavía
tokens manuales: todos los `tokens` enviados por este editor están vacíos y BL055 se ocupa de esa segmentación.

## Contenido desconocido

RF-M03-010 exige representar lo inaudible o pendiente sin inventar texto. El esquema físico P0 no incluye una
columna separada para el tipo de contenido desconocido, por lo que BL054 reserva cuatro superficies editoriales
inequívocas:

- `[UNKNOWN:INAUDIBLE]`
- `[UNKNOWN:UNKNOWN]`
- `[UNKNOWN:OMITTED]`
- `[UNKNOWN:PENDING_TRANSCRIPTION]`

El navegador nunca pide al editor escribir esos marcadores manualmente: se selecciona una opción localizada. El
servidor acepta únicamente el conjunto cerrado y prohíbe tokens en una línea desconocida. La previsualización
presenta una etiqueta humana y no el código técnico.

## Concurrencia

GET de la revisión más reciente devuelve:

- `"lyrics-none"` cuando todavía no existe revisión;
- `"lyrics-{revisionId:N}-v{version}"` cuando existe.

POST exige `If-Match`. El servicio adquiere el mismo advisory lock por grabación usado por BL053, vuelve a leer la
revisión vigente y compara el ETag antes de crear la siguiente. Un desfase devuelve 412; no crea una revisión
silenciosa.

## Previsualización

La vista previa es exclusivamente local y no cambia estado editorial. `Guardar nueva revisión` crea un DRAFT; no hay
acción de publicación en UI-MVP-021.
