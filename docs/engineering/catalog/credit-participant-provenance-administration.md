# BL-MVP-039 — Créditos, participantes y procedencia

Este incremento completa la atribución y la procedencia previas a derechos. La grabación sigue siendo el objeto canónico de referencia.

## Garantías

- `catalog.recording_credit` conserva participante, rol y orden.
- Una identidad conocida usa `artist_id`; el nombre visible no es la clave.
- Una identidad todavía no resuelta conserva `artist_id = NULL` y `PENDING_IDENTITY`.
- `catalog.source_reference` conserva tipo, cita, localizador y momento de consulta.
- `editorial.provenance_record` enlaza cada crédito con su fuente.
- La verificación se representa en la relación de procedencia como `CREDIT_VERIFIED`, `CREDIT_UNVERIFIED` o `CREDIT_PENDING_IDENTITY`.
- Fuente + crédito + procedencia + auditoría se confirman en una sola transacción.
- No se modifica ni elimina historial.
- Derechos, usos, territorios y vigencias quedan fuera de BL-MVP-039 y pertenecen a BL-MVP-040.

## Menú lateral del backoffice

BL-MVP-039 también corrige la deuda de navegación del panel interno. El shell previo filtraba opciones con nombres de capability que no correspondían a los códigos efectivos y generaba enlaces dinámicos con el literal `ejemplo`.

`BackofficeSidebar` usa `routeManifest` y las capabilities reales de la sesión. Muestra grupos Editorial y Administración, genera enlaces contextuales solo cuando existe un UUID real y nunca convierte la visibilidad del menú en autorización.

En móvil el panel se apila, conserva objetivos táctiles y evita scroll horizontal.
