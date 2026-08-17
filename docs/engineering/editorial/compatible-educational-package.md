# Paquete educativo compatible — BL-MVP-047

El agregado `editorial.editorial_package` es la unidad que reúne referencias exactas. BL047 usa el esquema físico ya existente; no agrega migración.

## Escritura

`POST /api/v1/editorial/song-drafts/{recordingId}/compatible-package`

La operación:

1. exige sesión autorizada con `EDITORIAL.SUBMIT` o `EDITORIAL.REVIEW`;
2. valida CSRF;
3. exige `If-Match`;
4. serializa por grabación con advisory lock;
5. resuelve cada UUID exacto dentro de su tabla propietaria;
6. exige la misma `lyrics_revision_id` para tiempos, traducción, análisis y ejercicios;
7. reemplaza componentes solo sobre paquete `DRAFT` no congelado;
8. calcula SHA-256 sobre grabación + kind + revision_id + checksum ordenados;
9. actualiza el checksum del paquete, dejando que `ops.bump_version()` incremente `version`;
10. registra `EDITORIAL.PACKAGE.ASSEMBLE` en auditoría.

## Lo que deliberadamente no hace

No congela ni somete (`BL048`), no crea decisiones (`BL049`) y no publica (`BL050`). Esto evita que el ciclo de planificación BL047↔BL079 se convierta en una publicación adelantada.
