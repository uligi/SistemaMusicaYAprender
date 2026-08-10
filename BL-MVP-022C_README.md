# BL-MVP-022C — Config Playwright compatible con carga CommonJS/ESM

## Fallo observado

Después de BL-MVP-022B ya pasaron:

- dependencias y lockfile;
- Chromium;
- regresiones BL018-BL021;
- verificador estructural BL022;
- build frontend;
- build .NET;
- `typecheck:e2e`.

El fallo ocurrió al iniciar realmente Playwright:

```text
Warning: Failed to load the ES module: tests\E2ETests\playwright.config.ts
SyntaxError: Cannot use 'import.meta' outside a module
```

## Causa

El `playwright.config.ts` estaba fuera de `apps/web`, por lo que no heredaba el
`"type": "module"` del `apps/web/package.json`.

La configuración usaba:

```ts
fileURLToPath(import.meta.url);
```

Playwright 1.62 transpila/carga la configuración TypeScript de forma que, en este
repositorio Windows sin `"type": "module"` en la raíz, el archivo terminó ejecutándose
como CommonJS. En CommonJS `import.meta` no es válido.

No es necesario convertir todo el repositorio a ESM ni agregar `"type": "module"` a la
raíz, porque eso cambiaría el modo de ejecución de otros scripts del proyecto.

## Corrección

BL-MVP-022C modifica:

- `tests/E2ETests/playwright.config.ts`
- `scripts/frontend/verify-e2e-harness.mjs`

y agrega este README.

El config ahora calcula rutas con:

```ts
const repoRoot = process.cwd();
const configDirectory = join(repoRoot, 'tests/E2ETests');
```

Los scripts npm del proyecto se ejecutan desde la raíz del package, por lo que este
cálculo funciona tanto en Windows local como en GitHub Actions.

Se eliminan:

```ts
import.meta.url;
fileURLToPath;
dirname;
resolve;
```

La configuración conserva:

- Chromium;
- viewport 320x800;
- es-CR;
- America/Costa_Rica;
- reducedMotion mediante `contextOptions`;
- artifacts;
- webServer Vite preview;
- 1 worker;
- 0 retries.

## Verificador

Ahora exige además:

- `process.cwd()` como raíz;
- `tests/E2ETests` como directorio de pruebas;
- ausencia de `import.meta` y `fileURLToPath`.

## Alcance

No cambia:

- React;
- rutas;
- componentes;
- cliente HTTP;
- backend;
- PostgreSQL;
- nginx;
- Docker.

Solo corrige la carga del archivo de configuración de Playwright.

## Siguiente paso

Extraer este ZIP en la raíz y ejecutar de nuevo:

```powershell
.\scripts\apply-bl-mvp-022.ps1
```

No hacer `git add`, commit ni push hasta revisar la salida completa.
