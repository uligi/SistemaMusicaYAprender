# Modelo editorial del banco de ejercicios · BL-MVP-070

## Decisión

M08 ya posee el modelo físico aprobado. BL070 no agrega migraciones: convierte ese modelo en un contrato de aplicación y una superficie editorial legible.

La identidad estable vive en `learning.exercise_definition`. La versión mutable/congelable vive en `learning.exercise_revision`. Los elementos ordenados viven en `learning.exercise_item`.

## Contrato `solution_spec` v1

Para el MVP, `exercise_revision.solution_spec` usa TypedMeta con esta forma mínima:

```json
{
  "schemaVersion": 1,
  "answerModel": "SINGLE_CHOICE",
  "acceptedItemOrders": [1],
  "explanation": "Explicación educativa.",
  "feedback": {
    "correct": "Retroalimentación positiva.",
    "incorrect": "Retroalimentación correctiva."
  },
  "difficulty": {
    "code": "BEGINNER",
    "justification": "Justificación editorial."
  }
}
```

Los valores visibles/opciones permanecen en `exercise_item`; la solución referencia el `item_order` conservado por la misma revisión.

## Contexto

`exercise_definition.line_id` apunta a la línea canónica. La lectura editorial une:

`exercise_definition -> lyric_line -> lyric_section -> lyrics_revision`

por lo que la revisión fuente no se infiere desde "latest".

## Procedencia

La procedencia no se duplica dentro del JSON. Se conserva como:

- `editorial.provenance_record.object_type = EXERCISE_REVISION`
- `object_id = exercise_revision_id`
- `catalog.source_reference` para cita, tipo y localizador.

## Seguridad

UI-MVP-025 requiere `EDITORIAL.DRAFT` con alcance M08. BL070 es read-only.

No se amplían grants sobre `learning`: `jp_backoffice` continúa con SELECT. Las escrituras acotadas de BL071 deberán diseñarse explícitamente y no mediante un `GRANT INSERT/UPDATE` general.

## Fuera de alcance

- crear o editar ejercicios;
- elegir huecos/distractores;
- validar ambigüedad;
- publicar;
- crear instancias de estudiante;
- responder/evaluar;
- minijuegos P2.
