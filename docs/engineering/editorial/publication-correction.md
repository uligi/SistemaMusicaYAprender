# Corrección y reversión — BL-MVP-051

Una publicación histórica es evidencia y no se reescribe.

## Acciones

- **WITHDRAW**: cierra la publicación ACTIVE y registra un caso `WITHDRAWAL`.
- **RESTORE**: revalida una publicación histórica y crea una nueva publicación activa con sus componentes exactos.
- **REVERT**: vuelve efectiva una versión histórica mediante una nueva publicación; no elimina versiones posteriores.
- **SUBSTITUTE**: toma un paquete corregido `APPROVED` de la misma grabación, revalida componentes/derechos y lo activa atómicamente.

## Concurrencia e idempotencia

- advisory lock por grabación;
- `If-Match`;
- `Idempotency-Key`;
- unique físico `(correlation_id, action_code)`.

No hay `DELETE` sobre el historial editorial.
