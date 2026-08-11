# BL-MVP-031D — alinear el selector con el nombre accesible real

## Primera falla observada

031C eliminó la ambigüedad de coincidencia parcial, pero el test quedó esperando:

```ts
getByLabel('Rol', { exact: true });
```

y agotó los 30 segundos sin encontrar el control.

La evidencia anterior de Playwright ya mostraba el `<select>` como:

```text
getByLabel('Rol *')
```

El asterisco de campo requerido forma parte del nombre que Playwright está resolviendo para este
control en el harness actual.

## Corrección

031D cambia únicamente el selector a:

```ts
getByLabel('Rol *', { exact: true });
```

Esto conserva coincidencia exacta y evita volver a coincidir con la región `Roles y permisos`.

No se modifica la aplicación ni la accesibilidad; se alinea la prueba con el nombre accesible que
Playwright reportó realmente.

## Validación

031D ejecuta Prettier, `typecheck:e2e`, únicamente `role-management.spec.ts`, restaura
`tsconfig.app.tsbuildinfo` y ejecuta `git diff --check`.
