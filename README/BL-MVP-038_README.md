# BL-MVP-038 — Administrar obra, grabación y fuente de YouTube

## Definición

- Fase: F2 — Catálogo y cadena editorial.
- Épica: EP-05 — Catálogo musical y búsqueda.
- Tipo: Historia.
- Traza: CU-MVP-14; UI-MVP-018, UI-MVP-019; CE-02, CE-12.
- Story Points: 13.
- Dependencia: BL-MVP-037.

Resultado aceptable:

> Obra, grabación y fuente quedan separadas; la referencia de YouTube valida proveedor, external_ref y correspondencia exacta.

## Qué implementa

BL-MVP-038 completa el alta editorial iniciada por BL-MVP-037:

1. reutiliza una identidad estable de artista;
2. crea `catalog.musical_work` como obra canónica;
3. conserva el título original en `catalog.work_title`;
4. vincula artista y obra mediante `catalog.work_artist`;
5. crea `catalog.recording` como interpretación grabada separada;
6. crea `catalog.recording_source` con proveedor `YOUTUBE` y `external_ref` normalizado;
7. registra el estado inicial DRAFT y auditoría primaria en la misma transacción;
8. permite abrir UI-MVP-019 con los identificadores separados.

No publica contenido, no registra derechos, no registra créditos completos y no crea letras.

## Validación de YouTube

El servidor no usa YouTube Data API ni otra API externa. Acepta de forma local:

- identificador de video de 11 caracteres;
- `https://www.youtube.com/watch?v=<id>`;
- `https://youtu.be/<id>`;
- `https://www.youtube.com/embed/<id>`;
- `https://www.youtube.com/shorts/<id>`;
- `https://www.youtube-nocookie.com/embed/<id>`.

Se persiste únicamente `provider_code = YOUTUBE` y el `external_ref`. No se descarga ni almacena audio o video.

El editor además debe confirmar explícitamente que la referencia corresponde exactamente a la grabación que está registrando. Esa confirmación editorial no pretende sustituir una API externa prohibida.

## Duplicados e idempotencia

Antes del alta se revisa:

- coincidencia exacta de `external_ref` de YouTube en cualquier grabación;
- similitud de título para el mismo artista mediante `pg_trgm`.

Una fuente exacta ya vinculada bloquea el alta. Una coincidencia potencial de título exige revisión y confirmación explícita.

La creación deriva identificadores deterministas desde actor + operación + `Idempotency-Key`:

- mismo key + mismo contenido: replay seguro;
- mismo key + contenido distinto: conflicto 409.

Los advisory locks transaccionales serializan simultáneamente la clave idempotente, el título por artista y la fuente de YouTube.

## API

- `POST /api/v1/editorial/song-drafts/duplicates`
- `POST /api/v1/editorial/song-drafts`
- `GET /api/v1/editorial/song-drafts/{recordingId}`

Las operaciones requieren sesión y permiso efectivo `EDITORIAL.DRAFT`. Las altas usan CSRF; la creación exige `Idempotency-Key`.

La lectura por `recordingId` se autoriza con ámbito objetivo M02, por lo que un grant GLOBAL, MODULE M02 u OBJECT coincidente puede satisfacer la autorización.

## UI

- UI-MVP-018 `/editorial/canciones/nueva`
  - selecciona o crea artista;
  - completa obra, grabación y fuente;
  - revisa duplicados;
  - crea el borrador.
- UI-MVP-019 `/editorial/canciones/{id}`
  - muestra obra, grabación, fuente y artista con IDs separados;
  - deja claro que DRAFT no equivale a publicación.

## Fuera de alcance

Se mantienen para historias posteriores:

- BL-MVP-039: créditos, participantes y procedencia;
- BL-MVP-040: derechos, usos, territorios y vigencias;
- BL-MVP-041: proyección pública elegible;
- BL-MVP-042: búsqueda pública completa.

No hay migración nueva ni cambios al SQL maestro en BL-MVP-038.
