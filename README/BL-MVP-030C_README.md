# BL-MVP-030C — idempotencia del route-manifest después de Prettier

## Motivo

BL-MVP-030B restauró correctamente `apps/web/tsconfig.app.tsbuildinfo`. La reejecución de la puerta
llegó a las capacidades del `route-manifest`, pero se detuvo porque `Replace-ExactText` intentaba
reconocer el bloque nuevo mediante su representación textual exacta.

BL-MVP-030A ya había ejecutado Prettier sobre `route-manifest.ts`. Prettier conservó la semántica
pero cambió saltos de línea/indentación, así que:

- el alias antiguo `editorial:access` ya no existía;
- el texto nuevo sí existía semánticamente;
- pero ya no coincidía byte por byte con `$NewText`.

Por eso la puerta informó `No se encontro el ancla exacta`.

## Corrección

BL-MVP-030C no vuelve a modificar capacidades ya migradas. La puerta base ahora:

1. busca marcadores legacy por código, independientes del formato;
2. valida que estén presentes los `permission_code` canónicos requeridos;
3. si no quedan aliases legacy y están todos los canónicos, considera la transformación aplicada;
4. solo intenta reemplazos cuando todavía encuentra aliases antiguos;
5. vuelve a validar el estado final.

La comprobación pasa a ser semántica/idempotente frente a Prettier.

No cambia el motor de autorización, PostgreSQL, sesiones, scopes, CI ni permisos.
