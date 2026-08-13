# Segmentación manual de tokens

BL-MVP-055 mantiene a `content.lyric_token` como la única identidad canónica de token del MVP.

## Rango y superficie

`start_offset` y `end_offset` son offsets UTF-16 `[inicio, fin)`. El frontend solo permite editar esos límites;
`surface` se calcula con `japaneseText.slice(inicio, fin)`. El servidor repite la comprobación con `Substring`,
rechaza solapamientos y, desde BL055, también rechaza límites que corten un par sustituto Unicode.

La normalización permanece separada en `normalized_surface`; nunca reemplaza `surface`.

## Agrupación

El SQL físico P0 no define `token_group`. BL055 no altera la línea base de 109 tablas para crear una entidad
adicional. Para M03, agrupar caracteres contiguos como una unidad se conserva mediante un único token cuyo rango
abarca exactamente esa superficie. El control `Unir con siguiente` convierte dos rangos adyacentes en ese rango
único.

Las agrupaciones semánticas entre varios tokens —por ejemplo una construcción gramatical— pertenecen a M05 y
pueden apoyarse en los anclajes de tokens aprobados, como `grammar_occurrence.start_token_id/end_token_id`.

## Impacto de corregir segmentación

Una revisión de letra puede ser fuente de:

- `content.timing_revision`;
- `content.translation_revision`;
- `content.linguistic_analysis_revision`.

El endpoint de impacto devuelve conteos sobre la revisión que se está corrigiendo. Si cambia la segmentación,
UI-MVP-021 avisa de esas relaciones; no las copia ni declara compatibles automáticamente con la nueva revisión.

## Concurrencia

BL055 reutiliza ETag/If-Match de BL054. El análisis de impacto es informativo; el guardado sigue creando una nueva
revisión DRAFT y una base obsoleta continúa devolviendo 412.

## Entrada multilínea

`lyric_line` representa una línea de interpretación ordenada. Si el usuario pega o introduce saltos de línea en
`Japonés original`, UI-MVP-021 distribuye el bloque en objetos de línea consecutivos en lugar de almacenar los
saltos dentro de un solo `japanese_text`. La primera línea conserva la etiqueta de voz existente; las líneas nuevas
nacen sin voz y sin tokens para evitar heredar anclas incorrectas. Los tokens de una línea cuyo texto cambia se
invalidan localmente y deben segmentarse de nuevo.
