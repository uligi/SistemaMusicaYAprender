# Cliente HTTP tipado · BL-MVP-021

BL-MVP-021 implementa el `Data client` previsto por la arquitectura del cliente web. La aplicación usa `fetch` nativo con contratos TypeScript y una base same-origin `/api/v1`; no agrega una librería HTTP ni almacena credenciales en `localStorage` o `sessionStorage`.

## Contrato uniforme

`TypedHttpClient` devuelve `ApiResult<T>` en lugar de obligar a cada pantalla a interpretar respuestas por su cuenta. Los métodos de escritura emiten `MutationState`: comienzan en `UI-EST-11` Guardando y solo pasan a `UI-EST-12` Confirmado después de una respuesta HTTP satisfactoria. Un `412` o `409` se representa como `UI-EST-10` Conflicto; validación como `UI-EST-09`; sesión/autorización y red usan los estados ya definidos por el sistema visual.

La cancelación usa `AbortSignal` de extremo a extremo, incluso durante la lectura del cuerpo de la respuesta. Cancelar no se presenta como error de red ni como escritura confirmada.

## ETag y concurrencia

Las lecturas GET mantienen una caché breve exclusivamente en memoria. Cuando la entrada deja de estar fresca, el cliente revalida el ETag mediante `If-None-Match`; un `304` reutiliza el dato ya recibido. Las escrituras pueden enviar `If-Match` para concurrencia optimista y nunca convierten un conflicto de versión en sobrescritura silenciosa.

La caché no persiste datos privados en almacenamiento del navegador. Las mutaciones pueden invalidar prefijos explícitos en todas las variantes de idioma y subrutas relacionadas; por defecto, invalidan su propia ruta.

## ProblemDetails y DI-MVP-05

Los errores HTTP se normalizan desde `application/problem+json`. El cliente conserva `code` estable, `correlation_id`, estado HTTP, clasificación y campos afectados. No convierte `title` o `detail` libres del servidor en texto de interfaz.

DI-MVP-05 exige errores recuperables. Por eso `ClientProblem` expone causa, corrección, si los datos se conservaron y errores de campo estructurados. La pantalla puede presentar una explicación segura en español, enfocar los campos correspondientes y conservar entradas válidas sin depender de mensajes libres del backend.

## Español, japonés y DI-MVP-08

El cliente usa `Accept-Language: es-CR` de forma predeterminada y JSON UTF-8. No translitera, normaliza ni transforma contenido japonés recibido o enviado. Los componentes siguen siendo responsables de marcar el contenido con `lang="ja"` y `ruby/rt` cuando corresponda; romaji continúa siendo una ayuda y no una fuente canónica.

## Reintentos seguros e idempotencia

Una solicitud automática puede ejecutarse como máximo tres veces. GET/HEAD son reintentables por ser lecturas seguras. POST, PUT, PATCH o DELETE solo reciben reintento automático cuando incluyen `Idempotency-Key`; sin esa clave se hace un único intento. Los estados transitorios cubiertos son 408, 425, 429, 502, 503 y 504, además de fallas de red, con retroceso exponencial y jitter.

Un `AbortSignal`, validación, acceso denegado o conflicto de ETag nunca se reintentan automáticamente. El servidor sigue siendo la autoridad de idempotencia y de autorización.

## Same-origin y sesión

`TypedHttpClient` solo admite una base relativa al mismo origen y usa `credentials: 'same-origin'`. Las rutas se resuelven de forma canónica y no pueden escapar de la base `/api/v1` mediante segmentos `.`/`..`, equivalentes codificados o fragmentos. No agrega JWT ni cabeceras `Authorization` automáticamente; la sesión segura permanece administrada por cookie del navegador según ADR-007. El reverse proxy conserva `/api/v1/` al reenviar contratos REST v1 al servidor.

## Evidencia

`scripts/frontend/verify-http-client.mjs` comprueba el contrato estático y ejecuta escenarios conductuales contra `fetch` inyectado: cancelación antes y durante la lectura del cuerpo, JSON japonés, caché + ETag/304, invalidación por prefijo entre idiomas, confinamiento a `/api/v1`, ProblemDetails, máximo de tres intentos, POST sin/sí Idempotency-Key, If-Match/412 y transiciones Guardando/Confirmado. `apps/web/src/data/http/HttpClientContractFixture.ts` mantiene un consumidor TypeScript compilable para evitar regresiones del API genérico.
