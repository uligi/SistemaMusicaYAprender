# Revisión, checklist y decisión editorial

BL-MVP-049 implementa la mitad de revisión de CU-MVP-21 sin adelantar la
publicación atómica de BL-MVP-050.

## Invariantes

- El objeto revisado es el `editorial_package` congelado por BL048.
- El conjunto de `package_component` y sus checksums no se modifica.
- El revisor es explícito y debe poseer `EDITORIAL.REVIEW` efectivo para M15 y
  la grabación.
- El creador/sometedor no se considera revisor independiente.
- La reasignación agrega historia; no elimina filas anteriores.
- El conflicto se declara una sola vez y solo avanza de `false` a `true`.
- La declaración queda además registrada en `security.audit_event`.
- Un conflicto bloquea decisiones.
- `review_decision` es append-only y la restricción física admite una decisión
  por asignación.
- La decisión conserva el checklist evaluado como JSON versionado.
- Aprobar exige checklist verde; rechazar conserva motivo accionable.
- `publication` y `publication_component` permanecen intactas.

## Concurrencia

Las mutaciones toman advisory lock por `recording_id` y exigen `If-Match`.
El ETag cubre paquete, estado del sometimiento, checksums, asignaciones,
conflictos y decisiones. Una vista obsoleta devuelve 412.

## Segregación

La visibilidad del cliente no concede autorización. Todos los endpoints
revalidan capacidad y alcance en servidor. Las operaciones privilegiadas
requieren la garantía reciente incorporada por BL032.

## Estado derivado

La evidencia final es `review_decision`. Como puntero operativo, la transacción
mueve `review_submission.status_code` y `editorial_package.status_code` a
`APPROVED` o `REJECTED`. Esto no reescribe la decisión ni los componentes.

`APPROVED` habilita posteriormente a BL050; no equivale a publicación.
