# Búsqueda pública PostgreSQL — BL-MVP-042

## Autoridad

`catalog.song_search_document` es una proyección de búsqueda, no una fuente de autorización. Cada lectura pública vuelve a unir el documento con `editorial.published_package_projection`, `editorial.publication`, `editorial.publication_availability` y la fuente YouTube exacta almacenada en la proyección BL-MVP-041.

## Índice

El Worker ejecuta primero BL-MVP-041 y después reconstruye el documento de búsqueda. `normalized_terms` incorpora:

- título canónico de obra;
- título de grabación;
- títulos alternos/localizados;
- nombre canónico de artistas asociados;
- alias/lecturas de artistas;
- nombres de créditos disponibles.

La columna `search_vector` continúa siendo generada por PostgreSQL con configuración `simple`; no se duplica ni se calcula en C#.

## Consulta

La búsqueda acepta Unicode NFKC y combina:

- `search_vector @@ plainto_tsquery('simple', ...)`;
- operador de similitud `%` de `pg_trgm`;
- coincidencia de subcadena para consultas japonesas parciales.

El orden es total y determinista: prioridad de coincidencia, título, artista, grabación y UUID interno. El cliente recibe un cursor Base64URL opaco ligado a consulta, territorio e idioma.

## Disponibilidad

Los resultados solo salen cuando la publicación sigue activa, la disponibilidad PUBLIC sigue vigente para el territorio/idioma solicitado y la fuente coincide exactamente con la identidad/version guardada por BL-MVP-041. Un documento stale no concede acceso.

## UI

UI-MVP-002 y UI-MVP-003 muestran título, artista, grabación, proveedor y disponibilidad sin exponer UUID. La ficha UI-MVP-004 se reserva para BL-MVP-043 para no inventar un slug antes de su historia propietaria.
