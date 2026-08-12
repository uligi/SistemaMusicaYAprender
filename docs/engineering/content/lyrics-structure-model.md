# Modelo editorial de letra japonesa

BL-MVP-053 materializa el árbol `lyrics_revision -> lyric_section -> lyric_line -> lyric_token` sin crear
tablas nuevas.

## Superficie y normalización

`japanese_text` y `surface` son la fuente editorial. Se guardan sin trim, transliteración ni reemplazo automático.
Las columnas `normalized_text` y `normalized_surface` se calculan por separado con NFC para búsqueda,
comparación y futuros analizadores. Un texto descompuesto como `か` + dakuten puede normalizarse a `が` sin
modificar el original.

## Identidad y orden

Los nombres y el texto nunca son claves. Revisión, sección, línea y token usan UUID opacos. El orden está en
`revision_no`, `display_order`, `line_no` y `token_no`.

Los offsets de token usan unidades UTF-16 para coincidir con `String` de .NET y JavaScript. Antes de insertar se
comprueba que cada token sea exactamente el substring indicado y que los intervalos no se solapen.

## Historial

Una corrección estructural puede crear una nueva revisión enlazada por `parent_revision_id`; no sobrescribe una
revisión anterior. El checksum SHA-256 resume el árbol canónico y también evita crear una revisión idéntica por
un reintento inmediato.

## Límites de este BL

BL053 no implementa aún edición interactiva, sincronización, traducción, análisis, ejercicios ni publicación.
UI-MVP-021 permite comprobar el modelo real y un estado vacío seguro. BL054 añadirá el editor reutilizando estas
identidades y las reglas de concurrencia de BL052.
