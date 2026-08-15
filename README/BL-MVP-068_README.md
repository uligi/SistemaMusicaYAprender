# BL-MVP-068 — Mostrar panel de análisis contextual

## Alcance

Implementa `UI-MVP-010` y un panel reutilizable dentro de `UI-MVP-009`.

Resultado aceptable normativo:

> Seleccionar token/línea presenta vocabulario, kanji, lectura y gramática autorizados sin detener obligatoriamente el player.

## Contrato público

`GET /api/v1/public/catalog/songs/{slug}/analysis/{token}?territory=CR&language=es`

`token` es una clave pública opaca derivada del token canónico. No expone UUID editorial.

El servicio:

- revalida publicación, territorio e idioma;
- usa los componentes `LYRICS` y `ANALYSIS` exactos del paquete publicado;
- rechaza revisiones incompatibles;
- no sustituye una referencia rota por otra revisión;
- devuelve lectura, vocabulario, morfología, kanji, gramática y procedencia;
- no llama servicios lingüísticos externos.

## Experiencia

En `/aprender/{slug}`, un token con análisis se vuelve accionable. El panel se actualiza sin desmontar el reproductor.

También existe deep link:

`/aprender/{slug}/analisis/{token}`

Los niveles JLPT/escolares se muestran como orientación, nunca como certificación oficial.
