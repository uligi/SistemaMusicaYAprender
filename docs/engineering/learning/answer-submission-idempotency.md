# Confirmación idempotente de respuesta · BL-MVP-074

## Decisión

La respuesta de completar espacios es una confirmación append-only formada por:

- `answer_submission`: identidad lógica, `submission_no = 1`, `Idempotency-Key`, estado, hora y digest;
- `answer_value`: referencia al `instance_item` seleccionado y `value_type = SELECTED_ITEM`.

La opción se valida contra la instancia privada antes de escribir.

## Concurrencia e idempotencia

La operación toma un advisory lock por cuenta/instancia. Después:

1. recupera una submission existente;
2. si el digest coincide, devuelve la misma entrega;
3. si la misma clave llega con digest distinto, devuelve conflicto;
4. si ya existe otra respuesta confirmada distinta, rechaza una segunda entrega;
5. si no existe, inserta submission + value y cambia la instancia a `RESPONDED` en la misma transacción.

Los índices físicos `ux_learning_answer_submission_01` y `02` siguen actuando como defensa de integridad.

## Frontera BL075

Guardar no equivale a evaluar. BL074 no lee la solución para decidir corrección y no crea `evaluation_result`, feedback, evidencia ni progreso.
