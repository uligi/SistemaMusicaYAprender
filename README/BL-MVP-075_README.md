# BL-MVP-075 · Evaluar respuesta reproduciblemente

## Resultado aceptable

> El resultado deriva de versión/clave fijadas, conserva algoritmo/versión y no cambia al editar futuros borradores.

## Trazabilidad

- Fase: F4 · Práctica y evidencia.
- Épica: EP-10 · Sesiones, ejercicios y evidencia.
- Tipo: Historia.
- SP: 13.
- Dependencias: BL-MVP-070 y BL-MVP-074.
- CU-MVP-11; UI-MVP-013; CE-06 y CE-07.
- CA-MVP-061: resultado y retroalimentación reproducibles con versiones registradas.
- CA-MVP-062: una alternativa aceptada se decide por la regla publicada, no por comparación textual simplista.
- CA-MVP-063: una fuente o regla ausente deja un estado revisable y no confirma evidencia ni progreso.

## Implementación

La evaluación parte de `learning.answer_submission` confirmada y de la `exercise_revision_id` ya congelada en `learning.exercise_instance`. El evaluador lee `solution_spec.schemaVersion`, `answerModel` y `acceptedItemOrders`; convierte esos órdenes en identidades de `learning.exercise_item` de la revisión exacta y decide el resultado comparando identidad de item, nunca el texto presentado.

`learning.evaluation_result` conserva una sola evaluación por submission, `evaluator_version`, score, correct, marca UTC y `result_digest` SHA-256. Un advisory lock serializa reintentos; si ya existe un resultado, el servicio recomputa la misma clave determinista y solo lo reutiliza cuando versión, score, correct y digest coinciden.

## Frontera

BL-MVP-075 no crea `learning.learning_evidence`, no escribe `progress.*` y no recalifica resultados históricos. Una incompatibilidad se devuelve como conflicto revisable para que una corrección posterior use el flujo trazable correspondiente.
