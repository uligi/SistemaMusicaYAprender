# BL-MVP-066 · Vocabulario, kanji y gramática contextual

BL-MVP-066 completa el read model M05 iniciado por BL-MVP-064 y las ayudas
locales de BL-MVP-065.

Resultado aceptable:

> Entradas estables y ocurrencias contextuales muestran lectura, sentido y
> explicación sin mezclar revisiones incompatibles.

## Frontera

Este incremento no crea el editor integral. BL-MVP-067 conserva la
responsabilidad de autoría, validación de cobertura, detección de huérfanos y
previsualización completa.

El modelo reutiliza las tablas físicas existentes:

- `vocabulary_entry` / `vocabulary_sense` como ficha reutilizable;
- `vocabulary_occurrence` como uso en un token;
- `kanji_entry` / `kanji_reading` como ficha reutilizable;
- `kanji_occurrence` como aparición y posición dentro de un token;
- `grammar_point` / `grammar_explanation` como concepto reutilizable;
- `grammar_occurrence` como aplicación en una línea o rango.

La forma superficial continúa procediendo de M03. M05 no conserva una copia
editable de la letra.

## Compatibilidad de revisión

La API solo presenta una revisión de análisis cuya `lyrics_revision_id` coincide
con la revisión japonesa vigente. Vocabulario, kanji y gramática se contienen de
nuevo mediante token/línea/sección de esa revisión.

Kanji añade un guard de `char_offset`: la posición de la ocurrencia debe
corresponder al carácter de la ficha estable dentro de `lyric_token.surface`.

Una revisión anterior queda stale y nunca se mezcla con tokens de la fuente
nueva.

## Lecturas y niveles

La pronunciación contextual sigue siendo `token_reading`. Las lecturas de
`kanji_reading` son datos generales de la ficha y no reemplazan automáticamente
la lectura contextual del token.

JLPT y grado se muestran como orientación educativa, nunca como certificación
oficial.

## Dependencias externas

No se invoca diccionario, traductor, segmentador, modelo lingüístico ni servicio
de análisis externo. YouTube permanece aislado al reproductor incrustado.

## Continuación

- BL-MVP-067: editor integral del análisis.
- BL-MVP-068: panel contextual del estudiante (UI-MVP-010).
- BL-MVP-069: read model del paquete educativo publicado.
