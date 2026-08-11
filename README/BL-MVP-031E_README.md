# BL-MVP-031E — corregir selector Playwright ambiguo de Motivo

## Primera falla observada

031D ya permitió seleccionar correctamente `Rol *`. La prueba avanzó al siguiente control y falló
con `strict mode violation` porque:

```ts
getByLabel('Motivo');
```

coincidió con dos inputs:

- `Motivo`;
- `Motivo para retirar`.

La propia salida de Playwright identificó el primer input como:

```ts
getByRole('textbox', { name: 'Motivo', exact: true });
```

## Corrección

031E sustituye únicamente el selector ambiguo por el locator exacto que Playwright reportó:

```ts
page.getByRole('textbox', { name: 'Motivo', exact: true });
```

No se modifica la aplicación ni sus nombres accesibles.

## Validación

031E ejecuta Prettier, `typecheck:e2e`, únicamente `role-management.spec.ts`, restaura
`tsconfig.app.tsbuildinfo` y ejecuta `git diff --check`.

No cambia C#, PostgreSQL, autorización, auditoría, UI ni contratos HTTP.
