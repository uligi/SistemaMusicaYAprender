# BL-MVP-067 · Espacio editorial de análisis lingüístico

## Objetivo

BL-MVP-067 convierte UI-MVP-024 en un espacio de trabajo editorial real para preparar el análisis japonés sobre la revisión M03 vigente.

Resultado aceptable:

> El editor valida cobertura, anclas y procedencia, detecta huérfanos y previsualiza exactamente el paquete.

## Experiencia task-first

La interfaz evita exponer el modelo físico como un formulario técnico. El recorrido visible tiene tres pasos:

1. **Elige una línea y una palabra.**
2. **Completa solo lo que conozcas.**
3. **Revisa y guarda.**

El análisis parcial es válido. Lectura, vocabulario, morfología, kanji y gramática son categorías independientes. UUID, checksum y códigos internos no dominan la experiencia; el checksum queda dentro de detalles técnicos.

La letra japonesa permanece bloqueada y los controles principales tienen objetivo táctil de al menos 44 CSS px. A 320 CSS px la composición refluye a una columna.

## Validación exacta

`POST .../analysis-revisions/validate` no escribe. Recibe el mismo snapshot que se guardaría y devuelve cobertura, errores/advertencias, huérfanos, procedencia, checksum y `canSave`.

El servidor comprueba:

- `If-Match` contra la letra + revisión de análisis vigente;
- pertenencia de token/línea a la revisión M03 exacta;
- duplicados;
- `char_offset` Unicode del kanji;
- lectura general y significado educativo del kanji como pareja completa;
- rango gramatical dentro de una misma línea y en orden;
- JSON de rasgos morfológicos;
- procedencia no vacía.

Cobertura parcial produce advertencia, no error.

## Guardado

`POST .../analysis-revisions` requiere `EDITORIAL.DRAFT`, CSRF e `If-Match`. El guardado obtiene lock transaccional, crea una nueva revisión `DRAFT`, enlaza `parent_revision_id`, usa checksum como idempotencia semántica y registra procedencia.

Las entradas estables de vocabulario, kanji y gramática se reutilizan cuando coinciden. Los metadatos versionados de `kanji_entry` y `grammar_point` se actualizan solo cuando cambian; los triggers físicos incrementan `version`. `vocabulary_sense` y `grammar_explanation` conservan historial editorial: una corrección diferente se agrega como la versión localizada más reciente. `kanji_reading`, cuya unicidad física es por kanji/lectura/tipo/idioma, actualiza su significado cuando la misma lectura es corregida y mantiene la lectura elegida como la más reciente para el editor.

La reapertura del editor toma el último `vocabulary_sense` por `display_order` y la última lectura de kanji por `display_order`, evitando que una corrección guardada reaparezca con un valor anterior. Las ocurrencias pertenecen siempre a la nueva revisión exacta.

## Independencia externa

No hay llamadas a diccionarios, segmentadores, traductores ni modelos lingüísticos externos. La detección de kanji es local y solo identifica caracteres que ya existen en el token; nunca inventa lectura ni significado.

## Publicación

BL-MVP-067 no publica. El guardado produce exclusivamente `DRAFT`.
