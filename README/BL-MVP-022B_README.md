# BL-MVP-022B — Alineación de Playwright Core y `reducedMotion`

## Fallo observado

Después de BL-MVP-022A, el apply avanzó correctamente por:

- actualización de lockfile;
- `npm ci`;
- instalación de Chromium;
- formato;
- regresiones BL018-BL021;
- verificador estructural BL022;
- build frontend;
- build .NET.

La puerta se detuvo en:

```text
npm run typecheck:e2e
```

con dos diagnósticos TypeScript.

### TS2322 — dos tipos `Page` incompatibles

El error mostraba dos rutas de tipos distintas:

```text
node_modules/playwright/node_modules/playwright-core/...
node_modules/playwright-core/...
```

`@playwright/test@1.62.0` depende de `playwright@1.62.0`, y este depende exactamente de
`playwright-core@1.62.0`.

Por su parte, `@axe-core/playwright@4.11.3` declara `playwright-core >= 1.0.0` como peer dependency.

Sin un pin directo en la raíz, npm pudo resolver dos copias/versiones de `playwright-core`. Aunque ambas
representan una `Page`, TypeScript ve contratos diferentes y el constructor de `AxeBuilder` rechaza la
`Page` del fixture de `@playwright/test`.

### TS2769 — `reducedMotion`

En Playwright 1.62, la forma documentada y tipada de pasar esa opción desde `use` es:

```ts
use: {
  contextOptions: {
    reducedMotion: 'reduce',
  },
}
```

El parche original la colocaba directamente en `use`, lo que no coincide con `TestOptions` 1.62.

## Corrección

BL-MVP-022B modifica:

- `package.json`
- `tests/E2ETests/playwright.config.ts`
- `scripts/frontend/verify-e2e-harness.mjs`

y agrega este README.

### Dependencia alineada

Se fija explícitamente:

```json
"playwright-core": "1.62.0"
```

en la raíz, igualando exactamente la versión requerida por `playwright@1.62.0`.

Al volver a ejecutar el apply:

1. `npm install --package-lock-only` actualiza `package-lock.json`;
2. `npm ci` reconstruye `node_modules` desde el lock;
3. axe y Playwright Test resuelven el mismo `playwright-core@1.62.0`.

No se usa cast para esconder la incompatibilidad de tipos.

### Movimiento reducido

La configuración cambia a:

```ts
contextOptions: {
  reducedMotion: 'reduce',
},
```

La intención funcional se conserva: las pruebas siguen ejecutándose con movimiento reducido.

### Verificador

El verificador ahora exige:

- `@playwright/test = 1.62.0`;
- `@axe-core/playwright = 4.11.3`;
- `playwright-core = 1.62.0`;
- el lockfile con `node_modules/playwright-core` en `1.62.0`;
- `reducedMotion` dentro de `contextOptions`.

## Alcance

No cambia:

- aplicación React;
- componentes;
- rutas;
- cliente HTTP;
- backend;
- base de datos;
- migraciones;
- nginx;
- Docker.

Solo corrige el arnés E2E y su resolución de dependencias.

## Siguiente ejecución

Extraer el ZIP de BL-MVP-022B en la raíz y ejecutar de nuevo:

```powershell
.\scripts\apply-bl-mvp-022.ps1
```

No hacer `git add`, commit ni push hasta revisar el resultado completo.
