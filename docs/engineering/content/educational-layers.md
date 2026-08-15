# Capas educativas publicadas

BL-MVP-063 introduce un read model acotado a presentación, no el paquete educativo completo de BL-MVP-069.

## Endpoint

`GET /api/v1/public/catalog/songs/{slug}/layers?territory=CR&language=es`

Devuelve únicamente capas correspondientes a la publicación y disponibilidad elegibles:

- líneas y tokens de `LYRICS`;
- traducciones de `TRANSLATION`;
- lecturas de `ANALYSIS`.

Los identificadores editoriales permanecen internos al servicio; el cliente recibe orden, superficie, offsets y ayudas necesarias para renderizar.

## Compatibilidad

La consulta parte de `editorial.publication_component` y `editorial.package_component`. Una traducción o análisis cuya revisión japonesa no coincide no se mezcla: el endpoint responde estado seguro de incompatibilidad.

## Render

- texto japonés exacto de la línea;
- offsets de token sobre puntos de código Unicode para no sustituir la superficie;
- `ruby/rt` solo desde lectura contextual publicada;
- romaji separado;
- traducción NATURAL preferida, LITERAL como respaldo;
- toggles locales con `aria-pressed`.

## Dependencias externas

Cero llamadas lingüísticas externas. YouTube permanece aislado en su adaptador.
