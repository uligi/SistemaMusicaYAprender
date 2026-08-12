# Autoguardado y concurrencia editorial

BL-MVP-052 establece una semántica única para los borradores editoriales.

## Contrato HTTP

La lectura de un recurso editable devuelve `ETag`. Una mutación posterior exige exactamente ese valor mediante
`If-Match`. La ausencia de precondición devuelve 428. Una versión obsoleta devuelve 412 y conserva los datos locales
del cliente.

El ETag de la primera integración combina las versiones físicas de `catalog.recording` y
`catalog.recording_source`. El servicio bloquea filas durante la decisión y además mantiene el predicado
`WHERE version = @expected` en cada UPDATE. De este modo el mecanismo sigue siendo seguro incluso si en el futuro
cambia la estrategia de bloqueo.

## Experiencia

El hook `useEditorialAutosave` reserva tres estados P0 visibles:

- `Guardando…`;
- `Guardado`;
- `Conflicto de edición`.

El conflicto no dispara un reintento destructivo. La UI conserva la edición local, obtiene la versión vigente y muestra
una comparación. Solo una acción explícita permite adoptar el servidor o rebasar los cambios locales sobre el ETag
vigente.

## Extensión a UI-MVP-020–026

BL-MVP-052 no crea pantallas futuras ni revisiones ficticias. Los editores que aparezcan con BL-MVP-053–079 y el
paquete de BL-MVP-047 deben reutilizar esta misma semántica con la columna `version` de su objeto propietario o una
revisión inmutable apropiada.

## Persistencia

No hay migración nueva. `catalog.recording` y `catalog.recording_source` ya poseen `version` como control de
concurrencia. El smoke de BL052 demuestra que un segundo UPDATE con la versión anterior afecta cero filas.
