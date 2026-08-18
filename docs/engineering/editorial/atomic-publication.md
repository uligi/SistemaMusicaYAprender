# Publicación atómica — BL-MVP-050

La autoridad es PostgreSQL y el agregado editorial exacto aprobado.

## Invariantes

- No existe publicación sin paquete congelado y decisión `APPROVED`.
- `publication_component.source_component_id` apunta al `package_component` exacto.
- El checksum publicado conserva el checksum del paquete aprobado.
- La disponibilidad no excede la vigencia de derechos usada para autorizarla y exige el alcance `WEB`/`DISPLAY` ya definido por BL040.
- Una publicación anterior se cierra como `SUPERSEDED`, no se confunde con el nuevo contenido.
- `publication`, componentes, disponibilidad, acción, auditoría y outbox comparten transacción.
- La proyección pública es derivada y nunca concede autoridad.

## Reintentos y concurrencia

La UI genera una `Idempotency-Key` UUID al preparar la confirmación. El servidor usa esa clave como `correlation_id` de `publication_action`; el índice único físico hace deduplicable la operación lógica.

También se usan `If-Match`, advisory transaction lock por `recording_id` y comprobaciones de estado. Un conflicto responde 412 y no deja publicación parcial.
