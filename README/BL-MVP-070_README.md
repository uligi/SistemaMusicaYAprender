# BL-MVP-070 · Banco y revisiones de ejercicios

## Resultado aceptable

> Ejercicio conserva tipo, contexto, revisión, opciones, solución, explicación, dificultad y procedencia.

BL-MVP-070 inicia F4 / EP-10 y materializa el modelo de lectura editorial de M08 en UI-MVP-025.

## Alcance

- usa las tablas físicas ya existentes `learning.exercise_definition`, `learning.exercise_revision` y `learning.exercise_item`;
- conserva el ancla exacta de línea y revisión de letra;
- interpreta `solution_spec` como TypedMeta `schemaVersion: 1`;
- conserva opciones ordenadas y soluciones por `acceptedItemOrders`;
- conserva explicación y retroalimentación;
- conserva dificultad editorial y su justificación;
- lee procedencia desde `editorial.provenance_record` + `catalog.source_reference`;
- expone una vista editorial accesible en `/editorial/canciones/{id}/ejercicios`;
- la lectura requiere `EDITORIAL.DRAFT` con alcance M08;
- no crea, edita, publica ni instancia ejercicios.

## Frontera con BL-MVP-071

BL-MVP-071 implementará la autoría de completar espacios con opciones, distractores y validación de ambigüedad. BL070 no adelanta esas escrituras.

Esto también respeta el privilegio actual de `jp_backoffice`: `SELECT` sobre `learning`, sin conceder escrituras generales al esquema.

## Verificación

- `scripts/ci/learning/verify-exercise-bank-model.sh`
- `tests/E2ETests/exercise-bank-model.spec.ts`
- gates generales de formato, TypeScript, .NET, arquitectura y E2E.
