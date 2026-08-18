# BL-MVP-050 — Publicar paquete y disponibilidad de forma atómica

## Alcance

F2 · EP-06 · 13 SP
Traza: CU-MVP-21 · UI-MVP-027 · CE-02-06, CE-09, CE-10, CE-14.
Dependencias: BL-MVP-040 y BL-MVP-049.

Resultado vinculante:

> Publicación, disponibilidad, auditoría y outbox se confirman en una transacción y no admiten vigencias incompatibles.

## Contrato

BL050 parte del **paquete exacto aprobado** por BL049. No resuelve componentes por `latest`.

En una sola transacción de backoffice:

1. revalida `editorial_package` congelado y `APPROVED`;
2. exige `review_submission` y `review_decision` aprobados;
3. revalida checksums de las revisiones exactas;
4. exige alcance de derechos explícito para territorio/idioma y el uso web `WEB`/`DISPLAY`;
5. cierra la publicación ACTIVE anterior como histórica;
6. crea `editorial.publication`;
7. copia `package_component` a `publication_component`;
8. crea `publication_availability`;
9. registra `publication_action`, auditoría y outbox;
10. mueve el paquete a `PUBLISHED`.

Cualquier excepción revierte toda la transacción.

## Idempotencia y concurrencia

- `If-Match` evita confirmar sobre estado obsoleto.
- `Idempotency-Key` UUID se conserva en `publication_action.correlation_id`.
- `(correlation_id, action_code)` impide duplicar la operación lógica.
- advisory lock serializa publicación/corrección de una grabación.

## Proyección pública

BL050 **no escribe** `published_package_projection`. La publicación canónica y el outbox se confirman primero; el worker reconstruye proyecciones. PostgreSQL canónico sigue siendo autoridad.

## UI-MVP-027

La pantalla `/administracion/publicaciones/{id}` conserva revisión/checklist de BL049 y añade el panel **5. Publicación atómica** solo para `EDITORIAL.PUBLISH`.

La acción exige territorio, idioma, audiencia, motivo, resumen de impacto y doble confirmación.

## Verificación focal

```powershell
& "C:\Program Files\Git\bin\bash.exe" `
  scripts/ci/editorial/verify-atomic-publication.sh

npm.cmd run test:e2e -- editorial-publication.spec.ts
```
