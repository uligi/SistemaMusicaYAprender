# BL-MVP-030 — Implementar motor de permisos efectivos y alcance

Fase F1 · EP-03 · Historia · 13 SP.

Traza: `CU-03,23; UI-007,029; CE-01,09`.

Dependencias: BL-MVP-013, BL-MVP-026 y BL-MVP-035.

Resultado vinculante:

> Cada comando/consulta evalúa permiso, ámbito y vigencia con denegación por defecto; ocultar enlaces
> no sustituye la autorización.

## Corte implementado

- motor server-side sobre `role`, `permission`, `role_permission`, `role_assignment` y
  `access_scope`;
- baseline seguro `STUDENT` para cuenta registrada activa/verificada;
- roles elevados solo mediante asignación explícita vigente;
- sin caché de autorización;
- scopes `GLOBAL`, `MODULE`, `OBJECT`, sin expresión ejecutable;
- denegación por defecto y fallo cerrado si PostgreSQL no está disponible;
- cookie sin claims de rol efectivo;
- `/api/v1/auth/session` publica roles/capacidades recalculados solo para UX;
- route manifest usa `permission_code` canónicos;
- gate de servidor reusable;
- `/api/v1/security/authorization/catalog` exige `SECURITY.MANAGE_ROLES` global;
- pruebas unitarias de scope, E2E de visibilidad y smoke real PostgreSQL/API.

No gestiona asignaciones, no incorpora MFA y no implementa la auditoría primaria completa.
