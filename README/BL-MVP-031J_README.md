# BL-MVP-031J — acotar `EDITOR` a la lista de asignaciones

## Primera falla observada

031I confirmó que el build actualizado ya se estaba sirviendo. El mensaje de éxito apareció y la
prueba avanzó hasta la verificación de `EDITOR`.

El locator:

```ts
page.getByText('EDITOR', { exact: true });
```

resolvió dos elementos:

- la opción `EDITOR` del `<select>` de roles;
- el `<strong>EDITOR</strong>` dentro de la lista de asignaciones.

## Corrección

031J acota la aserción al contenedor accesible que representa la lista:

```ts
page.getByLabel('Asignaciones de la cuenta').getByText('EDITOR', { exact: true });
```

Así la prueba verifica específicamente la asignación recién renderizada y no la opción del
formulario.

## Validación

031J conserva la lección de 031I: ejecuta `npm run build` antes del E2E aislado. Luego valida
Prettier, TypeScript web, TypeScript E2E, `role-management.spec.ts` y `git diff --check`.

No cambia la aplicación, PostgreSQL, autorización, auditoría, CSRF ni contratos HTTP.
