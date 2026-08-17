# Validación de ejercicios de paquete — BL-MVP-079

BL079 endurece la frontera entre la autoría DRAFT de BL071 y el paquete publicable.

## Regla de fuente

La revisión del ejercicio conserva una línea, la línea pertenece a una sección y esa sección fija una `lyrics_revision_id`. Esa identidad debe coincidir exactamente con la letra elegida por BL047. Un cambio de fuente no se “repara” buscando otra revisión: el ejercicio queda incompatible hasta revalidarlo explícitamente.

## Regla P0

El candidato debe ser `FILL_BLANK_OPTIONS` y `SINGLE_CHOICE`, conservar 3-5 opciones distinguibles, exactamente una opción `CORRECT` con `sourceTokenId` válido, solución versionada, explicación, feedback textual, dificultad y procedencia.

`acceptedItemOrders` permanece explícito. No se activan minijuegos, vidas, combos, puntuación ni temporizador.

## Preview y checklist

UI-MVP-026 muestra el texto de contexto y los bloqueos por candidato. Los candidatos inválidos quedan deshabilitados y el checklist distingue enlaces rotos, compatibilidad de fuente, derechos y preparación para congelar.

“Listo para congelar” no significa “publicado”.
