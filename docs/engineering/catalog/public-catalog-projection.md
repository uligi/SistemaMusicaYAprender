# Proyección pública elegible del catálogo

## Propósito

BL-MVP-041 crea una proyección derivada y reemplazable. No convierte la proyección en fuente de verdad: `editorial.publication`, `editorial.publication_availability` y el catálogo canónico siguen decidiendo si una apertura puede servirse.

## Reconstrucción

El worker toma únicamente publicaciones `ACTIVE` dentro de vigencia, con al menos una disponibilidad `PUBLIC` activa y vigente, artista primario activo y una fuente YouTube canónica elegible. La instantánea conserva checksum de publicación, identidad/version de fuente y checksums de componentes publicados.

La operación usa un advisory lock transaccional para evitar dos rebuild concurrentes. `ON CONFLICT` actualiza solo si cambió la instantánea y las filas que dejaron de ser elegibles se eliminan. Por eso el worker necesita `DELETE` solo sobre `editorial.published_package_projection`.

## Revalidación al abrir

La lectura pública no confía en que la proyección siga vigente. Cada apertura vuelve a comprobar:

- publicación `ACTIVE` y vigente;
- territorio exacto solicitado;
- audiencia `PUBLIC`;
- idioma exacto o disponibilidad genérica;
- disponibilidad activa y vigente;
- artista primario activo;
- misma fuente de YouTube y versión registrada en la proyección;
- estado canónico de la fuente (`ACTIVE` o `PUBLISHED`).

Si cualquiera cambia, el endpoint responde como no disponible aunque la fila derivada todavía no haya sido retirada por el worker.

## Límites de alcance

BL-MVP-041 no implementa la búsqueda `tsvector/pg_trgm` de BL-MVP-042, la ficha pública de BL-MVP-043 ni UI-MVP-017. La bandeja editorial real es BL-MVP-044 y depende de BL-MVP-041.
