# BL-MVP-053 · Revisiones de letra, secciones, líneas y tokens

Implementa el modelo funcional de UI-MVP-021 sobre las tablas físicas ya existentes de M03.

El resultado conserva la superficie japonesa exacta en `japanese_text` y `surface`. La normalización NFC se
calcula en aplicación y se guarda únicamente en `normalized_text` y `normalized_surface`; nunca sustituye el
original. Secciones, líneas y tokens reciben UUID opacos y el orden se representa con columnas explícitas.

Cada nueva estructura crea una `lyrics_revision` con número creciente y `parent_revision_id`. El árbol recibe un
checksum SHA-256. Si el mismo árbol se reenvía inmediatamente, se devuelve la revisión vigente en lugar de crear
un duplicado.

UI-MVP-021 es deliberadamente de inspección en BL053. El editor estructurado pertenece a BL-MVP-054 y la
sincronización temporal a BL-MVP-056/057. BL053 no publica contenido.
