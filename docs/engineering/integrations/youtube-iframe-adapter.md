# Adaptador YouTube IFrame · BL-MVP-058

## Límite

YouTube es la única dependencia externa permitida del MVP y se limita a reproducción incrustada. El navegador es el único componente que se comunica con YouTube.

El adaptador no conoce letra, traducción, análisis, ejercicios ni reglas educativas. BL-MVP-059 recibirá un controlador mínimo y resolverá la sincronización local por fuera del adaptador.

## Privacidad y carga

El script de IFrame Player API y el iframe se cargan únicamente después de una acción explícita de la persona.

El adaptador crea explícitamente un `<iframe>` existente con:

- host `https://www.youtube-nocookie.com`;
- `enablejsapi=1`;
- `origin=window.location.origin`;
- `playsinline=1`;
- `rel=0`.

La aplicación conserva únicamente el identificador/referencia de once caracteres que ya existe en `catalog.recording_source.external_ref`. No descarga ni copia audio, video o subtítulos.

## Eventos

El contrato local expone:

- `ready`;
- `state` con `unstarted`, `ended`, `playing`, `paused`, `buffering` o `cued`;
- `error` con código numérico del IFrame API.

El controlador disponible para BL-MVP-059 contiene:

- `play()`;
- `pause()`;
- `seek(seconds)`;
- `getCurrentTime()`.

No se propaga el objeto `YT.Player` fuera del adaptador.

## Degradación

Error de carga del script, bloqueo de red, código 101 o 150 y cualquier fallo del player producen un estado degradado dentro del componente. El contenido propio de UI-MVP-009 permanece montado y utilizable.

La interfaz no mueve el foco ante eventos del player y no usa regiones vivas para anunciar cada cambio de estado.

## Prohibiciones verificables

- sin YouTube Data API;
- sin `googleapis.com/youtube/v3`;
- sin scraping;
- sin descarga de media;
- sin almacenamiento audiovisual;
- sin lógica de sincronización BL-MVP-059;
- sin publicación.

El iframe mantiene un viewport mínimo de 200 × 200 CSS px antes de aplicar la relación 16:9 disponible.

## Vista previa editorial sin publicación

BL-MVP-058 debe poder revisarse antes de la publicación final del MVP. Por eso el adaptador se reutiliza en UI-MVP-022 con la fuente exacta que ya entrega el contexto editorial de la grabación.

Esta vista:

- requiere la frontera editorial existente;
- usa `recording_source.external_ref` del borrador;
- no consulta `/public/catalog/songs/{slug}`;
- no crea `publication`, `publication_availability` ni `published_package_projection`;
- no genera ni necesita un slug público;
- no cambia el estado editorial de la canción.

La ruta `/aprender/{slug}` sigue siendo la superficie pública/estudiante de UI-MVP-009 y solo tendrá datos reales cuando exista una publicación válida.
