# BL-MVP-056 · Revisiones y segmentos de sincronización

Materializa UI-MVP-022 y los contratos de `content.timing_revision` / `content.timing_segment` sin crear una
migración ni adelantar el editor de línea de tiempo de BL057.

Cada combinación `lyrics_revision + source` posee su numeración de revisión independiente. El servicio serializa
la creación con un advisory lock, calcula checksum SHA-256 y devuelve la revisión vigente cuando un reintento
repite exactamente el mismo árbol temporal.

Los intervalos se guardan en milisegundos y se validan contra la duración confirmada de la fuente después de
aplicar `offset_ms`. Una fuente sin duración confirmada puede mostrarse en UI, pero no permite confirmar una nueva
revisión temporal.

El esquema físico P0 solo almacena `line_id` en `timing_segment`. Para conservar el requisito de precisión por
línea/token sin inventar columnas ni tablas:

- una línea con un único segmento representa precisión de línea;
- una línea con sincronización detallada genera un segmento ordenado por cada token canónico;
- en precisión TOKEN se exige cobertura completa y el mismo orden de `content.lyric_token`;
- al leer, los segmentos ordenados de la línea se vuelven a asociar con sus tokens canónicos;
- si una línea tiene un único token, su único intervalo satisface simultáneamente línea y token.

Los solapamientos entre líneas se aceptan únicamente cuando ambas tienen etiquetas de voz no vacías y distintas,
que es la justificación persistida disponible para interpretación simultánea. Dentro de una misma línea los tokens
no pueden solaparse.
