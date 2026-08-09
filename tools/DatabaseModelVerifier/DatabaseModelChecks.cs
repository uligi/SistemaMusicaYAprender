using System.Globalization;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using MusicaAprender.BuildingBlocks.Infrastructure.Database.Modeling;
using MusicaAprender.BuildingBlocks.Infrastructure.Database.Ops;
using MusicaAprender.Modules.Catalog.Infrastructure.Persistence;
using MusicaAprender.Modules.Configuration.Infrastructure.Persistence;
using MusicaAprender.Modules.Content.Infrastructure.Persistence;
using MusicaAprender.Modules.Editorial.Infrastructure.Persistence;
using MusicaAprender.Modules.Identity.Infrastructure.Persistence;
using MusicaAprender.Modules.Learning.Infrastructure.Persistence;
using MusicaAprender.Modules.Progress.Infrastructure.Persistence;
using MusicaAprender.Modules.Security.Infrastructure.Persistence;
using Npgsql;

namespace MusicaAprender.DatabaseModelVerifier;

internal sealed class DatabaseModelChecks
{
    private const string MasterSha256 =
        "da46cc9637c5b564f600f05b1c3dc4f16b6fc9ce161bf1f2943c2f9eb4929efa";

    private const string InitialSchemaSha256 =
        "bbd1e1500bdae63fee91028b37f9d23a2880cde1325d346e8f7a390d3c8f4ab8";

    private const string SeedSha256 =
        "d031be0126447ac52474e5f86694c4c21e909514f981f679fa44d13fbcc59193";


    private readonly ModelVerificationOptions _options;
    private readonly string _connectionString;

    internal DatabaseModelChecks(ModelVerificationOptions options)
    {
        _options = options;

        var password = ReadSecret(
            options.SecretDirectory,
            "postgres_migrator_password");

        _connectionString = new NpgsqlConnectionStringBuilder
        {
            Host = options.Host,
            Port = options.Port,
            Database = options.Database,
            Username = "jp_login_migrator",
            Password = password,
            IncludeErrorDetail = false,
            Pooling = false,
            Timeout = 15,
            ApplicationName = "bl-mvp-014-model-verifier"
        }.ConnectionString;
    }

    internal async Task RunAsync()
    {
        VerifyAuthoritativeHashes();
        VerifyMigrationHistorySource();

        var physical = await ReadPhysicalModelAsync();
        var ef = ReadEfModel();

        CompareTablesAndViews(physical, ef);
        CompareColumns(physical, ef);
        ComparePrimaryKeys(physical, ef);
        CompareForeignKeys(physical, ef);
        CompareConcurrency(physical, ef);

        if (physical.Tables.Count != 109
            || physical.Views.Count != 2
            || physical.Columns.Count != 752
            || physical.PrimaryKeys.Count != 109
            || physical.ForeignKeys.Count != 167)
        {
            throw new InvalidOperationException(
                "La base fisica no conserva los conteos vinculantes de BL-MVP-011.");
        }

        if (ef.ContextSchemas.Count != 9)
        {
            throw new InvalidOperationException(
                $"Se esperaban 9 contextos propietarios y se obtuvieron {ef.ContextSchemas.Count}.");
        }

        await WriteSummaryAsync(physical, ef);

        Console.WriteLine(
            $"OK: {ef.ContextSchemas.Count} contextos, " +
            $"{ef.Tables.Count} tablas, {ef.Views.Count} vistas, " +
            $"{ef.Columns.Count} columnas, {ef.PrimaryKeys.Count} PK y " +
            $"{physical.ForeignKeys.Count} FK reconciliadas.");
    }

