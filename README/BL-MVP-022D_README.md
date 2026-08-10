# BL-MVP-022D — Spec Playwright compatible con carga CommonJS/ESM

## Fallo observado

Después de BL-MVP-022C:

- `typecheck:e2e` pasó;
- Playwright logró cargar `playwright.config.ts`;
- el runner llegó a descubrir los archivos de pruebas;

pero falló cargando:

```text
tests\E2ETests\base-accessibility.spec.ts
```

con:

```text
Warning: Failed to load the ES module ...
SyntaxError: Cannot use 'import.meta' outside a module
Error: No tests found
```

## Causa

BL-MVP-022C eliminó `import.meta` del archivo de configuración, pero
`base-accessibility.spec.ts` todavía conservaba:

```ts
dirname(fileURLToPath(import.meta.url));
```

El spec está en el mismo árbol `tests/E2ETests`, fuera del package ESM de
`apps/web`. Playwright puede transpilar sus imports TypeScript, pero `import.meta`
sigue siendo inválido cuando el archivo termina evaluándose en modo CommonJS.

Por eso el runner no pudo cargar el spec y terminó reportando `No tests found`.

## Corrección

BL-MVP-022D modifica:

- `tests/E2ETests/base-accessibility.spec.ts`
- `scripts/frontend/verify-e2e-harness.mjs`

y agrega este README.

El spec ahora usa:

```ts
const repoRoot = process.cwd();
```

y conserva las rutas de evidencia mediante:

```ts
join(repoRoot, 'artifacts/e2e');
```

Se eliminan del spec:

- `import.meta`;
- `fileURLToPath`;
- `dirname`;
- `resolve`.

## Verificador

El verificador BL-MVP-022 ahora exige también que el spec:

- use `process.cwd()`;
- no contenga `import.meta`;
- no contenga `fileURLToPath`.

Así, tanto el config como el spec quedan protegidos contra la misma regresión de
modo de módulo.

## Alcance

No cambia:

- aplicación React;
- rutas;
- componentes;
- cliente HTTP;
- backend;
- PostgreSQL;
- nginx;
- Docker;
- comportamiento funcional de las pruebas.

Las pruebas siguen validando:

- Chromium;
- 320x800;
- teclado;
- foco visible;
- axe;
- ausencia de scroll horizontal;
- japonés;
- UI-EST-07;
- UI-EST-03;
- capturas deterministas.

## Siguiente ejecución

Extraer el ZIP sobre la raíz y ejecutar:

```powershell
.\scripts\apply-bl-mvp-022.ps1
```

No hacer `git add`, commit ni push hasta revisar la salida completa.
