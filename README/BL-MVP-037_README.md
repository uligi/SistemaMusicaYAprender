# BL-MVP-037 — Administrar artistas, alias y nombres localizados

## Definición normativa

- Fase: F2 — Catálogo y cadena editorial.
- Épica: EP-05 — Catálogo musical y búsqueda.
- Tipo: Historia.
- Traza: `CU-MVP-14`; `UI-MVP-018`, `UI-MVP-019`; M02.
- Story Points: 8.
- Dependencias: BL-MVP-030 y BL-MVP-035.
- Resultado: **el editor crea identidad estable, alias y lecturas sin usar nombres como clave; duplicados potenciales generan advertencia.**

## Corte funcional

BL-MVP-037 convierte la primera sección de `UI-MVP-018` (`/editorial/canciones/nueva`) en una pantalla funcional para registrar o localizar la identidad canónica del artista antes de crear obra, grabación y fuente.

El servidor exige `EDITORIAL.DRAFT` dentro del ámbito M02 en cada consulta y mutación. La navegación visible no concede acceso.

La identidad se persiste en `catalog.artist.artist_id` como UUID opaco. El nombre canónico, la lectura kana, la romanización y los nombres localizados se conservan como datos mostrables/buscables; ninguno se utiliza como clave primaria.

## Duplicados e idempotencia

Antes del alta la UI ejecuta una revisión de coincidencias sobre nombres y alias internos. La búsqueda usa PostgreSQL/`pg_trgm`; no existe llamada a un buscador o recomendador externo.

Si aparecen coincidencias, el alta exige confirmación explícita. El sistema no fusiona automáticamente registros. La fusión controlada completa de RF-M02-013/095 queda fuera de este PBI.

La creación usa `Idempotency-Key`. La identidad UUID se deriva de actor + operación + clave de idempotencia, nunca del nombre. Repetir exactamente la misma alta devuelve la identidad existente; reutilizar la misma clave con otro contenido devuelve conflicto.

## Alias y lectura

La fila canónica también se registra como forma preferida en `catalog.artist_alias`, lo que permite una búsqueda uniforme junto con:

- lectura japonesa;
- romanización;
- nombre localizado;
- otras formas que futuros PBI agreguen sobre el mismo contrato.

Se conserva UTF-8/NFC para presentación y una forma NFKC/case-folded separada para comparación.

## Estado y publicación

El nuevo artista se crea con `status_code=ACTIVE` como estado del objeto de catálogo. Esto **no publica una canción** ni crea obra, grabación, fuente, derechos o paquete editorial. BL-MVP-038 continúa la cadena de CU-MVP-14.

## Evidencia

- Playwright/axe: flujo UI de advertencia, confirmación y búsqueda por alias.
- Smoke PostgreSQL/API: sesión real de editor, autorización M02, antiforgery, alta, reintento idempotente, advertencia de duplicado, búsqueda por romanización y auditoría.
- CI publica `artifacts/postgres/artist-administration-summary.txt`.
