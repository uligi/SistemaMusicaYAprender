# BL-MVP-031G — adaptar `loadAssignments` al evento React

## Primera falla observada

031F cambió `loadAssignments` para aceptar opciones:

```ts
loadAssignments(options?: { clearFeedback?: boolean }): Promise<boolean>
```

El botón manual seguía entregando esa función directamente a `onClick`:

```tsx
onClick = { loadAssignments };
```

React invoca un `MouseEventHandler` con el evento como primer argumento. Por eso TypeScript rechazó
la asignación: un `MouseEvent` no es el objeto de opciones de `loadAssignments`.

## Corrección

031G adapta explícitamente el evento del botón:

```tsx
onClick={() => void loadAssignments()}
```

Así el evento React no se reenvía accidentalmente como configuración y `loadAssignments` conserva su
API interna.

## Validación

031G ejecuta Prettier, typecheck web, typecheck E2E, el spec aislado de gestión de roles, restaura
`tsconfig.app.tsbuildinfo` y ejecuta `git diff --check`.

No cambia PostgreSQL, permisos, auditoría, CSRF ni contratos HTTP.