    private EfModelSnapshot ReadEfModel()
    {
        var contexts = new ContextDescriptor[]
        {
            CreateDescriptor<IdentityDbContext>("identity", options => new IdentityDbContext(options)),
            CreateDescriptor<SecurityDbContext>("security", options => new SecurityDbContext(options)),
            CreateDescriptor<CatalogDbContext>("catalog", options => new CatalogDbContext(options)),
            CreateDescriptor<ContentDbContext>("content", options => new ContentDbContext(options)),
            CreateDescriptor<LearningDbContext>("learning", options => new LearningDbContext(options)),
            CreateDescriptor<ProgressDbContext>("progress", options => new ProgressDbContext(options)),
            CreateDescriptor<EditorialDbContext>("editorial", options => new EditorialDbContext(options)),
            CreateDescriptor<ConfigurationDbContext>(
                "configuration",
                options => new ConfigurationDbContext(options)),
            CreateDescriptor<OpsDbContext>("ops", options => new OpsDbContext(options))
        };

        var tables = new HashSet<string>(StringComparer.Ordinal);
        var views = new HashSet<string>(StringComparer.Ordinal);
        var columns = new Dictionary<string, bool>(StringComparer.Ordinal);
        var primaryKeys = new HashSet<string>(StringComparer.Ordinal);
        var sameSchemaForeignKeys = new HashSet<string>(StringComparer.Ordinal);
        var crossSchemaForeignKeys = new HashSet<string>(StringComparer.Ordinal);
        var concurrencyColumns = new HashSet<string>(StringComparer.Ordinal);
        var contextSchemas = new HashSet<string>(StringComparer.Ordinal);

        foreach (var descriptor in contexts)
        {
            using var context = descriptor.Create(_connectionString);
            var model = context.Model;

            if (!contextSchemas.Add(descriptor.Schema))
            {
                throw new InvalidOperationException(
                    $"El esquema '{descriptor.Schema}' tiene mas de un contexto propietario.");
            }

            foreach (var entityType in model.GetEntityTypes())
            {
                var viewName = entityType.GetViewName();

                if (viewName is not null)
                {
                    var viewSchema =
                        entityType.GetViewSchema()
                        ?? descriptor.Schema;

                    if (!string.Equals(
                            viewSchema,
                            descriptor.Schema,
                            StringComparison.Ordinal))
                    {
                        throw new InvalidOperationException(
                            $"El contexto '{descriptor.Schema}' contiene la vista " +
                            $"'{viewSchema}.{viewName}'.");
                    }

                    views.Add(ObjectId(viewSchema, viewName));
                    continue;
                }

                var tableName = entityType.GetTableName();

                if (tableName is not null)
                {
                    var schema = entityType.GetSchema();

                    if (!string.Equals(
                            schema,
                            descriptor.Schema,
                            StringComparison.Ordinal))
                    {
                        throw new InvalidOperationException(
                            $"{descriptor.Schema}DbContext mapea indebidamente " +
                            $"{schema ?? "<default>"}.{tableName}.");
                    }

                    var tableId = ObjectId(schema!, tableName);

                    if (!tables.Add(tableId))
                    {
                        throw new InvalidOperationException(
                            $"La tabla '{tableId}' aparece en mas de un contexto.");
                    }

                    var storeObject = StoreObjectIdentifier.Table(
                        tableName,
                        schema);

                    foreach (var property in entityType.GetProperties())
                    {
                        var columnName = property.GetColumnName(storeObject);

                        if (columnName is null)
                        {
                            continue;
                        }

                        var columnId = ColumnId(
                            schema!,
                            tableName,
                            columnName);

                        if (!columns.TryAdd(columnId, property.IsNullable))
                        {
                            throw new InvalidOperationException(
                                $"La columna '{columnId}' esta duplicada en el modelo EF.");
                        }

                        if (property.IsConcurrencyToken)
                        {
                            concurrencyColumns.Add(columnId);
                        }
                    }

                    var primaryKey = entityType.FindPrimaryKey();

                    if (primaryKey is not null)
                    {
                        var keyColumns = primaryKey.Properties
                            .Select(property =>
                                property.GetColumnName(storeObject)
                                ?? throw new InvalidOperationException(
                                    $"PK sin columna fisica en '{tableId}'."))
                            .ToArray();

                        primaryKeys.Add(
                            KeyId(
                                schema!,
                                tableName,
                                keyColumns));
                    }

                    foreach (var foreignKey in entityType.GetForeignKeys())
                    {
                        var principalTable =
                            foreignKey.PrincipalEntityType.GetTableName();

                        if (principalTable is null)
                        {
                            continue;
                        }

                        var principalSchema =
                            foreignKey.PrincipalEntityType.GetSchema();

                        if (!string.Equals(
                                principalSchema,
                                descriptor.Schema,
                                StringComparison.Ordinal))
                        {
                            throw new InvalidOperationException(
                                $"El contexto '{descriptor.Schema}' contiene una navegacion FK " +
                                $"hacia '{principalSchema}.{principalTable}'. Las FK transversales " +
                                "deben permanecer como metadato, no como entidad mutable compartida.");
                        }

                        var principalStoreObject =
                            StoreObjectIdentifier.Table(
                                principalTable,
                                principalSchema);

                        var dependentColumns = foreignKey.Properties
                            .Select(property =>
                                property.GetColumnName(storeObject)
                                ?? throw new InvalidOperationException(
                                    $"FK sin columna dependiente en '{tableId}'."))
                            .ToArray();

                        var principalColumns =
                            foreignKey.PrincipalKey.Properties
                                .Select(property =>
                                    property.GetColumnName(principalStoreObject)
                                    ?? throw new InvalidOperationException(
                                        $"FK sin columna principal en " +
                                        $"'{principalSchema}.{principalTable}'."))
                                .ToArray();

                        sameSchemaForeignKeys.Add(
                            ForeignKeyId(
                                descriptor.Schema,
                                tableName,
                                dependentColumns,
                                descriptor.Schema,
                                principalTable,
                                principalColumns));
                    }
                }

            }

            foreach (var relationship in
                     PhysicalModelConventions.GetCrossSchemaForeignKeys(model))
            {
                if (!string.Equals(
                        relationship.DependentSchema,
                        descriptor.Schema,
                        StringComparison.Ordinal)
                    || string.Equals(
                        relationship.PrincipalSchema,
                        descriptor.Schema,
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        $"Anotacion FK transversal invalida en '{descriptor.Schema}'.");
                }

                crossSchemaForeignKeys.Add(
                    ForeignKeyId(
                        relationship.DependentSchema,
                        relationship.DependentTable,
                        relationship.DependentColumns,
                        relationship.PrincipalSchema,
                        relationship.PrincipalTable,
                        relationship.PrincipalColumns));
            }
        }

        foreach (var relationship in crossSchemaForeignKeys)
        {
            var arrow = relationship.IndexOf("->", StringComparison.Ordinal);
            var dependent = relationship[..arrow];
            var principal = relationship[(arrow + 2)..];

            var dependentObject = dependent[..dependent.IndexOf('(')];
            var principalObject = principal[..principal.IndexOf('(')];

            if (!tables.Contains(dependentObject)
                || !tables.Contains(principalObject))
            {
                throw new InvalidOperationException(
                    $"La FK transversal '{relationship}' referencia una tabla ausente.");
            }
        }

        return new EfModelSnapshot(
            tables,
            views,
            columns,
            primaryKeys,
            sameSchemaForeignKeys,
            crossSchemaForeignKeys,
            concurrencyColumns,
            contextSchemas);
    }

