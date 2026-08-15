# Read model público del paquete educativo

BL-MVP-069 introduce el punto de lectura integral que une las piezas ya
publicadas sin convertir una caché en autoridad.

## Fuente de verdad

`editorial.published_package_projection` acelera la resolución inicial, pero
cada solicitud vuelve a comprobar:

1. `editorial.publication` activa y vigente;
2. `editorial.publication_availability` pública, territorial y vigente;
3. `catalog.recording_source` exacta y elegible;
4. `editorial.publication_component` realmente publicado;
5. `editorial.package_component` del mismo paquete y tipo;
6. revisión canónica y checksum del componente.

La proyección debe coincidir con el número/checksum de publicación, fuente,
orden, tipo, `sourceComponentId` y checksum de todos los componentes. Una
proyección stale o adulterada produce estado seguro `409`.

## Compatibilidad

La revisión de letra es el ancla común:

- sincronización -> misma `lyrics_revision_id` y misma fuente;
- traducción -> misma `lyrics_revision_id`;
- análisis -> misma `lyrics_revision_id`;
- ejercicio -> misma grabación y, si declara línea, esa línea pertenece a la
  misma revisión de letra.

No se utiliza `latest` para completar huecos.

## Snapshot de lectura

La resolución se ejecuta en una única transacción `REPEATABLE READ` y
`READ ONLY`, evitando que una solicitud observe mitad de una sustitución
concurrente.

## HTTP

Contrato:

`GET /api/v1/public/catalog/songs/{slug}/learning-package`

Query:

- `territory`
- `language` (español por defecto)

Estados:

- `200`: paquete coherente y elegible;
- `304`: mismo checksum **después de revalidar autoridad**;
- `400`: slug/territorio/idioma inválidos;
- `404`: ninguna publicación actualmente elegible;
- `409`: ambigüedad o mezcla/checksum incompatible.

El ETag usa el checksum de la publicación. La respuesta no contiene UUID
internos ni concede acciones editoriales.
