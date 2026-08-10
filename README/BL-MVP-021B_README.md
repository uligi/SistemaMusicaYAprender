# BL-MVP-021B — Corrección de spawn de npm.cmd en Windows

## Fallo observado

El segundo `apply-bl-mvp-021.ps1` llegó correctamente al verificador BL-MVP-021, pero el proceso que debía invocar `tsc` no arrancó de forma válida en Windows.

La evidencia fue:

```text
AssertionError [ERR_ASSERTION]: El compilador TypeScript del proyecto no pudo emitir el fixture BL-MVP-021.
```

sin diagnósticos de TypeScript debajo del mensaje.

## Causa

La versión BL-MVP-021A usaba en Windows:

```js
spawnSync('npm.cmd', ...)
```

Los archivos `.cmd` de Windows requieren un intérprete de comandos. Node documenta que deben ejecutarse mediante `cmd.exe`, `exec()` o un shell.

Al no iniciarse correctamente `npm.cmd`, `spawnSync` no produjo stdout/stderr de TypeScript y el verificador solo mostró el `assert.fail` genérico.

## Corrección

En Windows el verificador ahora ejecuta explícitamente:

```text
cmd.exe /d /s /c "npm.cmd exec -- tsc -p <tsconfig temporal>"
```

mediante `process.env.ComSpec` cuando está disponible.

En Unix/Linux/macOS continúa ejecutando `npm` directamente.

Además, si el proceso vuelve a fallar, el verificador ahora imprime:

- `compile.error`;
- stdout;
- stderr;
- exit status;
- signal.

Así, cualquier fallo posterior del compilador real mostrará su diagnóstico exacto.

## Alcance

BL-MVP-021B no cambia:

- cliente HTTP;
- ProblemDetails;
- ETag;
- If-Match;
- reintentos;
- Idempotency-Key;
- caché;
- nginx;
- CI;
- dependencias;
- backend;
- SQL;
- migraciones.

Solo corrige la forma en que el arnés BL-MVP-021 invoca el compilador en Windows.

## Preflight

El verificador corregido pasó:

```text
node --check scripts/frontend/verify-http-client.mjs
OK

node scripts/frontend/verify-http-client.mjs
OK: BL-MVP-021 cliente HTTP tipado verificado: cancelación, ETag, ProblemDetails, reintentos seguros y estados guardando/confirmado.
```

La validación autoritativa sigue siendo el reapply en Windows con Node 24.18.0 y TypeScript 7.0.2 del proyecto.
