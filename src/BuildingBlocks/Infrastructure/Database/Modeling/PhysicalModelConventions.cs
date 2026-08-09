using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Database.Modeling;

public static class PhysicalModelConventions
{
    public const string CrossSchemaForeignKeysAnnotationName =
        "MusicaAprender:CrossSchemaForeignKeys";

    private const string CrossSchemaForeignKeysResourceName =
        "MusicaAprender.BuildingBlocks.Infrastructure.Database.Modeling.CrossSchemaForeignKeys.json";

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static readonly Lazy<CrossSchemaForeignKeyManifest> Manifest =
        new(
            LoadManifest,
            LazyThreadSafetyMode.ExecutionAndPublication);

    public static void ApplyPhysicalSchemaConventions(
        this ModelBuilder modelBuilder,
        string ownedSchema)
    {
        ArgumentNullException.ThrowIfNull(modelBuilder);
        ArgumentException.ThrowIfNullOrWhiteSpace(ownedSchema);

        var schema = ownedSchema.Trim();

        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            var viewName = entityType.GetViewName();

            if (viewName is not null)
            {
                var viewSchema = entityType.GetViewSchema() ?? schema;

                if (!string.Equals(
                        viewSchema,
                        schema,
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        $"El contexto propietario de '{schema}' intento mapear " +
                        $"la vista '{viewSchema}.{viewName}'.");
                }

                continue;
            }

            var tableName = entityType.GetTableName();

            if (tableName is null)
            {
                continue;
            }

            var tableSchema = entityType.GetSchema();

            if (!string.Equals(tableSchema, schema, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"El contexto propietario de '{schema}' intento mapear " +
                    $"'{tableSchema ?? "<default>"}.{tableName}'.");
            }

            var storeObject = StoreObjectIdentifier.Table(
                tableName,
                tableSchema);

            foreach (var property in entityType.GetProperties())
            {
                var columnName = property.GetColumnName(storeObject);

                if (!string.Equals(
                        columnName,
                        "version",
                        StringComparison.Ordinal))
                {
                    continue;
                }

                property.IsConcurrencyToken = true;
                property.ValueGenerated = ValueGenerated.OnAddOrUpdate;
            }
        }

        var externalRelationships = Manifest.Value.Relationships
            .Where(relationship =>
                string.Equals(
                    relationship.DependentSchema,
                    schema,
                    StringComparison.Ordinal))
            .OrderBy(static relationship => relationship.Constraint, StringComparer.Ordinal)
            .ToArray();

        modelBuilder.Model.SetAnnotation(
            CrossSchemaForeignKeysAnnotationName,
            JsonSerializer.Serialize(
                externalRelationships,
                SerializerOptions));
    }

    public static IReadOnlyList<CrossSchemaForeignKeyDefinition>
        GetCrossSchemaForeignKeys(IReadOnlyModel model)
    {
        ArgumentNullException.ThrowIfNull(model);

        var value = model
            .FindAnnotation(CrossSchemaForeignKeysAnnotationName)
            ?.Value as string;

        if (string.IsNullOrWhiteSpace(value))
        {
            return Array.Empty<CrossSchemaForeignKeyDefinition>();
        }

        return JsonSerializer.Deserialize<CrossSchemaForeignKeyDefinition[]>(
                   value,
                   SerializerOptions)
               ?? Array.Empty<CrossSchemaForeignKeyDefinition>();
    }

    private static CrossSchemaForeignKeyManifest LoadManifest()
    {
        var assembly = typeof(PhysicalModelConventions).Assembly;

        using var stream = assembly.GetManifestResourceStream(
            CrossSchemaForeignKeysResourceName)
            ?? throw new InvalidOperationException(
                "No se encontro el manifiesto embebido de relaciones FK entre esquemas.");

        var manifest =
            JsonSerializer.Deserialize<CrossSchemaForeignKeyManifest>(
                stream,
                SerializerOptions)
            ?? throw new InvalidOperationException(
                "El manifiesto de relaciones FK entre esquemas esta vacio.");

        if (!string.Equals(
                manifest.BacklogItem,
                "BL-MVP-014",
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "El manifiesto de relaciones FK entre esquemas no pertenece a BL-MVP-014.");
        }

        return manifest;
    }

    private sealed record CrossSchemaForeignKeyManifest(
        string BacklogItem,
        CrossSchemaForeignKeyDefinition[] Relationships);
}

public sealed record CrossSchemaForeignKeyDefinition(
    string Constraint,
    string DependentSchema,
    string DependentTable,
    string[] DependentColumns,
    string PrincipalSchema,
    string PrincipalTable,
    string[] PrincipalColumns);
