# BL-MVP-031C — corregir selector Playwright ambiguo de Rol

## Primera falla observada

La puerta completa de BL-MVP-031 superó TypeScript, Prettier, frontend build y compilación .NET.
Playwright ejecutó 17 pruebas: 16 pasaron y una falló en
`tests/E2ETests/role-management.spec.ts`.

El fallo fue:

```text
strict mode violation: getByLabel('Rol') resolved to 2 elements
```

El selector coincidió tanto con la región accesible `Roles y permisos` como con el `<select>`
etiquetado `Rol`.

## Corrección

BL-MVP-031C cambia únicamente ese selector a coincidencia exacta:

```ts
page.getByLabel('Rol', { exact: true });
```

No cambia la aplicación ni la semántica accesible. La prueba sigue localizando el control por su
nombre accesible, pero ya no acepta coincidencias parciales con `Roles y permisos`.

## Validación

031C ejecuta:

- Prettier sobre el test y los Markdown del correctivo;
- `npm run typecheck:e2e`;
- únicamente `role-management.spec.ts`;
- restauración defensiva de `tsconfig.app.tsbuildinfo`;
- `git diff --check`.

No cambia C#, PostgreSQL, autorización, auditoría, UI ni contratos HTTP.
