using System.Reflection;
using System.Text;

namespace MusicaAprender.DatabaseMigrator.Migrations;

internal static class EmbeddedMigrationSql
{
    internal const string InitialSchemaResource =
        "MusicaAprender.DatabaseMigrator.Migrations.Sql.01_initial_schema.sql";

    internal const string SeedResource =
        "MusicaAprender.DatabaseMigrator.Migrations.Sql.02_seed_mvp.sql";

    internal static string Read(string resourceName)
    {
        var assembly = typeof(EmbeddedMigrationSql).Assembly;

        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException(
                $"No se encontro el recurso SQL embebido '{resourceName}'.");

        using var reader = new StreamReader(
            stream,
            Encoding.UTF8,
            detectEncodingFromByteOrderMarks: true);

        return reader.ReadToEnd();
    }
}
