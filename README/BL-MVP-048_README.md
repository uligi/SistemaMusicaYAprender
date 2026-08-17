# BL-MVP-048 — Congelar y someter paquete a revisión

## Resultado

Cuando un paquete DRAFT supera el checklist de compatibilidad, un actor con `EDITORIAL.SUBMIT` puede congelarlo y someterlo a revisión desde `UI-MVP-026`.

La operación:

- revalida revisiones, procedencia de ejercicios, derechos y checksum justo antes de congelar;
- exige CSRF e `If-Match`;
- cambia el paquete de `DRAFT` a `SUBMITTED` y fija `frozen_at`;
- crea `editorial.review_submission` con checklist `BL-MVP-048.v1`;
- registra `EDITORIAL.PACKAGE.SUBMIT` en auditoría;
- no crea asignaciones, decisiones ni publicación.

Después del sometimiento, `package_component` deja de ser mutable por la guarda física existente. El espacio de edición vuelve a un DRAFT vacío; al guardar otra selección, BL047 asigna el siguiente `package_no`, por lo que las nuevas ediciones no alteran el paquete congelado.

## UX incorporada

La misma entrega corrige la experiencia observada en escritorio:

- `UI-MVP-026` usa el ancho disponible del backoffice;
- formulario y panel de estado/checklist se organizan en dos columnas en escritorio y una columna en pantallas estrechas;
- el checklist permanece visible en un panel lateral sticky cuando hay espacio;
- se diferencia selección local sin guardar de estado confirmado por servidor;
- el último sometimiento queda visible;
- `Paquete y revisión` se incorpora a la navegación contextual de cada canción;
- la pantalla de paquete vuelve a mostrar la navegación contextual, evitando depender de conocer la URL manualmente.

## Trazabilidad

- BL-MVP-048
- CU-MVP-20
- UI-MVP-026
- CE-09
- CE-14
- CA-MVP-115-120
- Dependencia: BL-MVP-047

## Límites

BL-MVP-048 no asigna revisores, no emite decisión y no publica. Esas responsabilidades continúan en BL-MVP-049 y BL-MVP-050.
