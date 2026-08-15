# BL-MVP-069 · API/read model del paquete educativo publicado

## Resultado

BL-MVP-069 materializa un contrato único para consultar la identidad pública de
un paquete educativo ya publicado:

`GET /api/v1/public/catalog/songs/{slug}/learning-package?territory=CR&language=es`

El habilitador no publica contenido. La proyección tampoco concede
elegibilidad: antes de devolver datos se vuelven a comprobar la publicación,
su vigencia, la disponibilidad pública, la fuente, la instantánea de
`publication_component`, el `package_component` de origen y las revisiones
canónicas.

## Coherencia

Toda la lectura se resuelve dentro de una transacción PostgreSQL
`REPEATABLE READ` marcada `READ ONLY`.

El paquete exige:

- una única revisión `LYRICS`;
- como máximo una revisión `TIMING`, `TRANSLATION` y `ANALYSIS`;
- ejercicios opcionales y repetibles;
- `TIMING` anclado a la misma letra y fuente;
- `TRANSLATION` y `ANALYSIS` anclados a la misma letra;
- ejercicios pertenecientes a la misma grabación y, cuando tienen línea,
  a la revisión de letra exacta;
- checksum idéntico entre revisión, `package_component` y
  `publication_component`;
- correspondencia exacta entre la proyección y la instantánea publicada.

Una inconsistencia devuelve `409`; nunca se compone un paquete híbrido.

## Caché

La respuesta expone el checksum de la publicación y usa un ETag derivado de
él. `Cache-Control: public, no-cache` permite almacenar la respuesta, pero
obliga a revalidarla.

La comprobación de `If-None-Match` ocurre **después** de volver a validar la
publicación y su disponibilidad. Un ETag antiguo no conserva acceso a una
publicación retirada, vencida o incompatible.

## Identidad pública

El DTO no expone UUID internos. Devuelve:

- número de publicación y paquete;
- checksum de publicación y paquete;
- fuente pública YouTube y versión;
- alcance/vigencia pública resuelta;
- versión y fecha de la proyección;
- capacidades disponibles;
- tipo, orden, revisión, estado y checksum de cada componente.

## Exclusiones

BL-MVP-069:

- no implementa el flujo editorial de publicación;
- no crea ni modifica `publication`;
- no cambia derechos;
- no adelanta BL-MVP-070/071 de ejercicios;
- no sustituye las entidades canónicas por la proyección;
- no llama APIs externas.
