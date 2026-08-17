# BL-MVP-049 — Ejecutar revisión, checklist y decisión

## Alcance

F2 · EP-06 · 13 SP
Traza: CU-MVP-21 · UI-MVP-027 · CE-09, CE-10, CE-14.

Resultado vinculante:

> Asignación, conflicto de interés, checklist y decisiones son append-only; rechazar devuelve motivos accionables.

## Frontera

BL049 **no publica**. La creación de `editorial.publication`,
`editorial.publication_component` y disponibilidad pertenece a BL-MVP-050.

BL049 toma el paquete exacto congelado por BL048 y nunca resuelve componentes
por `latest`.

## Comportamiento

- GET de revisión por grabación con paquete/sometimiento exactos.
- Asignación explícita de una cuenta con `EDITORIAL.REVIEW` vigente.
- Se bloquea creador/sometedor como revisor independiente.
- Reasignar crea una nueva fila; no reescribe la asignación histórica.
- `conflict_declared` es una declaración monotónica `false -> true`, auditada y
  nunca se revierte. La limitación física de la línea base impide crear otra fila
  para el mismo `(submission, reviewer, scope)`.
- Un conflicto bloquea la decisión de esa asignación.
- Cada asignación admite como máximo una `review_decision`, garantizado también
  por el UNIQUE físico existente.
- `APPROVED` exige checklist sin bloqueos.
- `REJECTED` exige motivo textual que la UI presenta como acción correctiva.
- La decisión mueve únicamente el estado de
  `review_submission`/`editorial_package`; no altera `package_component`.
- Todas las escrituras usan CSRF, If-Match, advisory lock y auditoría primaria.

## UI-MVP-027

Ruta:

`/administracion/publicaciones/{id}`

La pantalla separa:

1. paquete congelado;
2. checklist;
3. asignación/conflicto;
4. decisión de doble confirmación.

Un usuario con `EDITORIAL.REVIEW` puede revisar; uno con
`EDITORIAL.PUBLISH` puede asignar. La publicación sigue ausente.

## Tema visual

BL049 consume exclusivamente los tokens semánticos de BL018. No implementa el
dark mode dentro de este incremento y no agrega colores crudos.

## Verificación focal

```powershell
& "C:\Program Files\Git\bin\bash.exe" `
  scripts/ci/editorial/verify-review-workflow.sh

npm.cmd run test:e2e -- editorial-review-workflow.spec.ts
```

Después continúan build, tests, E2E completo, `verify-running`, higiene y CI.