    private static ContextDescriptor CreateDescriptor<TContext>(
        string schema,
        Func<DbContextOptions<TContext>, TContext> factory)
        where TContext : DbContext
    {
        return new ContextDescriptor(
            schema,
            connectionString =>
            {
                var options = new DbContextOptionsBuilder<TContext>()
                    .UseNpgsql(connectionString)
                    .Options;

                return factory(options);
            });
    }

    private async Task<PhysicalModelSnapshot> ReadPhysicalModelAsync()
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync();

        var tables = await ReadObjectSetAsync(
            connection,
            "AND object_row.relkind IN ('r', 'p')");

        var views = await ReadObjectSetAsync(
            connection,
            "AND object_row.relkind IN ('v', 'm')");

        var columns = await ReadColumnsAsync(connection);
        var primaryKeys = await ReadPrimaryKeysAsync(connection);
        var foreignKeys = await ReadForeignKeysAsync(connection);

        var concurrencyColumns = columns.Keys
            .Where(static column =>
                column.EndsWith(".version", StringComparison.Ordinal))
            .ToHashSet(StringComparer.Ordinal);

        return new PhysicalModelSnapshot(
            tables,
            views,
            columns,
            primaryKeys,
            foreignKeys,
            concurrencyColumns);
    }

    private static async Task<HashSet<string>> ReadObjectSetAsync(
        NpgsqlConnection connection,
        string relkindPredicate)
    {
        var sql =
            $"""
            SELECT
                namespace_row.nspname,
                object_row.relname
            FROM pg_catalog.pg_class AS object_row
            JOIN pg_catalog.pg_namespace AS namespace_row
              ON namespace_row.oid = object_row.relnamespace
            WHERE namespace_row.nspname IN (
                'identity',
                'security',
                'catalog',
                'content',
                'learning',
                'progress',
                'editorial',
                'configuration',
                'ops'
            )
            {relkindPredicate}
            ORDER BY
                namespace_row.nspname,
                object_row.relname;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync();

        var result = new HashSet<string>(StringComparer.Ordinal);

        while (await reader.ReadAsync())
        {
            result.Add(
                ObjectId(
                    reader.GetString(0),
                    reader.GetString(1)));
        }

        return result;
    }

    private static async Task<Dictionary<string, bool>> ReadColumnsAsync(
        NpgsqlConnection connection)
    {
        const string sql =
            """
            SELECT
                namespace_row.nspname,
                table_row.relname,
                attribute_row.attname,
                NOT attribute_row.attnotnull AS is_nullable
            FROM pg_catalog.pg_attribute AS attribute_row
            JOIN pg_catalog.pg_class AS table_row
              ON table_row.oid = attribute_row.attrelid
            JOIN pg_catalog.pg_namespace AS namespace_row
              ON namespace_row.oid = table_row.relnamespace
            WHERE namespace_row.nspname IN (
                'identity',
                'security',
                'catalog',
                'content',
                'learning',
                'progress',
                'editorial',
                'configuration',
                'ops'
            )
              AND table_row.relkind IN ('r', 'p')
              AND attribute_row.attnum > 0
              AND NOT attribute_row.attisdropped
            ORDER BY
                namespace_row.nspname,
                table_row.relname,
                attribute_row.attnum;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync();

        var result = new Dictionary<string, bool>(StringComparer.Ordinal);

        while (await reader.ReadAsync())
        {
            result.Add(
                ColumnId(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.GetString(2)),
                reader.GetBoolean(3));
        }

        return result;
    }

    private static async Task<HashSet<string>> ReadPrimaryKeysAsync(
        NpgsqlConnection connection)
    {
        const string sql =
            """
            SELECT
                namespace_row.nspname,
                table_row.relname,
                attribute_row.attname,
                key_column.ordinality
            FROM pg_catalog.pg_constraint AS constraint_row
            JOIN pg_catalog.pg_class AS table_row
              ON table_row.oid = constraint_row.conrelid
            JOIN pg_catalog.pg_namespace AS namespace_row
              ON namespace_row.oid = table_row.relnamespace
            CROSS JOIN LATERAL unnest(constraint_row.conkey)
                WITH ORDINALITY AS key_column(attnum, ordinality)
            JOIN pg_catalog.pg_attribute AS attribute_row
              ON attribute_row.attrelid = table_row.oid
             AND attribute_row.attnum = key_column.attnum
            WHERE constraint_row.contype = 'p'
              AND namespace_row.nspname IN (
                  'identity',
                  'security',
                  'catalog',
                  'content',
                  'learning',
                  'progress',
                  'editorial',
                  'configuration',
                  'ops'
              )
            ORDER BY
                namespace_row.nspname,
                table_row.relname,
                key_column.ordinality;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync();

        var groups =
            new Dictionary<string, List<(long Ordinal, string Column)>>(
                StringComparer.Ordinal);

        while (await reader.ReadAsync())
        {
            var schema = reader.GetString(0);
            var table = reader.GetString(1);
            var groupId = ObjectId(schema, table);

            if (!groups.TryGetValue(groupId, out var columns))
            {
                columns = [];
                groups.Add(groupId, columns);
            }

            columns.Add(
                (reader.GetInt64(3), reader.GetString(2)));
        }

        return groups
            .Select(group =>
            {
                var separator =
                    group.Key.IndexOf('.');

                var schema = group.Key[..separator];
                var table = group.Key[(separator + 1)..];

                return KeyId(
                    schema,
                    table,
                    group.Value
                        .OrderBy(static item => item.Ordinal)
                        .Select(static item => item.Column));
            })
            .ToHashSet(StringComparer.Ordinal);
    }

    private static async Task<HashSet<string>> ReadForeignKeysAsync(
        NpgsqlConnection connection)
    {
        const string sql =
            """
            SELECT
                constraint_row.oid,
                dependent_namespace.nspname,
                dependent_table.relname,
                dependent_attribute.attname,
                principal_namespace.nspname,
                principal_table.relname,
                principal_attribute.attname,
                dependent_key.ordinality
            FROM pg_catalog.pg_constraint AS constraint_row
            JOIN pg_catalog.pg_class AS dependent_table
              ON dependent_table.oid = constraint_row.conrelid
            JOIN pg_catalog.pg_namespace AS dependent_namespace
              ON dependent_namespace.oid = dependent_table.relnamespace
            JOIN pg_catalog.pg_class AS principal_table
              ON principal_table.oid = constraint_row.confrelid
            JOIN pg_catalog.pg_namespace AS principal_namespace
              ON principal_namespace.oid = principal_table.relnamespace
            CROSS JOIN LATERAL unnest(constraint_row.conkey)
                WITH ORDINALITY AS dependent_key(attnum, ordinality)
            JOIN LATERAL unnest(constraint_row.confkey)
                WITH ORDINALITY AS principal_key(attnum, ordinality)
              ON principal_key.ordinality = dependent_key.ordinality
            JOIN pg_catalog.pg_attribute AS dependent_attribute
              ON dependent_attribute.attrelid = dependent_table.oid
             AND dependent_attribute.attnum = dependent_key.attnum
            JOIN pg_catalog.pg_attribute AS principal_attribute
              ON principal_attribute.attrelid = principal_table.oid
             AND principal_attribute.attnum = principal_key.attnum
            WHERE constraint_row.contype = 'f'
              AND dependent_namespace.nspname IN (
                  'identity',
                  'security',
                  'catalog',
                  'content',
                  'learning',
                  'progress',
                  'editorial',
                  'configuration',
                  'ops'
              )
              AND principal_namespace.nspname IN (
                  'identity',
                  'security',
                  'catalog',
                  'content',
                  'learning',
                  'progress',
                  'editorial',
                  'configuration',
                  'ops'
              )
            ORDER BY
                constraint_row.oid,
                dependent_key.ordinality;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync();

        var groups =
            new Dictionary<uint, PhysicalForeignKeyBuilder>();

        while (await reader.ReadAsync())
        {
            var oid = reader.GetFieldValue<uint>(0);

            if (!groups.TryGetValue(oid, out var group))
            {
                group = new PhysicalForeignKeyBuilder(
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(4),
                    reader.GetString(5));

                groups.Add(oid, group);
            }

            group.Columns.Add(
                new ForeignKeyColumn(
                    reader.GetInt64(7),
                    reader.GetString(3),
                    reader.GetString(6)));
        }

        return groups.Values
            .Select(group =>
                ForeignKeyId(
                    group.DependentSchema,
                    group.DependentTable,
                    group.Columns
                        .OrderBy(static item => item.Ordinal)
                        .Select(static item => item.DependentColumn),
                    group.PrincipalSchema,
                    group.PrincipalTable,
                    group.Columns
                        .OrderBy(static item => item.Ordinal)
                        .Select(static item => item.PrincipalColumn)))
            .ToHashSet(StringComparer.Ordinal);
    }

    private static void CompareTablesAndViews(
        PhysicalModelSnapshot physical,
        EfModelSnapshot ef)
    {
        AssertSetEqual("tablas", physical.Tables, ef.Tables);
        AssertSetEqual("vistas", physical.Views, ef.Views);
    }

    private static void CompareColumns(
        PhysicalModelSnapshot physical,
        EfModelSnapshot ef)
    {
        AssertSetEqual(
            "columnas",
            physical.Columns.Keys,
            ef.Columns.Keys);

        foreach (var column in physical.Columns)
        {
            if (!ef.Columns.TryGetValue(
                    column.Key,
                    out var efNullable)
                || efNullable != column.Value)
            {
                throw new InvalidOperationException(
                    $"Nullability EF no coincide para '{column.Key}'.");
            }
        }
    }

    private static void ComparePrimaryKeys(
        PhysicalModelSnapshot physical,
        EfModelSnapshot ef)
    {
        AssertSetEqual(
            "claves primarias",
            physical.PrimaryKeys,
            ef.PrimaryKeys);
    }

    private static void CompareForeignKeys(
        PhysicalModelSnapshot physical,
        EfModelSnapshot ef)
    {
        var modelForeignKeys = ef.SameSchemaForeignKeys
            .Concat(ef.CrossSchemaForeignKeys)
            .ToHashSet(StringComparer.Ordinal);

        AssertSetEqual(
            "claves foraneas",
            physical.ForeignKeys,
            modelForeignKeys);
    }

    private static void CompareConcurrency(
        PhysicalModelSnapshot physical,
        EfModelSnapshot ef)
    {
        AssertSetEqual(
            "tokens version de concurrencia",
            physical.ConcurrencyColumns,
            ef.ConcurrencyColumns);
    }

    private static void AssertSetEqual(
        string label,
        IEnumerable<string> expected,
        IEnumerable<string> actual)
    {
        var expectedSet =
            expected.ToHashSet(StringComparer.Ordinal);

        var actualSet =
            actual.ToHashSet(StringComparer.Ordinal);

        var missing = expectedSet
            .Except(actualSet, StringComparer.Ordinal)
            .OrderBy(static value => value, StringComparer.Ordinal)
            .Take(10)
            .ToArray();

        var extra = actualSet
            .Except(expectedSet, StringComparer.Ordinal)
            .OrderBy(static value => value, StringComparer.Ordinal)
            .Take(10)
            .ToArray();

        if (missing.Length == 0 && extra.Length == 0)
        {
            return;
        }

        throw new InvalidOperationException(
            $"Diferencia en {label}. " +
            $"Faltan=[{string.Join(", ", missing)}] " +
            $"Sobran=[{string.Join(", ", extra)}].");
    }

    private void VerifyAuthoritativeHashes()
    {
        AssertSha256(
            Path.Combine(
                _options.RepositoryRoot,
                "database",
                "postgresql",
                "master",
                "MVP_PostgreSQL_18_Master.sql"),
            MasterSha256);

        AssertSha256(
            Path.Combine(
                _options.RepositoryRoot,
                "database",
                "postgresql",
                "migrations",
                "sql",
                "01_initial_schema.sql"),
            InitialSchemaSha256);

        AssertSha256(
            Path.Combine(
                _options.RepositoryRoot,
                "database",
                "postgresql",
                "migrations",
                "sql",
                "02_seed_mvp.sql"),
            SeedSha256);
    }

    private void VerifyMigrationHistorySource()
    {
        var migrationsDirectory = Path.Combine(
            _options.RepositoryRoot,
            "tools",
            "DatabaseMigrator",
            "Migrations");

        var migrationFiles = Directory
            .EnumerateFiles(
                migrationsDirectory,
                "*.cs",
                SearchOption.TopDirectoryOnly)
            .Where(path =>
                File.ReadAllText(path)
                    .Contains("[Migration(", StringComparison.Ordinal))
            .ToArray();

        if (migrationFiles.Length != 1)
        {
            throw new InvalidOperationException(
                $"BL-MVP-014 esperaba una sola migracion fisica y encontro {migrationFiles.Length}.");
        }

        var initialMigration = File.ReadAllText(migrationFiles[0]);

        if (!initialMigration.Contains(
                "202608080001_InitialPhysicalSchema",
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "La unica migracion fisica ya no es InitialPhysicalSchema.");
        }

        var unexpectedModuleMigrations = Directory
            .EnumerateFiles(
                Path.Combine(
                    _options.RepositoryRoot,
                    "src",
                    "Modules"),
                "*.cs",
                SearchOption.AllDirectories)
            .Where(path =>
                path.Split(
                        Path.DirectorySeparatorChar,
                        Path.AltDirectorySeparatorChar)
                    .Contains(
                        "Migrations",
                        StringComparer.OrdinalIgnoreCase))
            .Take(10)
            .ToArray();

        if (unexpectedModuleMigrations.Length > 0)
        {
            throw new InvalidOperationException(
                "BL-MVP-014 no debe generar migraciones por modulo. " +
                $"Ejemplos: {string.Join(", ", unexpectedModuleMigrations)}");
        }
    }

    private async Task WriteSummaryAsync(
        PhysicalModelSnapshot physical,
        EfModelSnapshot ef)
    {
        if (string.IsNullOrWhiteSpace(_options.SummaryPath))
        {
            return;
        }

        var summaryPath = _options.SummaryPath;
        var directory = Path.GetDirectoryName(summaryPath);

        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var physicalCrossSchema = physical.ForeignKeys.Count(
            foreignKey =>
            {
                var arrow =
                    foreignKey.IndexOf("->", StringComparison.Ordinal);

                var dependent =
                    foreignKey[..foreignKey.IndexOf('.')];

                var principalPart = foreignKey[(arrow + 2)..];
                var principal =
                    principalPart[..principalPart.IndexOf('.')];

                return !string.Equals(
                    dependent,
                    principal,
                    StringComparison.Ordinal);
            });

        var lines = new[]
        {
            "bl_mvp=014",
            $"schemas={ef.ContextSchemas.Count.ToString(CultureInfo.InvariantCulture)}",
            $"tables={ef.Tables.Count.ToString(CultureInfo.InvariantCulture)}",
            $"views={ef.Views.Count.ToString(CultureInfo.InvariantCulture)}",
            $"columns={ef.Columns.Count.ToString(CultureInfo.InvariantCulture)}",
            $"primary_keys={ef.PrimaryKeys.Count.ToString(CultureInfo.InvariantCulture)}",
            $"foreign_keys={physical.ForeignKeys.Count.ToString(CultureInfo.InvariantCulture)}",
            $"same_schema_foreign_keys={ef.SameSchemaForeignKeys.Count.ToString(CultureInfo.InvariantCulture)}",
            $"cross_schema_foreign_keys={physicalCrossSchema.ToString(CultureInfo.InvariantCulture)}",
            $"concurrency_tokens={ef.ConcurrencyColumns.Count.ToString(CultureInfo.InvariantCulture)}",
            "migration_count=1",
            $"master_sha256={MasterSha256}",
            $"initial_schema_sha256={InitialSchemaSha256}",
            $"seed_sha256={SeedSha256}"
        };

        await File.WriteAllLinesAsync(summaryPath, lines);
    }

    private static void AssertSha256(
        string path,
        string expected)
    {
        if (!File.Exists(path))
        {
            throw new InvalidOperationException(
                $"No existe la fuente autoritativa '{path}'.");
        }

        using var stream = File.OpenRead(path);
        var actual = Convert.ToHexString(
                SHA256.HashData(stream))
            .ToLowerInvariant();

        if (!string.Equals(
                actual,
                expected,
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"SHA-256 inesperado para '{path}'. " +
                $"Esperado={expected}; Actual={actual}.");
        }
    }

    private static string ReadSecret(
        string secretDirectory,
        string secretName)
    {
        var path = Path.Combine(
            secretDirectory,
            secretName);

        if (!File.Exists(path))
        {
            throw new InvalidOperationException(
                $"Falta el secreto requerido '{secretName}'.");
        }

        var value = File.ReadAllText(path).Trim();

        if (value.Length < 24)
        {
            throw new InvalidOperationException(
                $"El secreto '{secretName}' es demasiado corto.");
        }

        return value;
    }

    private static string ObjectId(
        string schema,
        string objectName)
    {
        return $"{schema}.{objectName}";
    }

    private static string ColumnId(
        string schema,
        string table,
        string column)
    {
        return $"{schema}.{table}.{column}";
    }

    private static string KeyId(
        string schema,
        string table,
        IEnumerable<string> columns)
    {
        return $"{schema}.{table}({string.Join(",", columns)})";
    }

    private static string ForeignKeyId(
        string dependentSchema,
        string dependentTable,
        IEnumerable<string> dependentColumns,
        string principalSchema,
        string principalTable,
        IEnumerable<string> principalColumns)
    {
        return
            $"{dependentSchema}.{dependentTable}({string.Join(",", dependentColumns)})" +
            $"->{principalSchema}.{principalTable}({string.Join(",", principalColumns)})";
    }

    private sealed record ContextDescriptor(
        string Schema,
        Func<string, DbContext> Create);

    private sealed record PhysicalModelSnapshot(
        HashSet<string> Tables,
        HashSet<string> Views,
        Dictionary<string, bool> Columns,
        HashSet<string> PrimaryKeys,
        HashSet<string> ForeignKeys,
        HashSet<string> ConcurrencyColumns);

    private sealed record EfModelSnapshot(
        HashSet<string> Tables,
        HashSet<string> Views,
        Dictionary<string, bool> Columns,
        HashSet<string> PrimaryKeys,
        HashSet<string> SameSchemaForeignKeys,
        HashSet<string> CrossSchemaForeignKeys,
        HashSet<string> ConcurrencyColumns,
        HashSet<string> ContextSchemas);

    private sealed class PhysicalForeignKeyBuilder(
        string dependentSchema,
        string dependentTable,
        string principalSchema,
        string principalTable)
    {
        internal string DependentSchema { get; } = dependentSchema;

        internal string DependentTable { get; } = dependentTable;

        internal string PrincipalSchema { get; } = principalSchema;

        internal string PrincipalTable { get; } = principalTable;

        internal List<ForeignKeyColumn> Columns { get; } = [];
    }

    private sealed record ForeignKeyColumn(
        long Ordinal,
        string DependentColumn,
        string PrincipalColumn);
}
