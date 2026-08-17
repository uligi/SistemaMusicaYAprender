# Congelación y sometimiento de paquete educativo

## Autoridad

BL-MVP-048 transforma un `editorial.editorial_package` compatible de `DRAFT` a `SUBMITTED`. La operación corre dentro de una única transacción de backoffice y adquiere el mismo advisory lock por grabación utilizado durante el ensamblaje.

## Revalidación antes de congelar

El servidor no confía únicamente en el checklist que vio el navegador. Antes del `UPDATE`:

1. exige el ETag exacto del DRAFT;
2. vuelve a leer todos los `package_component`;
3. comprueba una letra, una sincronización, una traducción, un análisis y al menos un ejercicio;
4. comprueba que el checksum almacenado de cada componente siga igual al checksum actual de su revisión;
5. vuelve a comprobar que todas las dependencias apunten a la misma `lyrics_revision`;
6. bloquea revisiones terminales;
7. exige procedencia editorial para cada ejercicio;
8. vuelve a verificar derechos vigentes;
9. reconstruye el checksum del paquete usando la versión actual de catálogo y los checksums actuales.

Si cualquiera de esas condiciones cambió, la transacción no congela nada.

## Escritura atómica

La transacción confirma en conjunto:

- `editorial.editorial_package.status_code = 'SUBMITTED'`;
- `frozen_at = CURRENT_TIMESTAMP`;
- una fila `editorial.review_submission` en estado `SUBMITTED`;
- `checklist_version = 'BL-MVP-048.v1'`;
- auditoría `EDITORIAL.PACKAGE.SUBMIT`.

Si la inserción del sometimiento o la auditoría falla, el cambio de estado también se revierte.

## Inmutabilidad

La guarda física `editorial.guard_package_component_mutable()` permite modificar componentes solamente mientras el paquete está en `DRAFT`. Una vez sometido, BL047 tampoco puede actualizar su checksum porque sus escrituras exigen `status_code = 'DRAFT' AND frozen_at IS NULL`.

El paquete congelado se conserva como evidencia. Como BL047 busca únicamente un DRAFT abierto, una edición posterior crea el siguiente `package_no` en vez de reabrir o sobrescribir el paquete sometido.

## Separación de responsabilidades

BL-MVP-048 no escribe:

- `editorial.review_assignment`;
- `editorial.review_decision`;
- `editorial.publication`;
- `editorial.publication_component`.

BL-MVP-049 conserva asignación/checklist/decisión y BL-MVP-050 conserva la publicación atómica.

## UX de UI-MVP-026

La pantalla se reorganiza como workspace de escritorio:

- estado del DRAFT arriba;
- pasos de selección a la izquierda;
- checklist, último sometimiento y acción de congelación a la derecha;
- panel lateral sticky solo en escritorio;
- colapso a una columna en pantallas estrechas;
- mensaje explícito cuando la selección visible aún no fue guardada;
- navegación contextual `Paquete y revisión` desde las pantallas de la canción.
