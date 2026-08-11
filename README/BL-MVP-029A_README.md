# BL-MVP-029A — corrección de formato Prettier

## Motivo

La primera ejecución de `scripts/apply-bl-mvp-029.ps1` pasó:

- transformación controlada de configuración/Compose;
- toolchain fijado;
- secret store;
- `npm ci`;
- instalación de Chromium;
- secret scan;
- restore/build .NET;
- TypeScript.

La puerta se detuvo únicamente en `npm run format:check` por:

```text
docs/engineering/security/login-abuse-and-session-limits.md
tests/E2ETests/personal-login-abuse.spec.ts
```

No se observó un error funcional, de tipos o de seguridad en esa ejecución.

## Corrección

BL-MVP-029A usa el Prettier local fijado por el repositorio (`3.9.6`) y ejecuta `--write` únicamente
sobre los dos archivos reportados. Luego valida:

- `prettier --check`;
- `npm run typecheck:e2e`;
- `git diff --check`.

El paquete también entrega una versión completa reconciliada de `scripts/apply-bl-mvp-029.ps1` para
que la reejecución de la puerta reconozca los tres artefactos 029A y no produzca un falso RED de
inventario.

## Alcance

No cambia límites 5/20, ventana de 15 minutos, HMAC, CSRF, cookies, persistencia, Compose, API,
PostgreSQL, CI ni criterios de aceptación. Es un correctivo de formato + gobernanza del instalador.

Después de 029A debe ejecutarse nuevamente `scripts/apply-bl-mvp-029.ps1` completo, sin `Skip*`.
