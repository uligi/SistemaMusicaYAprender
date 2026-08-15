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

## Previsualización editorial antes de publicar

La lógica de publicación real todavía no es requisito para probar el panel manualmente.

El dossier editorial reutiliza `ContextualAnalysisPanel` dentro de **Previsualización de Karaoke** y consulta:

`GET /api/v1/editorial/song-drafts/{recordingId}/analysis-preview/{token}?language=es`

Este contrato:

- exige `EDITORIAL.DRAFT`;
- trabaja sobre la revisión de letra editorial más reciente y el análisis compatible exacto;
- rechaza análisis `stale` o de otra revisión;
- usa la misma referencia opaca de token que el reproductor educativo;
- no crea publicación;
- no necesita slug público;
- no consulta el catálogo público;
- no escribe datos;
- permite validar manualmente vocabulario, lectura, morfología, kanji, gramática y procedencia antes de implementar publicación.
