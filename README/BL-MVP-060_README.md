# BL-MVP-060 — Reproductor educativo y karaoke accesible

## Trazabilidad

- CU-MVP-06, CU-MVP-07
- UI-MVP-009
- CE-03, CE-04, CE-12, CE-13
- Dependencias funcionales consumidas: BL-MVP-019, 043, 058, 059 y contrato coordinado BL-MVP-063.

## Resultado

UI-MVP-009 presenta primero el contenido educativo propio y después la fuente externa. El snapshot del motor local BL059 activa línea y, únicamente cuando existe precisión TOKEN, el token correspondiente. La actualización temporal no mueve foco ni ejecuta `scrollIntoView`.

La vista degrada de TOKEN a LINE y de LINE a NONE sin inventar granularidad. Una falla o bloqueo de YouTube conserva letra y capas propias.

## Contrato coordinado 060/063

El ciclo de dependencias 060 ↔ 063 se resuelve con dos contratos estables:

1. BL059 entrega `LocalSynchronizationSnapshot`.
2. `/api/v1/public/catalog/songs/{slug}/layers` entrega las capas compatibles de la publicación exacta.

BL060 consume ambos contratos; BL063 es propietario de la presentación conmutables de capas. Los criterios y verificadores permanecen separados.

## Accesibilidad

- línea activa: `aria-current`, sin cambio automático de foco;
- controles propios operables con teclado;
- actualizaciones temporales con `aria-live="off"` para evitar anuncios continuos;
- reflujo a 320 CSS px;
- reducción de precisión segura cuando faltan tiempos por token.

## Exclusiones

No descarga audio/video, no usa YouTube Data API, no crea progreso, no persiste preferencias y no adelanta BL068/069.
