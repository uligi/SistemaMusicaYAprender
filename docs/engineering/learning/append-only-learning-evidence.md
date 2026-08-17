# Evidencia de aprendizaje append-only

BL-MVP-077 convierte una evaluación reproducible ya confirmada en un hecho educativo estable.

## Linaje

La fuente autoritativa parte de la instancia privada y sigue:

`exercise_instance -> study_session -> learner_profile`

`exercise_instance -> answer_submission -> evaluation_result`

`exercise_instance -> exercise_revision -> exercise_definition`

La evidencia persiste `learner_profile_id`, `evaluation_id`, `competency_id`, `recording_id`,
`outcome`, `evidence_version` y `confirmed_at`. La competencia y la grabación salen del ejercicio
exacto; además se valida que la grabación del ejercicio coincida con la sesión.

## Idempotencia y append-only

La operación toma un `pg_advisory_xact_lock` por cuenta/instancia y primero busca la combinación
lógica `(evaluation_id, competency_id)`, que además está protegida por el índice único físico.
Un replay devuelve el mismo `evidence_id` y valida que no haya deriva en linaje, outcome, versión o
`supported_by`/sustitución. El servicio no contiene UPDATE ni DELETE de la tabla de evidencia.

La corrección posterior no pertenece a BL077. El esquema ya reserva `superseded_by` y
`evidence_correction` para una sustitución trazable futura; esta historia no los activa.

## Notificación a progreso

La dependencia BL015 se usa de forma explícita: dentro de la **misma transacción** que confirma una
evidencia nueva se crea un `OutboxMessageDraft` con:

- event name: `LEARNING.EVIDENCE.CONFIRMED`
- schema version: `1`
- aggregate type: `LEARNING_EVIDENCE`
- aggregate id: `evidence_id`
- correlation id: `evidence_id`
- causation id: `evaluation_id`

El payload contiene solo identificadores educativos necesarios, outcome y versión. Al recuperar una
evidencia existente se exige exactamente una notificación de ese agregado; no se encola otra.

BL077 no consume el evento ni escribe tablas `progress.*`. BL083 podrá consumir esta notificación,
deduplicarla por inbox y derivar progreso una sola vez.

## Fallos

Sin evaluación válida no se confirma evidencia ni evento. Una discrepancia de linaje, versión o
notificación queda como conflicto revisable. Un fallo de almacenamiento devuelve un estado
recuperable: reintentar converge sobre la misma evidencia lógica.
