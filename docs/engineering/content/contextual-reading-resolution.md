# BL-MVP-065 · Resolución local de lecturas, furigana y romaji

## Objetivo

BL-MVP-065 resuelve ayudas de lectura sobre el análisis versionado de M05 sin
convertirlas en una fuente paralela de japonés ni invocar servicios lingüísticos
externos.

El resultado aceptable del backlog es:

> Las ayudas son editoriales/locales, versionadas y no envían texto a servicios
> externos; casos ambiguos permanecen explícitos.

La fuente continúa siendo `content.lyric_token` de la revisión M03 exacta. Las
lecturas provienen de `content.token_reading` y permanecen ligadas a
`content.linguistic_analysis_revision`.

## Alcance de este incremento

Este BL no crea todavía el editor completo de M05. BL-MVP-067 es responsable del
espacio editorial de autoría, validación integral de cobertura, huérfanos y
previsualización del paquete.

BL065 materializa un resolver reutilizable y una previsualización real en
UI-MVP-024:

- muestra lectura contextual aprobada;
- usa `furigana` editorial cuando existe;
- interpreta la notación editorial `漢字[かんじ]` como `ruby/rt`;
- evita furigana redundante en tokens solo-kana;
- distingue texto originalmente latino;
- si no existe alineación de furigana suficiente, muestra `Pendiente de
alineación` en lugar de inventarla;
- genera romaji únicamente desde `reading_kana`, nunca desde el kanji;
- una columna `romaji` ya guardada prevalece como excepción editorial;
- conserva todas las lecturas de un token y marca la ambigüedad;
- no elige automáticamente una alternativa ambigua;
- expone `READING.LOCAL.V1` como versión del resolver de presentación.

## Romanización local

La implementación inicial usa un perfil Hepburn modificado local y determinista.
Incluye hiragana/katakana, yōon, sokuon, `ん` antes de vocal/y, chōonpu y
combinaciones frecuentes de préstamos.

El resolver no afirma que una transliteración generada sea una lectura. Primero
debe existir una `reading_kana` editorial en la revisión compatible. La regla
evita derivar pronunciación directamente de los kanji.

## Ambigüedad

`content.token_reading` admite más de una fila por token/revisión cuando
`reading_type` es distinto. BL065 conserva todas las filas y las ordena de forma
determinista (`PRIMARY`, `CONTEXTUAL`, resto). Dos o más filas producen el estado
textual `Lectura ambigua · N alternativas`.

No se destruye ninguna alternativa para fabricar una única respuesta.

## Independencia externa

`ContextualReading.tsx` es una función de presentación pura sobre datos ya
entregados por la API propia. No usa `fetch`, XHR, SDK, diccionario, traductor,
transcriptor ni servicio de análisis externo.

YouTube continúa siendo la única dependencia externa permitida del MVP y no
participa en la resolución lingüística.

## Accesibilidad

- japonés conserva `lang="ja"`;
- furigana estructurado usa `ruby`, `rt` y `rp`;
- ambigüedad y origen del romaji se comunican con texto;
- el componente refluye a una columna a 320 CSS px;
- no mueve foco ni crea anuncios continuos;
- la ausencia de ayuda se expresa como estado, no como cadena fabricada.

## Límites posteriores

- BL-MVP-063 consumirá estas ayudas en las capas del reproductor.
- BL-MVP-066 ampliará vocabulario, kanji y gramática contextual.
- BL-MVP-067 materializará la autoría integral de análisis.
- BL-MVP-068 llevará el análisis contextual al panel del estudiante.
