# FIX-MVP-EDITORIAL-CRUD-DESKTOP-001

## Objetivo

Cerrar el hueco de gestión descubierto al intentar publicar una canción real: cada pestaña del
workspace de canción debe explicar y exponer su ciclo de creación, lectura, corrección y retiro,
sin convertir `DELETE` físico en un atajo que rompa el historial.

## CRUD editorial seguro

En entidades versionadas:

- **C**: crear DRAFT o nueva revisión.
- **R**: consultar estado, estructura e historial.
- **U**: editar DRAFT cuando el modelo lo permite o crear una nueva revisión correctiva.
- **D**: retirar, archivar, sustituir o dejar de seleccionar; nunca borrar una revisión publicada,
  evidencia, intentos o trazabilidad.

El workspace muestra este contrato de forma consistente en UI-MVP-019..026.

## Corrección de ejercicios

BL-MVP-071 ya permitía que `learning.save_fill_blank_exercise_draft(...)` actualizara la revisión
DRAFT de una definición existente, pero UI-MVP-025 no ofrecía forma de abrir esa revisión.
El fix:

1. añade `Editar borrador` / `Corregir como nueva revisión` al banco;
2. precarga línea, token, competencia, distractores, explicación, feedback y dificultad;
3. conserva la regla `If-Match` sobre la letra DRAFT exacta;
4. reutiliza la identidad estable del ejercicio cuando línea + competencia coinciden;
5. si la última revisión ya no es DRAFT, la función existente crea la siguiente revisión;
6. registra procedencia `EXERCISE_REVISION` para que BL-MVP-079 pueda validar el ejercicio.

No se elimina ninguna revisión de ejercicio.

## Integración de procedencia

La función de escritura M08 crea, cuando falta:

- `catalog.source_reference` con tipo `EDITORIAL_AUTHORING`;
- `editorial.provenance_record` con `object_type = EXERCISE_REVISION`;
- actor y timestamp de la operación.

Esto corrige el bloqueo visible:
`La revisión de ejercicio no conserva procedencia editorial.`

## Escritorio

El shell público mantiene su ancho de lectura. El backoffice, en cambio, deja de heredar el
`max-width` de lectura de `.route-surface` y usa el ancho disponible de la columna principal.

En escritorio:

- workspace y route surface usan `width: 100%` y `max-width: none`;
- párrafos introductorios conservan ancho de lectura;
- las ocho pestañas usan una grilla adaptable;
- el CRUD seguro usa cuatro columnas cuando hay espacio;
- las pantallas existentes pueden aprovechar sus grids internos de 2/3 columnas.

En móvil se conserva el reflow de una columna y el objetivo de 320 px sin overflow global.

## Validación

- verifier estático del fix;
- TypeScript / build;
- E2E de edición de ejercicio existente;
- Axe;
- 320 px sin overflow;
- escritorio 1536 px usando de forma efectiva la columna disponible;
- regresión completa.
