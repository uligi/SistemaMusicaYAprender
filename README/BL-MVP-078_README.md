# BL-MVP-078 · Experiencia completa de sesión de estudio — V3

## Objetivo

Integrar el recorrido privado ya construido por BL-MVP-072 a BL-MVP-077 y cerrar la aceptación de CU-MVP-09: el estudiante puede iniciar, **pausar**, **continuar** y **finalizar** una sesión sin duplicar hechos educativos y con estado autoritativo del servidor.

## Ciclo de vida de sesión

- `ACTIVE → PAUSED`: **Pausar sesión / Salir y continuar después**.
- `PAUSED → ACTIVE`: **Continuar sesión**.
- `ACTIVE|PAUSED → COMPLETED`: **Finalizar sesión**, `ended_at` autoritativo y resumen coherente en la vista actual.
- Las mutaciones usan CSRF y `If-Match` sobre `study_session.version`; la fila de sesión se bloquea al decidir transiciones y nuevas escrituras educativas para evitar carreras con pausa/finalización.
- El trigger físico `ops.bump_version()` conserva la versión monotónica; no se agrega migración.
- Una versión obsoleta devuelve precondición fallida y no sobrescribe otro cambio.

## Frontera educativa

Mientras una sesión está `PAUSED` o `COMPLETED`:

- no se crea una nueva instancia;
- no se confirma una respuesta nueva;
- no se crea una evaluación nueva;
- no se crea evidencia nueva.

Los hechos ya persistidos siguen siendo recuperables e idempotentes. Una selección local sin confirmar no se convierte en hecho guardado.

## Estados visibles

El recorrido conserva **Pendiente → Guardado → Confirmado** como estado educativo, separado del ciclo de vida `ACTIVE / PAUSED / COMPLETED` de la sesión.

## Aceptación focal

El E2E BL078 cubre:

1. Inicio → ejercicio → resultado y Pendiente → Guardado → Confirmado.
2. Salida antes de confirmar: persiste `PAUSED`; continuar persiste `ACTIVE`; se recupera la misma instancia sin guardar la selección local.
3. Instancia ya respondida: vuelve directamente al resultado confirmado sin nuevas escrituras.
4. **CA-MVP-053**: pausar, continuar y finalizar por teclado, sin temporizador obligatorio y sin escrituras educativas durante la pausa/finalización.
5. Axe y viewport de 320 px.

## Fuera de alcance

- No escribe `progress.*` ni adelanta BL-MVP-083.
- No publica ejercicios ni adelanta BL-MVP-079.
- No crea `resume_point` ni adelanta BL-MVP-086.
- No cambia esquema físico ni crea migraciones.
