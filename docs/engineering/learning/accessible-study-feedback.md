# Retroalimentación textual y accesible · BL-MVP-076

## Persistencia

Cada evaluación posee tres `learning.feedback_item` append-only con `display_order` 0..2:

1. `RESULT.CORRECT` o `RESULT.INCORRECT`: mensaje editorial de la revisión congelada.
2. `EXPLANATION.RULE`: explicación educativa de `solution_spec.explanation`.
3. `NEXT_ACTION.CONTINUE`: siguiente acción textual del evaluador versionado.

Los mensajes se persisten para que una futura modificación de código o de borradores editoriales no reescriba la retroalimentación histórica.

## UI-MVP-013

La vista expresa `Respuesta correcta` o `Respuesta incorrecta` en texto, muestra puntuación y versión del evaluador y etiqueta Resultado, Explicación y Siguiente acción mediante encabezados. El encabezado de resultado recibe foco programático después de confirmar o recuperar la evaluación. `aria-live=polite` complementa, pero no sustituye, la estructura semántica.

No existe dependencia funcional de color, audio, animación o temporizador. A 320 CSS px el flujo debe permanecer sin overflow horizontal y pasar axe para WCAG 2.2 A/AA aplicable.
