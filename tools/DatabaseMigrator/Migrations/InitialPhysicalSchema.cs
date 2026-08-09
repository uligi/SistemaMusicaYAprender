using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace MusicaAprender.DatabaseMigrator.Migrations;

[DbContext(typeof(PhysicalSchemaDbContext))]
[Migration(MigrationId)]
public sealed class InitialPhysicalSchema : Migration
{
    internal const string MigrationId = "202608080001_InitialPhysicalSchema";

    protected override void Up(MigrationBuilder migrationBuilder)
    {
        ArgumentNullException.ThrowIfNull(migrationBuilder);

        migrationBuilder.Sql(
            EmbeddedMigrationSql.Read(EmbeddedMigrationSql.InitialSchemaResource),
            suppressTransaction: true);

        migrationBuilder.Sql(
            SeedMigrationSql.Prepare(
                EmbeddedMigrationSql.Read(EmbeddedMigrationSql.SeedResource)),
            suppressTransaction: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        ArgumentNullException.ThrowIfNull(migrationBuilder);

        migrationBuilder.Sql(
            """
            DO $rollback$
            BEGIN
                RAISE EXCEPTION
                    'La migracion fisica inicial no admite Down automatico. Use una base desechable o el runbook aprobado.';
            END;
            $rollback$;
            """,
            suppressTransaction: true);
    }
}
