# BL-MVP-030A — corrección de formato Prettier

## Motivo

La primera ejecución de `scripts/apply-bl-mvp-030.ps1` aplicó correctamente las transformaciones de
autorización y aprobó:

- toolchain fijado;
- secret store;
- `npm ci`;
- instalación de Chromium;
- secret scan;
- restore/build inicial;
- TypeScript.

La puerta se detuvo únicamente en `npm run format:check` por:

```text
apps/web/src/app/router/route-manifest.ts
docs/engineering/security/effective-authorization.md
```

No se observó en esa ejecución un fallo del motor de permisos, del modelo de alcance, de TypeScript
ni de seguridad.

## Corrección

BL-MVP-030A usa el Prettier local fijado por el repositorio (`3.9.6`) y ejecuta `--write`
exclusivamente sobre esos dos archivos.

Después valida:

- `prettier --check`;
- `npm run typecheck`;
- `git diff --check`.

También incluye una versión completa reconciliada de `scripts/apply-bl-mvp-030.ps1` para que la
reejecución de la puerta reconozca los artefactos 030A y no produzca un falso RED de inventario.

## Alcance

No cambia la lógica server-side, los permisos, los ámbitos, PostgreSQL, cookies, sesiones, CI,
RLS ni criterios de aceptación. Es un correctivo de formato y gobernanza del instalador.
