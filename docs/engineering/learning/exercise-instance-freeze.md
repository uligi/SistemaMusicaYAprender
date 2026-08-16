# Instancia congelada de ejercicio · BL-MVP-073

## Decisión

Una sesión de estudio no consulta “el último ejercicio” cada vez que se abre. La primera entrega crea una `exercise_instance` que referencia exactamente una `exercise_revision` incluida en la `publication` de la sesión.

Las opciones visibles se copian a `exercise_instance_item`. La semilla solo decide el orden durante la primera creación; desde ese momento `display_order` es la fuente de verdad para esa instancia.

## Privacidad y solución

El servidor necesita validar el origen editorial para construir el espacio, pero el contrato estudiante solo recibe:

- consigna;
- línea publicada con el token objetivo enmascarado;
- revisión numérica;
- opciones congeladas con identificadores privados de instancia;
- submission propia, si ya fue confirmada.

No se envían `solution_spec`, `expected_value`, metadatos `CORRECT`, explicación ni feedback.

## Reanudación

`(study_session_id, instance_no)` ya tiene unicidad física. Además, la creación toma un advisory lock por cuenta/sesión y primero busca la instancia `1`. Por eso doble activación y reapertura convergen al mismo `instance_id`.

## Frontera

No se escribe evaluación, evidencia ni progreso.
