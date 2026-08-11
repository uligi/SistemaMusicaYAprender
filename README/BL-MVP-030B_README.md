# BL-MVP-030B — restaurar salida incremental TypeScript antes del inventario

## Motivo

BL-MVP-030A terminó correctamente, pero su `npm run typecheck` modificó el archivo rastreado:

`apps/web/tsconfig.app.tsbuildinfo`

Ese archivo es una salida incremental de TypeScript. La puerta base BL-MVP-030 ejecutaba el
inventario Git **antes** de restaurarlo y por eso lo interpretó como un cambio ajeno al paquete.

No es un cambio funcional de BL-MVP-030.

## Corrección

030B hace dos ajustes:

- restaura de forma segura `apps/web/tsconfig.app.tsbuildinfo` cuando está modificado en el working
  tree y no está staged;
- mueve esa restauración al inicio de `apply-bl-mvp-030.ps1`, antes de validar el inventario.

También actualiza `apply-bl-mvp-030a.ps1` para que futuras ejecuciones de 030A restauren ese archivo
después de TypeScript.

Ningún instalador hace `git add`, commit o push.
