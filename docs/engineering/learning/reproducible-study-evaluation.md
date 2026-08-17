# Evaluación reproducible de respuestas · BL-MVP-075

## Fuente de verdad

La submission confirmada, la instancia congelada y su `exercise_revision_id` son la cadena de autoridad. El evaluador no consulta “la última revisión” y no compara el texto visible para decidir si una opción es correcta.

Para `FILL_BLANK_OPTIONS` con `answerModel=SINGLE_CHOICE`, `solution_spec.acceptedItemOrders` representa la regla publicada. Cada orden aceptado se resuelve contra `learning.exercise_item` de la revisión congelada. Esto permite que una revisión futura admita más de una alternativa sin convertir una coincidencia textual en regla implícita.

## Clave determinista

`result_digest` se calcula con SHA-256 sobre material canónico formado por:

- `evaluator_version`;
- `submission_id`;
- `exercise_revision_id`;
- órdenes e identidades de items aceptados;
- identidad del item seleccionado;
- score y booleano correct.

El resultado se persiste una sola vez por `submission_id`. Un reintento toma advisory lock y valida en tiempo constante que el digest persistido coincide con el que deriva de la misma revisión congelada.

## Fallos seguros

Una regla JSON inválida, un `answerModel` incompatible, un orden aceptado que no existe o una respuesta que ya no pertenece a la revisión exacta impiden crear una evaluación. La API devuelve conflicto revisable y mantiene intacta la submission. No se crea evidencia ni progreso.
