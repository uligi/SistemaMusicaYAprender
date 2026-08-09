# Migración física inicial embebida — BL-MVP-011

BL-MVP-011 convierte la línea base física autoritativa en una migración EF Core ejecutable sin resolver archivos SQL mediante rutas del servidor.

## Fuente autoritativa

`database/postgresql/master/MVP_PostgreSQL_18_Master.sql` es copia exacta del archivo maestro entregado al proyecto.

- Maestro SHA-256: `da46cc9637c5b564f600f05b1c3dc4f16b6fc9ce161bf1f2943c2f9eb4929efa`
- Esquema SHA-256: `bbd1e1500bdae63fee91028b37f9d23a2880cde1325d346e8f7a390d3c8f4ab8`
- Semillas SHA-256: `d031be0126447ac52474e5f86694c4c21e909514f981f679fa44d13fbcc59193`

`verify-master-source.ps1` y CI validan estos hashes.

## Ejecución sin rutas SQL externas

`InitialPhysicalSchema.cs` obtiene `01_initial_schema.sql` y `02_seed_mvp.sql` con `Assembly.GetManifestResourceStream`.

Los archivos SQL se compilan como `EmbeddedResource`. El ejecutable de migración únicamente recibe la ruta del secreto PostgreSQL; nunca una ruta al DDL.

## Conteos de salida

- 9 esquemas.
- 109 tablas.
- 167 FK.
- 70 UNIQUE.
- 455 CHECK.
- 8 EXCLUDE.
- 53 triggers.
- 99 políticas RLS.

## Separación operacional

La API y el worker no llaman `Database.Migrate()`. La migración se ejecuta mediante `tools/DatabaseMigrator` como operación explícita de despliegue.

BL-MVP-012 separará la identidad LOGIN de migración de las identidades ordinarias de aplicación.
