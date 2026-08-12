# BL-MVP-052 · Autoguardado y conflictos editoriales

Implementa el habilitador transversal de concurrencia editorial requerido por UI-MVP-019 a UI-MVP-026.

La primera integración observable se hace sobre los metadatos editables de la grabación en UI-MVP-019. El servidor
publica un ETag derivado de `catalog.recording.version` y `catalog.recording_source.version`; cada PUT exige `If-Match`
y actualiza con compare-and-swap. Un cliente con una versión anterior recibe 412 y nunca sobrescribe silenciosamente
la edición confirmada por otra sesión.

El frontend aporta un hook de autoguardado reutilizable y estados visibles `Guardando…`, `Guardado` y
`Conflicto de edición`. Ante conflicto conserva los cambios locales, recupera la versión vigente y obliga a comparar
antes de adoptar el servidor o reaplicar explícitamente los cambios locales sobre el nuevo ETag.

No crea tablas ni migraciones. Las pantallas editoriales futuras UI-MVP-021 a UI-MVP-026 deben reutilizar el contrato
en vez de inventar otra semántica de concurrencia.
