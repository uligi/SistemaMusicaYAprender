# BL-MVP-059 — Motor local de sincronización

## Resultado aceptable

> Búsqueda binaria activa línea con desfase dentro de umbral, resincroniza tras seek y degrada por nivel disponible.

## Trazabilidad

- F3 — Contenido educativo
- EP-07 — Letra, reproducción y sincronización
- CU-MVP-06
- UI-MVP-009
- UI-MVP-022
- RNF-MVP-023 a RNF-MVP-025
- Dependencias: BL-MVP-056, BL-MVP-057 y BL-MVP-058

## Implementación

- endpoint público de sincronización basado únicamente en componentes fijados por la publicación;
- revisión exacta `TIMING + LYRICS + source`;
- DTO sin UUID públicos;
- índice temporal local en memoria;
- búsqueda binaria de línea y token;
- `offsetMs` aplicado antes de resolver;
- polling de reproducción a 100 ms;
- resincronización inmediata ante evento confirmado del player;
- degradación `TOKEN -> LINE -> NONE`;
- integración de la misma lógica en UI-MVP-009 y previsualización UI-MVP-022;
- cero movimiento de foco por cambio de línea.

## Fuera de alcance

- publicación editorial;
- karaoke completo y controles educativos BL060;
- furigana/romaji/traducción/análisis BL061-063;
- descarga multimedia;
- YouTube Data API;
- tablas o migraciones nuevas.

## Puertas

El instalador ejecuta:

- Prettier;
- `bash -n`;
- Chromium salvo `-SkipBrowserInstall`;
- build frontend;
- Playwright focal BL058/059;
- quality gate completa salvo `-SkipQualityGate`;
- Release;
- smoke PostgreSQL/API BL059 salvo `-SkipSmoke`;
- `git diff --check`;
- inventario exacto.

No ejecuta `git add`, commit ni push.

## UX editorial side-by-side

Tras la prueba visual se incorporó BL-MVP-059E: video sticky a la par del editor, selección explícita de línea, anterior/siguiente, marcado con el tiempo real del player, autoavance opcional, controles de precisión y responsive a 320 px. Esto elimina el flujo de scroll continuo detectado en UI-MVP-022.
