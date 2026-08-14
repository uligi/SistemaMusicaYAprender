# BL-MVP-064 · modelo de revisiones de análisis lingüístico

## Alcance

BL-MVP-064 materializa el modelo de lectura de M05 para una revisión japonesa
exacta. No crea un editor: BL-MVP-067 es quien permitirá preparar y validar el
contenido. El objetivo de este incremento es que UI-MVP-024 pueda demostrar que
lecturas, sentidos, morfología, gramática y procedencia pertenecen a una única
revisión compatible.

Endpoint:

`GET /api/v1/editorial/song-drafts/{recordingId}/analysis-context?language=es`

Permisos visibles y de servidor:

- `EDITORIAL.DRAFT` o `EDITORIAL.REVIEW`;
- módulo de autorización `M05`;
- acción auditada `EDITORIAL.ANALYSIS.READ`.

## Revisión fuente exacta

El servicio resuelve primero la última `content.lyrics_revision` de la grabación.
Las líneas y tokens se obtienen desde M03 y no se copian como texto editable de
M05.

El análisis compatible es exclusivamente la última
`content.linguistic_analysis_revision` cuyo `lyrics_revision_id` coincide con
esa fuente. Si solo existen análisis de revisiones japonesas anteriores:

- `hasStaleRevision=true`;
- `revision=null`;
- UI-MVP-024 muestra que la fuente cambió;
- no se mezclan anotaciones antiguas con tokens nuevos.

## Contención de revisión

Las consultas de:

- `content.token_reading`;
- `content.vocabulary_occurrence`;
- `content.morphology_annotation`;

vuelven a unir `lyric_token -> lyric_line -> lyric_section` y exigen
`lyric_section.lyrics_revision_id = @lyrics_revision_id`.

`content.grammar_occurrence` exige lo mismo para `line_id`. Si declara
`start_token_id`/`end_token_id`, ambos deben resolver a la misma línea y revisión
japonesa. Una FK física válida por sí sola no se interpreta como compatibilidad
editorial.

## Sentidos y explicaciones localizadas

`vocabulary_occurrence` selecciona una `vocabulary_entry` estable. Sus
`vocabulary_sense` localizados se leen para el idioma solicitado, inicialmente
`es`. De igual forma, cada `grammar_occurrence` resuelve la última
`grammar_explanation` disponible para el idioma solicitado.

Estas definiciones y explicaciones son ayudas educativas de M05: no sustituyen
la traducción de M04.

## Cobertura

La respuesta separa la cobertura por categoría:

- tokens con lectura;
- tokens con vocabulario/sentido;
- tokens con morfología;
- líneas con gramática.

Una categoría no implica la cobertura de otra y el análisis parcial permanece
explícito.

## Procedencia

La procedencia de una revisión se consulta mediante
`editorial.provenance_record` con:

`object_type = LINGUISTIC_ANALYSIS_REVISION`

y `object_id = analysis_revision_id`, enlazada a
`catalog.source_reference`.

BL-MVP-064 no inventa autoría a partir de la sesión ni convierte ausencia de
procedencia en una fuente implícita.

## Exclusiones

Este BL:

- no modifica tokens ni letra japonesa;
- no crea una segunda copia del japonés;
- no escribe análisis;
- no publica;
- no llama APIs externas de análisis, diccionario, traducción o transcripción;
- no implementa furigana/romaji contextual de BL-MVP-065;
- no administra vocabulario, kanji o gramática de BL-MVP-066;
- no implementa el editor de BL-MVP-067.

## UI-MVP-024

La pantalla es deliberadamente de lectura y usa divulgación progresiva:

- contexto de revisión fuente;
- cobertura diferenciada;
- líneas japonesas y tokens canónicos;
- detalle por token para lectura, sentido y morfología;
- gramática por línea;
- procedencia plegable.

La superficie mantiene `lang="ja"` para japonés y no depende de color para
expresar estados. El E2E cubre Axe y 320 CSS px sin scroll horizontal.
