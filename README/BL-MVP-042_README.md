# BL-MVP-042 — Implementar búsqueda interna PostgreSQL

Base exacta: `17eaa2ab0b729328b678a2404011b11b3dd3ed81`.

## Resultado aceptable

Busca título, alias, artista y lectura con `tsvector`/`pg_trgm`, paginación estable y sin servicio externo.

## Alcance

- reconstruye `catalog.song_search_document` desde la proyección pública BL-MVP-041;
- indexa título canónico, títulos alternos, artistas, alias, kana/lectura y romaji;
- usa el `tsvector` generado y los índices GIN/`pg_trgm` ya existentes;
- pagina con cursor opaco y orden total estable;
- consulta pública revalida publicación, territorio, idioma y la misma fuente canónica;
- el índice nunca autoriza por sí solo;
- UI-MVP-002 (`/canciones`) y UI-MVP-003 (`/canciones?consulta=`) quedan funcionales;
- no implementa todavía UI-MVP-004/ficha pública; BL-MVP-043 será responsable del slug y apertura;
- no usa APIs externas de búsqueda.

## Seguridad

`jp_worker` recibe `DELETE` únicamente sobre `catalog.song_search_document`, porque es una proyección reconstruible. `jp_app` conserva solo lectura sobre catálogo/editorial y no puede borrar el índice.

## Validación

El smoke comprueba:

- dos grabaciones de la misma obra permanecen separadas;
- búsqueda por `kaijuu` y por `怪獣`;
- lectura kana/romaji en el documento;
- GIN `tsvector` y GIN `pg_trgm` mediante `EXPLAIN`;
- paginación por cursor sin repetir grabaciones;
- territorio incorrecto sin resultados;
- una disponibilidad retirada deja de aparecer aunque el documento derivado aún exista;
- cero dependencia HTTP externa en backend de búsqueda.
