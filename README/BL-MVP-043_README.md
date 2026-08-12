# BL-MVP-043 · Ficha pública de canción publicada

## Resultado aceptable

La ficha identifica artista, grabación, disponibilidad y contenido propio sin exponer borradores ni bloquearse por YouTube.

## Alcance

- implementa UI-MVP-004 en `/canciones/{slug}`;
- enlaza los resultados de BL-MVP-042 mediante un slug público legible;
- retira identificadores UUID y `externalRef` del contrato público de búsqueda;
- vuelve a validar publicación, territorio, idioma y la fuente exacta al abrir;
- muestra identidad musical, grabación, disponibilidad y componentes propios declarados;
- no carga el iframe de YouTube ni depende de una llamada externa para renderizar la ficha;
- no implementa aún reproducción, letra sincronizada, traducción o análisis: pertenecen a F3.

## Slug público

El slug combina un prefijo legible derivado del título vigente y una clave opaca de 20 caracteres hexadecimales derivada en PostgreSQL de la identidad estable de la grabación. La clave, no el texto del título, resuelve la grabación. No se añade tabla ni migración física.

## Seguridad y privacidad

La API pública devuelve únicamente campos necesarios para la ficha. No devuelve `publicationId`, `recordingId`, `workId`, `artistId`, `externalRef`, checksums ni objetos editoriales. Una publicación retirada, fuera de territorio o cuya fuente ya no coincide con la proyección se responde como no disponible.

## Evidencia

- Playwright + axe para UI-MVP-004;
- 320 CSS px sin overflow injustificado;
- smoke PostgreSQL/API con slug, contrato público mínimo, 404 territorial y retiro de fuente;
- puerta CI dedicada en puerto 5458.
