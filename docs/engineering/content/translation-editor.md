# BL-MVP-062 — editor de traducción al español

## Alcance

BL-MVP-062 materializa la escritura de UI-MVP-023 sobre el modelo M04 creado por
BL-MVP-061. El editor trabaja únicamente con una revisión japonesa exacta y guarda
nuevas revisiones `DRAFT`; no publica contenido y nunca actualiza la letra japonesa.

El idioma inicial es `es` y el tipo permitido por esta historia es `HUMAN`. El
modelo físico sigue siendo multilingüe mediante `target_language`.

## Contrato de lectura y concurrencia

`GET /api/v1/editorial/song-drafts/{recordingId}/translation-context?language=es&translationType=HUMAN`

devuelve el read model de BL-MVP-061 y un `ETag` de edición:

- `"translation-none"` si no existe letra japonesa;
- `"translation-{lyricsRevisionId}-none"` si existe fuente pero todavía no una traducción compatible;
- `"translation-{translationRevisionId}-r{revisionNo}"` para una revisión compatible.

`POST /api/v1/editorial/song-drafts/{recordingId}/translation-revisions` exige:

- capacidad efectiva `EDITORIAL.DRAFT` en M04 y ámbito de la grabación;
- cookie de sesión y antiforgery same-origin;
- `If-Match` con el ETag leído por el editor;
- `lyricsRevisionId` exacto;
- idioma `es`;
- tipo `HUMAN`;
- unidades identificadas por `lineId`;
- una unidad por cada línea de la revisión japonesa vigente, incluso cuando literal
  y natural estén vacíos;
- texto literal/natural y nota editorial separados.

El comando representa un snapshot completo de líneas fuente: una línea pendiente se
envía con sus variantes vacías, no se omite. El servidor rechaza un conjunto parcial
para impedir que una revisión nueva elimine silenciosamente traducciones o notas de
otras líneas.

El comando no contiene `japaneseText`. El servidor vuelve a resolver la fuente bajo
la misma transacción, toma un advisory lock de la grabación y devuelve `412` si
cambió la letra o la cabeza de traducción. El borrador local permanece en el
navegador para permitir comparación explícita.

## Versionado y persistencia

Cada guardado diferente crea una nueva `content.translation_revision` con:

- `status_code = DRAFT`;
- `parent_revision_id` hacia la revisión compatible anterior;
- `revision_no` creciente;
- checksum SHA-256 determinista del idioma, tipo, revisión fuente y campos del editor.

Un replay con el mismo checksum devuelve la cabeza vigente en vez de duplicarla.

Las variantes se guardan en `content.translation_line` como `LITERAL` y `NATURAL`.
Una variante vacía se omite, por lo que un borrador incompleto puede guardarse y el
read model sigue identificando exactamente las líneas pendientes.

## Alineaciones

BL-MVP-062 no inventa un nuevo modelo de alineación. Cuando existe una revisión
padre, las relaciones de `content.token_alignment` compatibles se copian hacia la
nueva revisión:

- la línea ancla debe pertenecer a la misma `lyrics_revision_id`;
- el token también debe pertenecer a esa revisión;
- si el texto de la variante no cambió, puede conservarse el tramo objetivo;
- si el texto cambió, se conserva la relación con el token pero el tramo
  `target_start/target_end` se degrada a `NULL` para no afirmar offsets obsoletos.

Así el editor no mezcla revisiones ni convierte una posición antigua en evidencia
actual sin revisión.

## Notas y autoría

Las notas editoriales de línea se editan separadas del texto traducido.
Notas protegidas de otros tipos se copian desde la revisión padre solo cuando sus
anclas siguen perteneciendo a la misma fuente japonesa.

Cada revisión escrita crea:

- `catalog.source_reference` de tipo `EDITORIAL`;
- `editorial.provenance_record` con `object_type = TRANSLATION_REVISION`;
- `contribution_type = TRANSLATION_AUTHOR`;
- `recorded_by` igual al actor autenticado.

La autoría no depende del nombre visible ni se mezcla con el texto.

## UI-MVP-023

La pantalla mantiene la vista estructural de BL-MVP-061 y agrega el editor solo
cuando la sesión publica capacidad visible `EDITORIAL.DRAFT`. La autorización real
se repite en el servidor.

La pantalla usa un flujo compacto de trabajo para evitar una lista vertical
innecesariamente larga:

- una barra sticky mantiene progreso y guardado visibles durante la edición;
- cada unidad coloca la fuente japonesa de solo lectura junto a literal/natural en
  escritorio y la apila en móvil;
- cada unidad expone estado textual `Completa`, `Parcial` o `Pendiente`;
- las notas editoriales son opcionales y permanecen plegadas cuando están vacías;
- la guía literal/natural se muestra una sola vez en lugar de repetirse por línea.

Por cada línea japonesa se mantienen:

- japonés de solo lectura con `lang="ja"`;
- textarea de español literal;
- textarea de español natural;
- textarea de nota editorial, disponible dentro del bloque plegable.

Los estados de guardado, conflicto, comparación y error tienen texto y semántica
propios; no dependen únicamente de color. En conflicto se puede cargar el estado
vigente. El rebase local solo se habilita si `lyricsRevisionId` sigue siendo el
mismo; si la fuente japonesa cambió, se exige revisar las unidades explícitamente.

## Exclusiones

BL-MVP-062 no:

- modifica la letra japonesa;
- publica o aprueba una revisión;
- sustituye el flujo posterior de revisión/publicación;
- envía texto a traductores, diccionarios o servicios lingüísticos externos;
- usa YouTube para traducir;
- convierte comentarios internos en contenido público.

## Organización visual de UI-MVP-023

La vista completa prioriza la tarea del traductor y aplica divulgación progresiva:

- el encabezado explica el objetivo en lenguaje de trabajo, no de modelo de datos;
- `Contexto de trabajo` resume revisión fuente, idioma, modo y revisión española;
- la letra japonesa completa queda en un bloque desplegable porque el editor ya presenta cada
  fuente junto a su traducción;
- el editor es la superficie primaria para sesiones con `EDITORIAL.DRAFT`;
- `Revisión, alineaciones y procedencia` queda colapsada durante edición y abierta en modo de
  lectura;
- checksum, N:M y procedencia siguen disponibles, pero no compiten visualmente con la edición;
- no se usan landmarks `aside` dentro de landmarks principales; las fuentes por unidad son
  agrupaciones visuales, evitando `landmark-complementary-is-top-level`.
