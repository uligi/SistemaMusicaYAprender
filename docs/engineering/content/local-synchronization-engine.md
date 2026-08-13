# Motor local de sincronización — BL-MVP-059

## Alcance

BL-MVP-059 implementa el habilitador P0 que conecta la revisión temporal exacta de una publicación con el tiempo observable del adaptador YouTube de BL-MVP-058.

No crea tablas ni migraciones, no publica, no usa YouTube Data API y no descarga audio o video.

## Contrato publicado

`GET /api/v1/public/catalog/songs/{slug}/synchronization?territory=CR&language=es`

El backend revalida:

1. publicación ACTIVE y vigente;
2. disponibilidad PUBLIC vigente para territorio/idioma;
3. fuente YouTube exacta fijada por `published_package_projection`;
4. componente `TIMING` fijado por la publicación;
5. `timing_revision.source_id` igual a la fuente fijada;
6. componente `LYRICS` igual a `timing_revision.lyrics_revision_id`.

El DTO público no expone UUID, checksum ni `externalRef`. Si la publicación es elegible pero no posee `TIMING`, devuelve `available=false`, `maximumPrecision=NONE` y cero líneas.

## Índice local

`LocalSynchronizationEngine.ts` compila la línea de tiempo en memoria una vez:

- aplica `offsetMs`;
- ordena por inicio efectivo y orden canónico;
- conserva un vector `prefixMaximumEndMs` para manejar de forma segura solapamientos permitidos;
- usa búsqueda binaria para localizar la última línea iniciada;
- usa búsqueda binaria separada para tokens.

La resolución degrada:

`TOKEN -> LINE -> NONE`

Nunca activa una línea solo por cercanía. Un hueco temporal produce `NONE`; un hueco entre tokens dentro de una línea produce `LINE`.

## Eventos y umbrales

El hook integrado:

- lee `getCurrentTime()` inmediatamente tras eventos `ready/state`;
- por tanto, `seek`, pausa y reanudación confirmados no esperan al siguiente tick;
- mientras el estado es `playing`, actualiza cada 100 ms;
- mientras está `paused`, comprueba localmente cada 250 ms para detectar un seek incluso si el proveedor no emite un cambio de estado adicional;
- no mueve foco;
- usa `aria-live="off"` para que cada cambio de línea no sea anunciado obligatoriamente.

La periodicidad deja margen frente a:

- RNF-MVP-023: desfase p95 <= 250 ms y máximo <= 500 ms;
- RNF-MVP-024: resincronización p95 <= 300 ms.

BL-MVP-092 realizará la verificación de rendimiento/capacidad integral del candidato; BL059 deja pruebas deterministas de búsqueda, 100 operaciones y resincronización representativa.

## UI-MVP-009 y UI-MVP-022

- UI-MVP-009 obtiene la línea temporal publicada mediante el endpoint público y la conecta al adaptador BL058.
- UI-MVP-022 reutiliza el mismo motor con la revisión DRAFT que el editor está previsualizando; no consulta el endpoint público y no publica.

BL-MVP-060 construirá encima de esta señal el reproductor educativo/karaoke completo y las capas de lectura.

## Smoke de contrato

El smoke de contrato construye una canción pública canónica completa: artista
principal, obra, grabación, fuente, paquete, `package_component`, publicación,
`publication_component`, disponibilidad PUBLIC y proyección publicada. Antes de
consultar sincronización verifica que la ficha pública existente responda HTTP 200.

El harness también comprueba que el proceso API que acaba de iniciar siga vivo,
para no aceptar accidentalmente un listener viejo en el mismo puerto. Las respuestas
HTTP de BL059 se capturan con status/body y, en caso de error, se imprime `api.log`.

El cleanup de datos sintéticos usa `session_replication_role=replica` solo dentro
de la conexión superusuario del harness. Así puede retirar de forma determinista
el grafo de prueba sin que los guards append-only/versionados bloqueen el cleanup;
no altera el esquema ni la lógica funcional del producto.

## UX editorial BL-MVP-059E

La revisión visual real de UI-MVP-022 detectó que separar verticalmente video, línea y controles obligaba a hacer scroll constante. El editor queda corregido con un workspace de dos columnas en desktop/laptop: preview YouTube + seguimiento a la izquierda y edición contextual a la derecha. El preview permanece sticky mientras se trabaja.

El editor muestra una sola línea editable a la vez, ofrece selector y botones anterior/siguiente, usa la posición real expuesta por el controller BL058/BL059 para marcar inicio/fin, incorpora saltos de ±0,5 s y ±2 s, permite ir al inicio ya guardado y puede avanzar automáticamente a la siguiente línea al cerrar un intervalo. En móvil vuelve a una sola columna sin scroll horizontal.

Los controles de desplazamiento múltiple y offset siguen disponibles sin interferir con el flujo principal y el botón Guardar permanece visible en desktop. La UI no mueve el foco del teclado al cambiar la línea seleccionada.
