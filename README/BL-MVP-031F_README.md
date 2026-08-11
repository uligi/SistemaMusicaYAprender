# BL-MVP-031F — preservar el feedback tras grant/revoke

## Primera falla observada

Después de corregir los selectores Playwright, la prueba alcanzó el botón `Asignar rol`, pero no
encontró el mensaje:

```text
Asignación aplicada y auditada.
```

## Causa

La operación `grant()` sí establece el mensaje de éxito, pero inmediatamente después ejecuta:

```ts
await loadAssignments();
```

y `loadAssignments()` comienza con:

```ts
setMessage('');
setError('');
```

Por tanto el propio refresco de la lista borra el feedback que acaba de crear la mutación. El mismo
patrón existe en `revoke()`.

## Corrección

031F convierte `loadAssignments()` en una operación que puede preservar feedback y devuelve si la
recarga fue exitosa.

Después de grant/revoke:

- se refresca la lista con `clearFeedback: false`;
- si la recarga funciona, se publica el mensaje normal de éxito;
- si falla la recarga, se mantiene un mensaje que distingue que la mutación sí se aplicó pero la
  lista no pudo actualizarse.

El botón manual `Consultar asignaciones` conserva el comportamiento anterior y limpia feedback.

## Validación

031F ejecuta Prettier, typecheck web, typecheck E2E, el spec aislado `role-management.spec.ts`,
restaura `tsconfig.app.tsbuildinfo` y ejecuta `git diff --check`.

No cambia PostgreSQL, permisos, CSRF, auditoría ni contratos HTTP.
