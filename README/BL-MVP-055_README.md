# BL-MVP-055 · Segmentación y corrección manual de tokens

Extiende UI-MVP-021 con segmentación manual sobre el texto japonés conservado por BL053/054.

Cada token se persiste únicamente como un rango `[start_offset, end_offset)` sobre `japanese_text`. La superficie
se deriva del substring exacto y el servidor vuelve a verificarla. Los offsets usan unidades UTF-16, compatibles
con `String` de .NET y JavaScript, y no pueden cortar un par sustituto.

El editor puede crear tokens por carácter, ajustar rangos y unir tokens contiguos. En el modelo físico P0 no existe
una tabla separada de grupos de tokens; por eso una agrupación editorial persistente en M03 se expresa mediante el
rango exacto del token resultante. Las agrupaciones semánticas de varios tokens que pertenezcan al análisis se
representarán después mediante los objetos de M05, sin inventar una tabla fuera de las 109 aprobadas.

Al cambiar la segmentación de una revisión existente, la UI consulta relaciones con sincronización, traducciones y
análisis. La nueva revisión no migra esos vínculos automáticamente y muestra una advertencia antes de guardar.

Al pegar o escribir un bloque con saltos de línea, cada salto crea una `lyric_line` independiente. El editor no permite que varias líneas interpretadas queden ocultas dentro de un solo `japanese_text`; así los tokens, tiempos, traducciones y análisis conservan anclas de línea correctas.
