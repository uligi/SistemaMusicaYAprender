# BL-MVP-031H — usar la respuesta canónica de la mutación en la UI

## Primera falla observada

031G corrigió el error de tipos y el test volvió a alcanzar el grant, pero siguió sin encontrar
`Asignación aplicada y auditada.`.

El patrón de refrescar inmediatamente después de una mutación añadía una segunda dependencia de red
antes de presentar el resultado de una operación que ya había sido confirmada por el servidor.

## Corrección

031H elimina esa segunda lectura inmediata después de grant/revoke.

La respuesta de ambas mutaciones ya contiene la `assignment` canónica devuelta por la API. La UI
ahora la utiliza directamente para actualizar su estado local:

- grant inserta o reemplaza la asignación por `assignmentId`;
- revoke reemplaza la asignación afectada por la versión devuelta por el servidor;
- el feedback de éxito se publica inmediatamente después de incorporar la respuesta;
- `Consultar asignaciones` sigue haciendo una lectura explícita cuando el administrador quiere
  reconciliar la lista completa.

Esto evita que una lectura posterior o un mock de lectura impida mostrar el resultado ya confirmado
de la mutación.

## Validación

031H ejecuta Prettier, typecheck web, typecheck E2E, el spec aislado de gestión de roles, restaura
`tsconfig.app.tsbuildinfo` y ejecuta `git diff --check`.

No cambia PostgreSQL, permisos efectivos, CSRF, auditoría ni contratos de la API.
