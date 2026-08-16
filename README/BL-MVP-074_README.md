# BL-MVP-074 · Enviar respuesta de forma idempotente

## Resultado aceptable

> Doble clic/reintento produce una submission lógica, conserva valor validado y responde con estado confirmado o recuperable.

BL-MVP-074 completa la confirmación privada de `UI-MVP-012` y habilita el estado inicial de `UI-MVP-013`.

## Alcance

- confirma una opción perteneciente a la instancia congelada;
- exige CSRF e `Idempotency-Key`;
- serializa confirmaciones concurrentes por instancia;
- guarda una sola `learning.answer_submission` lógica (`submission_no = 1`);
- guarda el valor seleccionado en `learning.answer_value`;
- conserva un SHA-256 del valor canónico de la entrega;
- la misma respuesta/reintento recupera la submission existente;
- una clave reutilizada con respuesta distinta o un segundo valor distinto devuelve conflicto recuperable;
- una opción de otra instancia se rechaza sin revelar solución;
- al confirmar, la instancia pasa de `DELIVERED` a `RESPONDED`;
- `UI-MVP-013` muestra únicamente que la respuesta fue guardada y cuál fue la selección del propio estudiante.

## Frontera con BL075

BL074 **no decide si la respuesta es correcta**. No escribe `evaluation_result`, `feedback_item`, `learning_evidence` ni tablas de `progress`. BL075 será quien evalúe de forma reproducible contra la revisión congelada.

## Verificación

```powershell
$env:PGUSER = "musica_local"
$env:PGDATABASE = "musica_aprender"
$env:BL074_USE_DOCKER_PSQL = "true"

& "C:\Program Files\Git\bin\bash.exe" scripts/ci/learning/verify-answer-submission-idempotency.sh

npm.cmd run test:e2e -- study-exercise-flow.spec.ts --project=chromium-320
```
