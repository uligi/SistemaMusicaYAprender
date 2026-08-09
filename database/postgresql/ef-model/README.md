# Modelo EF Core por esquema — BL-MVP-014

BL-MVP-014 no cambia la línea base física. La fuente autoritativa sigue siendo la migración
embebida de BL-MVP-011.

La arquitectura prohíbe compartir `DbContext`, repositorios genéricos o entidades mutables
entre módulos. Por eso el modelo de aplicación se divide por propietario físico:

| Contexto                 | Esquema         | Propietario            |
| ------------------------ | --------------- | ---------------------- |
| `IdentityDbContext`      | `identity`      | M01                    |
| `SecurityDbContext`      | `security`      | M18                    |
| `CatalogDbContext`       | `catalog`       | M02                    |
| `ContentDbContext`       | `content`       | M03-M05                |
| `LearningDbContext`      | `learning`      | M06-M08                |
| `ProgressDbContext`      | `progress`      | M09                    |
| `EditorialDbContext`     | `editorial`     | M15                    |
| `ConfigurationDbContext` | `configuration` | M19                    |
| `OpsDbContext`           | `ops`           | infraestructura/worker |

## Generación

`scripts/database/scaffold-ef-model.ps1` reconstruye las entidades y el mapeo Fluent de
cada contexto desde una PostgreSQL 18 creada por la migración inicial aprobada.

El código generado vive bajo `Infrastructure/Persistence/Generated` en cada módulo y bajo
`Database/Ops/Generated` para `ops`. Los archivos `*.Conventions.cs` son manuales y no son
sobrescritos al regenerar.

No se usa `--use-database-names`: los nombres CLR pueden ser idiomáticos, pero `ToTable`,
`HasColumnName`, claves, índices y relaciones conservan el nombre físico real.

## Concurrencia

El reverse engineering no puede inferir que el trigger `bump_version()` convierte
`version bigint` en token de concurrencia. `PhysicalModelConventions` completa esa semántica:

- `version` es `IsConcurrencyToken`;
- `ValueGenerated` es `OnAddOrUpdate`.

## Relaciones entre esquemas

Una relación interna al mismo esquema se modela como FK normal de EF Core.

Una FK transversal no crea navegación hacia una entidad mutable de otro módulo, porque eso
violaría la frontera de propiedad. `cross-schema-foreign-keys.json` registra esas relaciones
físicas como metadato del modelo y el verificador exige que cada columna dependiente y
principal exista en su contexto propietario.

## Migraciones

BL-MVP-014 no ejecuta `migrations add` y no crea migraciones por módulo.

La única migración física sigue siendo:

`202608080001_InitialPhysicalSchema`

Los hashes de maestro/esquema/semillas de BL-MVP-011 se vuelven a comprobar. Cualquier
migración futura deberá partir de estas configuraciones reales y conservar la historia,
nunca recrear las 109 tablas como si fueran nuevas.

## Verificación

`DatabaseModelVerifier` compara los nueve modelos EF Core contra `pg_catalog` y exige:

- 9 esquemas propietarios;
- 109 tablas y 2 vistas;
- 752 columnas físicas;
- 109 PK;
- las 167 FK, incluidas las transversales registradas;
- nullability de columnas;
- `version` como token de concurrencia;
- ningún contexto mapeando tablas de otro esquema;
- hashes BL-MVP-011 intactos;
- una sola migración física inicial.
