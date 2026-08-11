# BL-MVP-029B — falso positivo E2E de no enumeración

## Motivo

Después de BL-MVP-029A, la puerta completa aprobó formato, build, TypeScript y llegó a Playwright.
Trece pruebas pasaron y falló únicamente la nueva prueba BL-MVP-029.

La aserción defectuosa buscaba en **toda la página**:

```text
cuenta limitada | dirección IP | correo existe
```

pero UI-MVP-007 ya contiene deliberadamente el texto de privacidad:

```text
La respuesta de error no confirma si el correo existe...
```

Por tanto `correo existe` no provenía de la respuesta 429 ni filtraba información: la prueba estaba
capturando una frase estática que precisamente explica la política no enumerativa.

## Corrección

La prueba ahora localiza exclusivamente el `StateMessage` generado por el HTTP 429
(`data-state="UI-EST-06"`) y valida dentro de ese mensaje:

- título genérico `La solicitud debe esperar`;
- corrección genérica `Espera un momento antes de volver a intentarlo.`;
- ausencia de `cuenta`, `dirección IP` y `correo existe`.

Así se comprueba lo que realmente exige BL-MVP-029: que **la respuesta de limitación** no revele qué
dimensión disparó el límite, sin prohibir el texto informativo estático de la pantalla.

## Alcance

No cambia API, límites 5/20, ventana, Retry-After, HMAC, cookies, CSRF, PostgreSQL, Compose ni
mensajes de producto. Es una corrección de prueba.

La versión incluida de `scripts/apply-bl-mvp-029.ps1` reconoce los artefactos A y B para evitar un
falso RED de inventario en la siguiente ejecución completa.
