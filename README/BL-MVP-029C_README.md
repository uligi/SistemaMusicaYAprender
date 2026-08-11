# BL-MVP-029C — validación ASCII-safe del correctivo E2E

## Motivo

BL-MVP-029B ya había entregado la prueba E2E corregida, pero su instalador se detuvo antes de
ejecutarla con:

```text
No se encontro la comprobacion no enumerativa acotada al mensaje 429.
```

La prueba extraída sí contiene la comprobación nueva. El problema estaba en el **validador
PowerShell**: comparaba un literal que incluía `dirección` dentro de un `.ps1` UTF-8 sin BOM.

La consola de Windows PowerShell ya mostraba síntomas de lectura por página de códigos heredada
(`configuraciÃ³n`, `definiciÃ³n`). En Windows PowerShell 5.1, un script UTF-8 sin BOM puede
interpretarse con la página de códigos del sistema. El literal acentuado del script dejó de ser
idéntico al texto leído explícitamente con `ReadAllText(..., UTF8)` desde el archivo TypeScript.

## Corrección

029C conserva la prueba funcional de 029B y reemplaza únicamente la validación del correctivo por
comprobaciones estructurales ASCII-safe:

- existencia del `StateMessage` `UI-EST-06`;
- ausencia de la antigua aserción global;
- presencia del inicio y final de la aserción no enumerativa acotada.

Después ejecuta realmente:

- Prettier check;
- TypeScript E2E;
- Playwright focalizado del archivo BL-MVP-029;
- `git diff --check`.

El instalador 029C es deliberadamente ASCII-only.

La versión incluida de `scripts/apply-bl-mvp-029.ps1` reconoce los artefactos 029A, 029B y 029C.

## Alcance

No cambia rate limiting, API, mensajes, HMAC, CSRF, cookies, sesiones, PostgreSQL, Compose ni CI.
Es un correctivo del validador del paquete.
