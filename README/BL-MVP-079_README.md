# BL-MVP-079 — Validar ejercicios dentro del paquete publicable

## Resultado

Antes de incorporar una revisión `EXERCISE` al paquete DRAFT, el servidor comprueba que el ejercicio P0 sea reproducible, accesible en preview y compatible con la revisión japonesa exacta.

La aprobación implementada aquí es **específica del paquete**: incorporar `exercise_revision_id` a `package_component` después de superar la validación. La revisión fuente no se reescribe y la publicación pública continúa perteneciendo a BL050.

## Bloqueos obligatorios

- Tipo distinto de `FILL_BLANK_OPTIONS`.
- Modelo distinto de `SINGLE_CHOICE`.
- Menos de 3 o más de 5 opciones.
- Opciones vacías, repetidas o indistinguibles.
- No existe exactamente una opción `CORRECT`.
- `sourceTokenId` no pertenece a la línea exacta.
- Falta explicación, feedback textual, dificultad o procedencia.
- La revisión japonesa del ejercicio no coincide con la elegida por el paquete.
- `solution_spec` no conserva esquema/versiones aceptadas.
- Metadatos P2 (`minigame`, vidas, combos, puntuación/temporizador) intentan entrar en el paquete P0.

## Trazabilidad

- CU-MVP-19-21
- CA-MVP-109-114
- UI-MVP-025-027
- CE-06, CE-09, CE-10, CE-14
- Dependencias coordinadas: BL047, BL070, BL071
