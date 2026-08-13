# BL-MVP-058 · Adaptador aislado de YouTube IFrame

Implementa el habilitador de reproducción externa de UI-MVP-009 sin incorporar todavía el motor de sincronización de BL-MVP-059 ni el reproductor educativo completo de BL-MVP-060.

Resultado aceptable:

> Carga diferida con origin y eventos permitidos; no usa Data API, no descarga media y expresa bloqueo/falla.

El cambio:

- habilita `/aprender/{slug}` como superficie mínima de UI-MVP-009;
- obtiene únicamente la referencia pública de la fuente ya validada;
- mantiene contenido propio visible antes de cargar YouTube;
- exige acción explícita antes de insertar el script/API o el iframe;
- crea el player con `youtube-nocookie.com`;
- envía `origin` del mismo origen de la aplicación;
- encapsula `ready`, cambios de estado y errores detrás de un contrato propio;
- expone un controlador mínimo para `play`, `pause`, `seek` y `getCurrentTime`, que BL-MVP-059 podrá consumir;
- convierte bloqueo, video no incrustable o fallo de red en un estado comprensible;
- no usa YouTube Data API, scraping, descarga audiovisual ni almacenamiento de bytes;
- no mueve el foco cuando cambian eventos del player;
- no implementa sincronización de línea ni publicación.

La referencia de YouTube se incorpora a la respuesta pública existente como `sourceExternalRef`; no se crea endpoint, tabla ni migración nueva.

## Previsualización sin publicar

Durante F3 no se requiere publicar una canción para revisar BL-MVP-058. El mismo adaptador se monta también dentro de UI-MVP-022 sobre la fuente del borrador editorial ya autorizado. Esa vista usa `recordingId` y `externalRef` del contexto editorial; no crea publicación, slug público ni proyección pública.

La ruta pública `/aprender/{slug}` continúa reservada para contenido realmente publicado. Antes de la publicación final puede responder no disponible, y eso es correcto.
