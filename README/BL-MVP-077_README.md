# BL-MVP-077 — Confirmar evidencia de aprendizaje append-only

## Ficha normativa

- Fase: F4 — Práctica y evidencia
- Épica: EP-10 — Sesiones, ejercicios y evidencia
- Tipo: Historia
- Traza: CU-11,12; UI-013-015; CE-07,11,14
- Story Points: 13
- Dependencias: BL015, BL075
- Base de implementación: `76770cb1e8f820816368358251bf2729438e049f`

Resultado aceptable exacto:

> Una evaluación válida produce una evidencia con linaje completo; reintentos no duplican y el registro no se reescribe.

## Decisiones

BL077 consume una `evaluation_result` ya persistida. La evidencia se deriva del linaje exacto
`evaluation -> submission -> instance -> exercise_revision -> exercise_definition`, toma la competencia
y la grabación del ejercicio congelado y usa el `score` evaluado como `outcome`.

La escritura es idempotente por `(evaluation_id, competency_id)`, se serializa con advisory lock y
nunca ejecuta UPDATE/DELETE sobre `learning.learning_evidence`. El trigger físico existente conserva
la política append-only y solo deja el enlace de sustitución para una corrección futura.

La misma transacción que inserta la evidencia encola exactamente un evento
`LEARNING.EVIDENCE.CONFIRMED` mediante `ITransactionalOutboxWriter` de BL015. Ese evento es la única
notificación destinada a la futura derivación de progreso. BL077 **no escribe `progress.*`**; BL083
mantiene esa responsabilidad.

No hay migración, cambio de grants ni cambio del SQL maestro: la tabla, FK, índice único, trigger,
RLS y permisos ya existen en la base física.

## API/UI

- GET privado `/api/v1/study/exercise-instances/{instanceId}/evidence` recupera evidencia existente.
- POST privado de la misma ruta recupera una confirmación pendiente con CSRF e idempotencia lógica.
- El POST de evaluación BL075 coordina la evidencia normal y devuelve su estado junto al resultado.
- La UI muestra confirmación textual; si una evaluación previa existe sin evidencia, ofrece
  `Confirmar evidencia` sin crear una segunda evaluación.
- No depende de color/audio y se cubre a 320 px con axe.

## Frontera

No implementa BL078, BL079, BL083 ni la corrección trazable CA-MVP-065. No publica ejercicios y no
fabrica datos públicos.
