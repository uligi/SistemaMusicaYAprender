# BL-MVP-076 · Mostrar retroalimentación accesible y textual

## Resultado aceptable

> Resultado, explicación y siguiente acción existen como texto, no dependen de color/audio/temporizador y mantienen foco.

## Trazabilidad

- Fase: F4 · Práctica y evidencia.
- Épica: EP-10 · Sesiones, ejercicios y evidencia.
- Tipo: Historia.
- SP: 8.
- Dependencias: BL-MVP-019 y BL-MVP-075.
- CU-MVP-11; UI-MVP-013; CE-06 y CE-13.
- CA-MVP-066: acierto/error, explicación y siguiente acción siguen siendo comprensibles sin color ni audio.

## Implementación

`learning.feedback_item` persiste tres piezas textuales ordenadas para la evaluación exacta: resultado editorial (`RESULT.*`), explicación versionada (`EXPLANATION.RULE`) y siguiente acción (`NEXT_ACTION.CONTINUE`). La localización inicial es `es-CR` y las dos primeras piezas provienen del `solution_spec` de la revisión congelada.

UI-MVP-013 recupera una evaluación existente mediante GET privado `no-store`; si todavía no existe, ofrece una acción explícita protegida por CSRF para crear o reutilizar la evaluación. Cuando el resultado queda disponible, el foco se mueve al encabezado de corrección y el contenido se anuncia de forma semántica.

## Frontera

La retroalimentación no crea evidencia ni progreso. Esos hechos comienzan en BL-MVP-077 y posteriores.
