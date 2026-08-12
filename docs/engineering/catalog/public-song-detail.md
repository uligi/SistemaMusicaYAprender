# Ficha pública por slug · BL-MVP-043

## Responsabilidad

BL-MVP-043 completa UI-MVP-004 y el último salto público de F2: un visitante puede pasar del catálogo a una ficha de la grabación exacta sin depender de YouTube y sin recibir identificadores internos innecesarios.

## Resolución del slug

La URL pública es `/canciones/{slug}`. El slug contiene un prefijo legible y una clave opaca estable de 20 caracteres. PostgreSQL calcula la clave con `md5(recording_id::text || ':public-song-v1')` truncado a 20 caracteres. No es un token de seguridad: la autorización sigue dependiendo de elegibilidad y disponibilidad actuales.

La resolución usa únicamente la clave final. Por eso cambiar el título visible no apunta a otra grabación. La respuesta devuelve el slug canónico calculado con el título vigente, pero no redirige silenciosamente a contenido distinto.

## Revalidación

Cada apertura exige simultáneamente:

- fila vigente en `editorial.published_package_projection`;
- `editorial.publication` ACTIVE y dentro de vigencia;
- disponibilidad PUBLIC ACTIVE para territorio e idioma;
- la misma fuente de la proyección por `sourceId`, proveedor, `externalRef` y versión;
- fuente YouTube ACTIVE/PUBLISHED y referencia válida.

Si el estado cambió entre búsqueda y apertura, la ficha deja de abrirse aunque el índice todavía conserve una fila anterior.

## Contrato público mínimo

La búsqueda y la ficha devuelven slug, título, nombre de grabación, artista, proveedor y disponibilidad. La ficha añade duración de referencia y clases de componentes propios declarados. No expone UUID internos, referencia externa de YouTube, checksums ni datos de borrador.

## YouTube degradable

BL-MVP-043 no instancia el iframe. La ficha se renderiza con contenido propio y solo identifica a YouTube como proveedor. La integración del player corresponde a BL-MVP-058/060; una falla externa no puede impedir leer esta ficha.
