# BL-MVP-014 — Crear DbContext y configuraciones EF Core por esquema

## Resultado aceptable

> El modelo refleja nombres, claves, concurrencia y relaciones físicas sin generar una migración que reescriba la inicial.

## Decisión

La arquitectura prohíbe compartir `DbContext`, repositorios genéricos o entidades mutables
entre módulos. BL-MVP-014 crea un contexto propietario por cada uno de los nueve esquemas.

Los ocho contextos de negocio viven dentro de su módulo. `OpsDbContext` vive en
BuildingBlocks Infrastructure porque `ops` es infraestructura operativa compartida por
contratos, no un módulo funcional.

## Fuente del modelo

No se vuelven a escribir a mano 109 tablas.

El script de scaffolding reverse-engineers una PostgreSQL 18 creada por
`202608080001_InitialPhysicalSchema` usando las versiones de EF Core/Npgsql fijadas por el
repositorio. Por eso nombres, columnas, nullability, PK, índices y FK internas provienen
directamente de la base aprobada.

## Fronteras

Las FK dentro del mismo esquema son relaciones EF normales.

Las FK que cruzan esquemas no generan navegación ni entidad mutable compartida. Se registran
en el manifiesto físico `cross-schema-foreign-keys.json` y se adjuntan como anotación del
modelo propietario. `DatabaseModelVerifier` reconcilia esas relaciones con `pg_catalog`.

## Concurrencia

Todas las columnas físicas `version` se marcan como token de concurrencia y valor generado
al agregar/actualizar, complementando el trigger `bump_version()` de PostgreSQL.

## Migraciones

BL-MVP-014 no llama `dotnet ef migrations add`.

Además verifica los tres SHA-256 autoritativos de BL-MVP-011 y que solo exista la migración:

`202608080001_InitialPhysicalSchema`

Así el modelo se añade sin convertir la base existente en una segunda migración de creación.

## Evidencia

Local:

- `scripts/database/verify-ef-model.ps1`
- `DatabaseModelVerifier`
- `artifacts/postgres/ef-model-summary.txt`

CI:

- compara los nueve modelos con una PostgreSQL 18 migrada desde cero;
- conserva las regresiones de BL-MVP-011, BL-MVP-012 y BL-MVP-013;
- publica el resumen dentro del artifact de evidencia.
