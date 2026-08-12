# BL-MVP-041 — Proyección pública elegible del catálogo

BL-MVP-041 implementa la proyección pública reconstruible que sirve como frontera entre el catálogo/editorial canónico y las historias públicas posteriores.

## Criterio vinculante

> La proyección solo incluye publicación vigente y es reconstruible; abrir siempre revalida la fuente canónica.

## Alcance

- `PublicCatalogProjectionService` reconstruye `editorial.published_package_projection` desde `publication`, disponibilidad vigente, catálogo y fuente de YouTube canónicos.
- El worker realiza una reconstrucción al iniciar y después de forma periódica.
- La reconstrucción es idempotente: no incrementa `projection_version` si la instantánea no cambió.
- Una publicación borrador, retirada, expirada, sin disponibilidad pública vigente o sin fuente canónica elegible no permanece en la proyección.
- La API de lectura revalida en cada apertura publicación, territorio, idioma, audiencia pública y la misma fuente/version canónica conservada por la proyección.
- El worker recibe `DELETE` únicamente sobre `editorial.published_package_projection`, porque la proyección es reconstruible y debe poder retirar filas obsoletas.
- No se implementan todavía búsqueda pública, ficha pública ni bandeja editorial. Esos alcances pertenecen a BL-MVP-042, BL-MVP-043 y BL-MVP-044.

## Pruebas

`scripts/ci/catalog/verify-public-catalog-projection.sh` comprueba con PostgreSQL, worker y API reales:

- inclusión de publicación activa y exclusión de borrador;
- idempotencia de rebuild;
- restricción territorial;
- revalidación de fuente canónica antes de servir;
- retirada de proyección cuando la fuente deja de ser elegible;
- reconstrucción con una fuente sustituta;
- expiración de disponibilidad;
- rechazo de contexto territorial inválido.
