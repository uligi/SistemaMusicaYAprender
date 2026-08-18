# BL-MVP-071 · Autoría DRAFT de completar espacios

## Trazabilidad

- CU-MVP-19
- UI-MVP-025
- CE-06, CE-09, CE-13
- M08
- dependencias: BL-MVP-052 y BL-MVP-070

## Contrato de fuente

El editor no escribe la respuesta correcta. Selecciona `line_id` y `token_id` dentro de la revisión `content.lyrics_revision` DRAFT exacta. El servidor vuelve a resolver esa cadena antes de guardar.

## UX

El creador usa pasos cortos, lenguaje humano, selección visual de línea/token, validación inline y una vista previa interactiva. La vista previa se etiqueta como DRAFT y no persiste actividad de estudiante.

## Concurrencia

`GET /exercise-authoring-context` entrega ETag. `POST /fill-blank-exercise-drafts` exige `If-Match`; si la revisión DRAFT fuente cambió devuelve 412 y el frontend conserva lo escrito.

## Modelo guardado

- `learning.exercise_definition`: identidad estable `FILL_BLANK_OPTIONS`;
- `learning.exercise_revision`: prompt + `solution_spec` schemaVersion 1, estado DRAFT;
- `learning.exercise_item`: respuesta correcta en `item_order=1` y distractores posteriores;
- `acceptedItemOrders=[1]`.

## Mínimo privilegio

El pool `jp_backoffice` no recibe DML directo sobre `learning`. La función `learning.save_fill_blank_exercise_draft(...)` es la única capacidad de escritura añadida para este flujo y revalida actor, fuente, modalidad, opciones y estado DRAFT.

## Corrección integrada

FIX-MVP-EDITORIAL-CRUD-DESKTOP-001 completa la integración descubierta al usar el flujo real:

- UI-MVP-025 permite abrir una revisión existente y precargar el creador;
- una revisión DRAFT se corrige sin cambiar la identidad estable del ejercicio;
- una revisión no DRAFT genera una revisión posterior al guardar;
- cada revisión escrita conserva `EXERCISE_REVISION` en `editorial.provenance_record`;
- BL-MVP-079 puede validar la procedencia sin inventar datos en el paquete.

## Fuera de alcance

- publicación/revisión final del paquete;
- sesiones de estudio;
- instancias/answer submissions;
- evidencia/progreso;
- minijuegos, vidas, combos y puntuación;
- APIs lingüísticas externas.
