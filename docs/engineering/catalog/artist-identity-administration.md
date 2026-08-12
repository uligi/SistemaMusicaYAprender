# Identidad editorial de artista — BL-MVP-037

## Invariantes

1. `artist_id` es la identidad estable y opaca.
2. `canonical_name` no es clave ni criterio de autorización.
3. Cada alta conserva una forma canónica preferida en `artist_alias`.
4. Alias, lectura y nombres localizados se comparan mediante `normalized_text`, pero el texto mostrado conserva Unicode.
5. Un posible duplicado se presenta para resolución; nunca se fusiona automáticamente.
6. La creación es atómica: artista, alias y auditoría se confirman o revierten juntos.
7. Un reintento con la misma `Idempotency-Key` no crea otra identidad lógica.
8. No se consulta ningún servicio externo para detectar duplicados.

## Autorización

Los endpoints editoriales exigen permiso efectivo `EDITORIAL.DRAFT` con alcance de módulo `M02`. Un actor con permiso limitado a otro módulo u objeto no obtiene capacidad de alta por conocer la URL.

Se usa la identidad PostgreSQL backoffice separada que ya posee `SELECT/INSERT/UPDATE` sobre `catalog` y `INSERT` sobre `security.audit_event`; la API ordinaria conserva acceso de solo lectura al catálogo.

## Normalización

La cadena mostrada se normaliza a NFC y conserva escritura original. Para coincidencias:

- NFKC;
- espacios internos colapsados;
- comparación invariante sin distinción de mayúsculas para escrituras que la poseen.

La normalización es un dato auxiliar de búsqueda; jamás reemplaza `artist_id`.

## Duplicados

La simulación reúne la forma canónica y los alias enviados y calcula coincidencias exactas o por similitud interna PostgreSQL. Una coincidencia no decide que dos artistas sean la misma persona o agrupación: únicamente obliga a revisión humana antes de crear otra identidad.

## Alcance deliberadamente diferido

BL-MVP-037 no crea obra musical, grabación, fuente de YouTube, créditos, derechos, publicación, redirección ni fusión de artistas. Esos objetos continúan en los PBI siguientes de F2.
