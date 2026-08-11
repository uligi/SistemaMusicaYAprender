using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Configuration.Infrastructure.Administration;

public sealed record ConfigurationParameterView(
    string ParameterKey,
    string OwnerModule,
    string ValueType,
    string ValidationSchemaJson,
    Guid ParameterVersionId,
    int CurrentVersionNo,
    string ScopeCode,
    string? ScopeValue,
    string CurrentValueJson,
    DateTimeOffset ValidFrom,
    DateTimeOffset? ValidTo,
    long ProjectionVersion);

public sealed record ConfigurationCatalogEntryView(
    Guid CatalogEntryId,
    string EntryCode,
    string LabelsJson,
    string ValueJson,
    DateTimeOffset ValidFrom,
    DateTimeOffset? ValidTo,
    long Version);

public sealed record ConfigurationCatalogView(
    string CatalogCode,
    string OwnerModule,
    string ValueSchemaJson,
    long DefinitionVersion,
    IReadOnlyList<ConfigurationCatalogEntryView> Entries);

public sealed record ConfigurationAdministrationSnapshot(
    IReadOnlyList<ConfigurationParameterView> Parameters,
    IReadOnlyList<ConfigurationCatalogView> Catalogs);

public sealed record ParameterConfigurationChangeCommand(
    string ParameterKey,
    string ScopeCode,
    string? ScopeValue,
    string TypedValueJson,
    DateTimeOffset? ValidUntil,
    string Reason,
    string Impact,
    int ExpectedVersionNo);

public sealed record CatalogConfigurationChangeCommand(
    string CatalogCode,
    string EntryCode,
    string LabelsJson,
    string ValueJson,
    DateTimeOffset? ValidUntil,
    string Reason,
    string Impact,
    Guid ExpectedEntryId,
    long ExpectedVersion);

public sealed record ConfigurationChangeSimulation(
    string ObjectType,
    string ObjectKey,
    string OwnerModule,
    bool CanActivate,
    IReadOnlyList<string> Checks,
    string BeforeJson,
    string AfterJson,
    long ExpectedVersion,
    DateTimeOffset? CurrentValidUntil,
    DateTimeOffset? ProposedValidUntil,
    bool HistoricalValueWillBePreserved);

public sealed record ConfigurationActivationResult(
    string ObjectType,
    string ObjectKey,
    string OwnerModule,
    Guid ActiveObjectId,
    long ActiveVersion,
    DateTimeOffset EffectiveFrom,
    DateTimeOffset? EffectiveUntil,
    Guid PreviousObjectId,
    Guid ChangeSetId,
    Guid ActivationId,
    bool HistoricalValuePreserved,
    bool AlreadyApplied);

public sealed class ConfigurationAdministrationException(
    string code,
    string message) : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed partial class ConfigurationAdministrationService(
    IConfigurationAdministrationTransactionExecutor transactionExecutor)
{
    private const int MaxJsonLength = 8192;
    private const int MaxReasonLength = 160;
    private const int MaxImpactLength = 240;

    [GeneratedRegex("^[A-Z0-9][A-Z0-9._-]{0,63}$", RegexOptions.CultureInvariant)]
    private static partial Regex CodePattern();

    [GeneratedRegex(
        "(^|[._-])(PASSWORD|PASSWD|SECRET|TOKEN|PRIVATE[_-]?KEY|API[_-]?KEY|CREDENTIAL)([._-]|$)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SecretNamePattern();

    public Task<ConfigurationAdministrationSnapshot> ReadSnapshotAsync(
        Guid actorAccountId,
        string correlationId,
        CancellationToken cancellationToken = default) =>
        transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            ReadSnapshotCoreAsync,
            cancellationToken);

    public Task<ConfigurationChangeSimulation> SimulateParameterAsync(
        Guid actorAccountId,
        ParameterConfigurationChangeCommand command,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                SimulateParameterCoreAsync(
                    connection,
                    transaction,
                    command,
                    token),
            cancellationToken);
    }

    public Task<ConfigurationChangeSimulation> SimulateCatalogAsync(
        Guid actorAccountId,
        CatalogConfigurationChangeCommand command,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                SimulateCatalogCoreAsync(
                    connection,
                    transaction,
                    command,
                    token),
            cancellationToken);
    }

    public Task<ConfigurationActivationResult> ActivateParameterAsync(
        Guid actorAccountId,
        ParameterConfigurationChangeCommand command,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        return transactionExecutor.ExecuteAuditedAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ActivateParameterCoreAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    command,
                    correlationId,
                    token),
            cancellationToken);
    }

    public Task<ConfigurationActivationResult> ActivateCatalogAsync(
        Guid actorAccountId,
        CatalogConfigurationChangeCommand command,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        return transactionExecutor.ExecuteAuditedAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ActivateCatalogCoreAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    command,
                    correlationId,
                    token),
            cancellationToken);
    }

    private static async Task<ConfigurationAdministrationSnapshot> ReadSnapshotCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        var parameters = new List<ConfigurationParameterView>();
        const string parameterSql = """
            SELECT
                d.parameter_key,
                d.owner_module,
                d.value_type,
                d.validation_schema::text,
                v.parameter_version_id,
                v.version_no,
                v.scope_code,
                v.scope_value,
                v.typed_value::text,
                v.valid_from,
                v.valid_to,
                e.projection_version
            FROM configuration.parameter_definition d
            JOIN configuration.effective_parameter e
              ON e.parameter_key = d.parameter_key
            JOIN configuration.parameter_version v
              ON v.parameter_version_id = e.parameter_version_id
            WHERE d.status_code = 'ACTIVE'
              AND v.status_code = 'ACTIVE'
              AND v.valid_from <= CURRENT_TIMESTAMP
              AND (v.valid_to IS NULL OR v.valid_to > CURRENT_TIMESTAMP)
            ORDER BY d.parameter_key, v.scope_code, v.scope_value NULLS FIRST;
            """;

        await using (var command =
            new NpgsqlCommand(parameterSql, connection, transaction))
        {
            await using var reader =
                await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                parameters.Add(
                    new ConfigurationParameterView(
                        reader.GetString(0),
                        reader.GetString(1),
                        reader.GetString(2),
                        reader.GetString(3),
                        reader.GetGuid(4),
                        reader.GetInt32(5),
                        reader.GetString(6),
                        reader.IsDBNull(7) ? null : reader.GetString(7),
                        reader.GetString(8),
                        ReadUtc(reader, 9),
                        ReadNullableUtc(reader, 10),
                        reader.GetInt64(11)));
            }
        }

        var catalogMap =
            new Dictionary<string, CatalogAccumulator>(StringComparer.Ordinal);
        const string catalogSql = """
            SELECT
                d.catalog_code,
                d.owner_module,
                d.value_schema::text,
                d.version,
                e.catalog_entry_id,
                e.entry_code,
                e.labels::text,
                e.value::text,
                e.valid_from,
                e.valid_to,
                e.version
            FROM configuration.catalog_definition d
            JOIN configuration.catalog_entry e
              ON e.catalog_definition_id = d.catalog_definition_id
            WHERE d.status_code = 'ACTIVE'
              AND e.status_code = 'ACTIVE'
              AND e.valid_from <= CURRENT_TIMESTAMP
              AND (e.valid_to IS NULL OR e.valid_to > CURRENT_TIMESTAMP)
            ORDER BY d.catalog_code, e.entry_code;
            """;

        await using (var command =
            new NpgsqlCommand(catalogSql, connection, transaction))
        {
            await using var reader =
                await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var catalogCode = reader.GetString(0);
                if (!catalogMap.TryGetValue(catalogCode, out var accumulator))
                {
                    accumulator = new CatalogAccumulator(
                        catalogCode,
                        reader.GetString(1),
                        reader.GetString(2),
                        reader.GetInt64(3));
                    catalogMap[catalogCode] = accumulator;
                }

                accumulator.Entries.Add(
                    new ConfigurationCatalogEntryView(
                        reader.GetGuid(4),
                        reader.GetString(5),
                        reader.GetString(6),
                        reader.GetString(7),
                        ReadUtc(reader, 8),
                        ReadNullableUtc(reader, 9),
                        reader.GetInt64(10)));
            }
        }

        return new ConfigurationAdministrationSnapshot(
            parameters,
            catalogMap.Values
                .Select(static item =>
                    new ConfigurationCatalogView(
                        item.CatalogCode,
                        item.OwnerModule,
                        item.ValueSchemaJson,
                        item.DefinitionVersion,
                        item.Entries))
                .ToArray());
    }

    private static async Task<ConfigurationChangeSimulation> SimulateParameterCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ParameterConfigurationChangeCommand command,
        CancellationToken cancellationToken)
    {
        var checks = ValidateCommon(
            command.ParameterKey,
            command.ScopeCode,
            command.ScopeValue,
            command.TypedValueJson,
            command.ValidUntil,
            command.Reason,
            command.Impact);

        ValidateCode(command.ParameterKey, "Clave de parámetro", checks);

        var definition = await ReadParameterDefinitionAsync(
            connection,
            transaction,
            command.ParameterKey,
            lockRow: false,
            cancellationToken);

        if (definition is null)
        {
            checks.Add("El parámetro no existe o no está activo.");
            return BlockedSimulation(
                "PARAMETER",
                command.ParameterKey,
                "UNKNOWN",
                checks,
                command.TypedValueJson,
                command.ExpectedVersionNo,
                command.ValidUntil);
        }

        ValidateParameterValue(
            definition.ValueType,
            definition.ValidationSchemaJson,
            command.TypedValueJson,
            checks);

        var current = await ReadCurrentParameterAsync(
            connection,
            transaction,
            definition.ParameterDefinitionId,
            command.ScopeCode,
            command.ScopeValue,
            lockRow: false,
            cancellationToken);

        if (current is null)
        {
            checks.Add(
                "BL-MVP-036 solo modifica valores efectivos existentes; no crea una definición o ámbito nuevo.");
            return BlockedSimulation(
                "PARAMETER",
                BuildParameterKey(
                    definition.ParameterKey,
                    command.ScopeCode,
                    command.ScopeValue),
                definition.OwnerModule,
                checks,
                command.TypedValueJson,
                command.ExpectedVersionNo,
                command.ValidUntil);
        }

        if (current.VersionNo != command.ExpectedVersionNo)
        {
            checks.Add(
                $"La versión esperada {command.ExpectedVersionNo} ya no es vigente; la actual es {current.VersionNo}.");
        }

        var proposed = CanonicalizeJson(
            command.TypedValueJson,
            "configuration.change.json.invalid");

        var noOp =
            JsonEquals(current.TypedValueJson, proposed)
            && SameInstant(current.ValidTo, command.ValidUntil);
        if (noOp)
        {
            checks.Add(
                "El valor y la vigencia ya coinciden con la versión efectiva; activar será un no-op idempotente.");
        }

        var blockingChecks = checks
            .Where(static check =>
                !check.Contains(
                    "no-op idempotente",
                    StringComparison.Ordinal))
            .ToArray();

        return new ConfigurationChangeSimulation(
            "PARAMETER",
            BuildParameterKey(
                definition.ParameterKey,
                command.ScopeCode,
                command.ScopeValue),
            definition.OwnerModule,
            blockingChecks.Length == 0,
            checks,
            current.TypedValueJson,
            proposed,
            current.VersionNo,
            current.ValidTo,
            command.ValidUntil,
            HistoricalValueWillBePreserved: true);
    }

    private static async Task<ConfigurationChangeSimulation> SimulateCatalogCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CatalogConfigurationChangeCommand command,
        CancellationToken cancellationToken)
    {
        var checks = ValidateCommon(
            command.CatalogCode,
            "GLOBAL",
            null,
            command.ValueJson,
            command.ValidUntil,
            command.Reason,
            command.Impact);

        ValidateCode(command.CatalogCode, "Código de catálogo", checks);
        ValidateCode(command.EntryCode, "Código de entrada", checks);
        ValidateLabels(command.LabelsJson, checks);

        var definition = await ReadCatalogDefinitionAsync(
            connection,
            transaction,
            command.CatalogCode,
            lockRow: false,
            cancellationToken);

        if (definition is null)
        {
            checks.Add("El catálogo no existe o no está activo.");
            return BlockedSimulation(
                "CATALOG_ENTRY",
                $"{command.CatalogCode}/{command.EntryCode}",
                "UNKNOWN",
                checks,
                command.ValueJson,
                command.ExpectedVersion,
                command.ValidUntil);
        }

        ValidateCatalogValue(
            definition.ValueSchemaJson,
            command.ValueJson,
            checks);

        var current = await ReadCurrentCatalogEntryAsync(
            connection,
            transaction,
            definition.CatalogDefinitionId,
            command.EntryCode,
            lockRow: false,
            cancellationToken);

        if (current is null)
        {
            checks.Add(
                "BL-MVP-036 solo modifica entradas efectivas existentes; la creación de nuevas entradas queda fuera de este corte.");
            return BlockedSimulation(
                "CATALOG_ENTRY",
                $"{definition.CatalogCode}/{command.EntryCode}",
                definition.OwnerModule,
                checks,
                command.ValueJson,
                command.ExpectedVersion,
                command.ValidUntil);
        }

        if (current.CatalogEntryId != command.ExpectedEntryId
            || current.Version != command.ExpectedVersion)
        {
            checks.Add(
                "La entrada cambió desde que se abrió la pantalla; vuelve a cargar antes de activar.");
        }

        var proposedValue = CanonicalizeJson(
            command.ValueJson,
            "configuration.change.json.invalid");
        var proposedLabels = CanonicalizeJson(
            command.LabelsJson,
            "configuration.change.labels.invalid");

        var noOp =
            JsonEquals(current.ValueJson, proposedValue)
            && JsonEquals(current.LabelsJson, proposedLabels)
            && SameInstant(current.ValidTo, command.ValidUntil);
        if (noOp)
        {
            checks.Add(
                "El valor, las etiquetas y la vigencia ya coinciden; activar será un no-op idempotente.");
        }

        var blockingChecks = checks
            .Where(static check =>
                !check.Contains(
                    "no-op idempotente",
                    StringComparison.Ordinal))
            .ToArray();

        return new ConfigurationChangeSimulation(
            "CATALOG_ENTRY",
            $"{definition.CatalogCode}/{current.EntryCode}",
            definition.OwnerModule,
            blockingChecks.Length == 0,
            checks,
            BuildCatalogDocument(
                current.LabelsJson,
                current.ValueJson),
            BuildCatalogDocument(
                proposedLabels,
                proposedValue),
            current.Version,
            current.ValidTo,
            command.ValidUntil,
            HistoricalValueWillBePreserved: true);
    }

    private static async Task<(ConfigurationActivationResult Result, ConfigurationAuditIntent? Audit)> ActivateParameterCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        ParameterConfigurationChangeCommand command,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var checks = ValidateCommon(
            command.ParameterKey,
            command.ScopeCode,
            command.ScopeValue,
            command.TypedValueJson,
            command.ValidUntil,
            command.Reason,
            command.Impact);
        ValidateCode(command.ParameterKey, "Clave de parámetro", checks);
        ThrowIfInvalid(checks);

        var definition = await ReadParameterDefinitionAsync(
            connection,
            transaction,
            command.ParameterKey,
            lockRow: true,
            cancellationToken)
            ?? throw new ConfigurationAdministrationException(
                "configuration.parameter.not-found",
                "El parámetro solicitado no existe o no está activo.");

        checks.Clear();
        ValidateParameterValue(
            definition.ValueType,
            definition.ValidationSchemaJson,
            command.TypedValueJson,
            checks);
        ThrowIfInvalid(checks);

        var now = await ReadDatabaseNowAsync(
            connection,
            transaction,
            cancellationToken);
        ValidateValidUntil(command.ValidUntil, now);

        var current = await ReadCurrentParameterAsync(
            connection,
            transaction,
            definition.ParameterDefinitionId,
            command.ScopeCode,
            command.ScopeValue,
            lockRow: true,
            cancellationToken)
            ?? throw new ConfigurationAdministrationException(
                "configuration.parameter.no-effective-value",
                "BL-MVP-036 requiere un valor efectivo existente para sustituirlo de forma versionada.");

        var proposed = CanonicalizeJson(
            command.TypedValueJson,
            "configuration.change.json.invalid");

        if (current.VersionNo != command.ExpectedVersionNo)
        {
            if (JsonEquals(current.TypedValueJson, proposed)
                && SameInstant(current.ValidTo, command.ValidUntil))
            {
                return (
                    await BuildAlreadyAppliedParameterAsync(
                        connection,
                        transaction,
                        definition,
                        current,
                        cancellationToken),
                    Audit: null);
            }

            throw Concurrency();
        }

        if (JsonEquals(current.TypedValueJson, proposed)
            && SameInstant(current.ValidTo, command.ValidUntil))
        {
            return (
                await BuildAlreadyAppliedParameterAsync(
                    connection,
                    transaction,
                    definition,
                    current,
                    cancellationToken),
                Audit: null);
        }

        await EnsureNoParameterValidityOverlapAsync(
            connection,
            transaction,
            definition.ParameterDefinitionId,
            command.ScopeCode,
            command.ScopeValue,
            current.ParameterVersionId,
            now,
            command.ValidUntil,
            cancellationToken);

        const string closeSql = """
            UPDATE configuration.parameter_version
            SET valid_to = @now,
                status_code = 'SUPERSEDED'
            WHERE parameter_version_id = @id
              AND version_no = @version_no
              AND status_code = 'ACTIVE';
            """;
        await using (var closeCommand =
            new NpgsqlCommand(closeSql, connection, transaction))
        {
            AddTimestamp(closeCommand, "now", now);
            closeCommand.Parameters.Add(
                "id",
                NpgsqlDbType.Uuid).Value =
                current.ParameterVersionId;
            closeCommand.Parameters.Add(
                "version_no",
                NpgsqlDbType.Integer).Value =
                current.VersionNo;
            var affected =
                await closeCommand.ExecuteNonQueryAsync(cancellationToken);
            if (affected != 1)
            {
                throw Concurrency();
            }
        }

        var nextVersion = await ReadNextParameterVersionNoAsync(
            connection,
            transaction,
            definition.ParameterDefinitionId,
            cancellationToken);
        var newId = await InsertParameterVersionAsync(
            connection,
            transaction,
            definition.ParameterDefinitionId,
            nextVersion,
            command.ScopeCode,
            command.ScopeValue,
            proposed,
            now,
            command.ValidUntil,
            command.Reason,
            command.Impact,
            cancellationToken);

        await UpdateEffectiveParameterAsync(
            connection,
            transaction,
            definition.ParameterKey,
            command.ScopeCode,
            command.ScopeValue,
            newId,
            proposed,
            now,
            cancellationToken);

        var beforeDigest = Digest(current.TypedValueJson);
        var afterDigest = Digest(proposed);
        var checksum = Digest(
            $"{Convert.ToHexString(afterDigest)}\n{command.Reason.Trim()}\n{command.Impact.Trim()}");
        var governance = await WriteGovernanceAsync(
            connection,
            transaction,
            actorAccountId,
            "PARAMETER_VERSION",
            current.VersionNo,
            newId,
            checksum,
            correlationId,
            now,
            cancellationToken);

        var result = new ConfigurationActivationResult(
            "PARAMETER",
            BuildParameterKey(
                definition.ParameterKey,
                command.ScopeCode,
                command.ScopeValue),
            definition.OwnerModule,
            newId,
            nextVersion,
            now,
            command.ValidUntil,
            current.ParameterVersionId,
            governance.ChangeSetId,
            governance.ActivationId,
            HistoricalValuePreserved: true,
            AlreadyApplied: false);

        var audit = new ConfigurationAuditIntent(
            "PARAMETER_VERSION",
            newId,
            "CONFIG.PARAMETER.ACTIVATE",
            beforeDigest,
            afterDigest,
            BuildAuditReason(
                command.Reason,
                command.Impact,
                current.ParameterVersionId));

        return (result, audit);
    }

    private static async Task<(ConfigurationActivationResult Result, ConfigurationAuditIntent? Audit)> ActivateCatalogCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        CatalogConfigurationChangeCommand command,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var checks = ValidateCommon(
            command.CatalogCode,
            "GLOBAL",
            null,
            command.ValueJson,
            command.ValidUntil,
            command.Reason,
            command.Impact);
        ValidateCode(command.CatalogCode, "Código de catálogo", checks);
        ValidateCode(command.EntryCode, "Código de entrada", checks);
        ValidateLabels(command.LabelsJson, checks);
        ThrowIfInvalid(checks);

        var definition = await ReadCatalogDefinitionAsync(
            connection,
            transaction,
            command.CatalogCode,
            lockRow: true,
            cancellationToken)
            ?? throw new ConfigurationAdministrationException(
                "configuration.catalog.not-found",
                "El catálogo solicitado no existe o no está activo.");

        checks.Clear();
        ValidateCatalogValue(
            definition.ValueSchemaJson,
            command.ValueJson,
            checks);
        ThrowIfInvalid(checks);

        var now = await ReadDatabaseNowAsync(
            connection,
            transaction,
            cancellationToken);
        ValidateValidUntil(command.ValidUntil, now);

        var current = await ReadCurrentCatalogEntryAsync(
            connection,
            transaction,
            definition.CatalogDefinitionId,
            command.EntryCode,
            lockRow: true,
            cancellationToken)
            ?? throw new ConfigurationAdministrationException(
                "configuration.catalog-entry.no-effective-value",
                "BL-MVP-036 requiere una entrada efectiva existente para sustituirla de forma versionada.");

        var proposedValue = CanonicalizeJson(
            command.ValueJson,
            "configuration.change.json.invalid");
        var proposedLabels = CanonicalizeJson(
            command.LabelsJson,
            "configuration.change.labels.invalid");

        if (current.CatalogEntryId != command.ExpectedEntryId
            || current.Version != command.ExpectedVersion)
        {
            if (JsonEquals(current.ValueJson, proposedValue)
                && JsonEquals(current.LabelsJson, proposedLabels)
                && SameInstant(current.ValidTo, command.ValidUntil))
            {
                return (
                    await BuildAlreadyAppliedCatalogAsync(
                        connection,
                        transaction,
                        definition,
                        current,
                        cancellationToken),
                    Audit: null);
            }

            throw Concurrency();
        }

        if (JsonEquals(current.ValueJson, proposedValue)
            && JsonEquals(current.LabelsJson, proposedLabels)
            && SameInstant(current.ValidTo, command.ValidUntil))
        {
            return (
                await BuildAlreadyAppliedCatalogAsync(
                    connection,
                    transaction,
                    definition,
                    current,
                    cancellationToken),
                Audit: null);
        }

        await EnsureNoCatalogValidityOverlapAsync(
            connection,
            transaction,
            definition.CatalogDefinitionId,
            command.EntryCode,
            current.CatalogEntryId,
            now,
            command.ValidUntil,
            cancellationToken);

        const string closeSql = """
            UPDATE configuration.catalog_entry
            SET valid_to = @now,
                status_code = 'SUPERSEDED'
            WHERE catalog_entry_id = @id
              AND version = @version
              AND status_code = 'ACTIVE';
            """;
        await using (var closeCommand =
            new NpgsqlCommand(closeSql, connection, transaction))
        {
            AddTimestamp(closeCommand, "now", now);
            closeCommand.Parameters.Add(
                "id",
                NpgsqlDbType.Uuid).Value =
                current.CatalogEntryId;
            closeCommand.Parameters.Add(
                "version",
                NpgsqlDbType.Bigint).Value =
                current.Version;
            var affected =
                await closeCommand.ExecuteNonQueryAsync(cancellationToken);
            if (affected != 1)
            {
                throw Concurrency();
            }
        }

        var newId = await InsertCatalogEntryAsync(
            connection,
            transaction,
            definition.CatalogDefinitionId,
            command.EntryCode,
            proposedLabels,
            proposedValue,
            now,
            command.ValidUntil,
            cancellationToken);

        var beforeDigest = Digest(
            BuildCatalogDocument(
                current.LabelsJson,
                current.ValueJson));
        var afterDigest = Digest(
            BuildCatalogDocument(
                proposedLabels,
                proposedValue));
        var checksum = Digest(
            $"{Convert.ToHexString(afterDigest)}\n{command.Reason.Trim()}\n{command.Impact.Trim()}");
        var governance = await WriteGovernanceAsync(
            connection,
            transaction,
            actorAccountId,
            "CATALOG_ENTRY",
            current.Version,
            newId,
            checksum,
            correlationId,
            now,
            cancellationToken);

        var result = new ConfigurationActivationResult(
            "CATALOG_ENTRY",
            $"{definition.CatalogCode}/{command.EntryCode}",
            definition.OwnerModule,
            newId,
            1,
            now,
            command.ValidUntil,
            current.CatalogEntryId,
            governance.ChangeSetId,
            governance.ActivationId,
            HistoricalValuePreserved: true,
            AlreadyApplied: false);

        var audit = new ConfigurationAuditIntent(
            "CATALOG_ENTRY",
            newId,
            "CONFIG.CATALOG.ACTIVATE",
            beforeDigest,
            afterDigest,
            BuildAuditReason(
                command.Reason,
                command.Impact,
                current.CatalogEntryId));

        return (result, audit);
    }

    private static async Task<Guid> InsertParameterVersionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid definitionId,
        int nextVersion,
        string scopeCode,
        string? scopeValue,
        string proposed,
        DateTimeOffset validFrom,
        DateTimeOffset? validUntil,
        string reason,
        string impact,
        CancellationToken cancellationToken)
    {
        var checksum = Digest(
            $"{definitionId:D}\n{nextVersion}\n{scopeCode}\n{scopeValue}\n{proposed}\n{validFrom:O}\n{validUntil:O}\n{reason.Trim()}\n{impact.Trim()}");

        const string sql = """
            INSERT INTO configuration.parameter_version (
                parameter_definition_id,
                version_no,
                scope_code,
                scope_value,
                typed_value,
                valid_from,
                valid_to,
                status_code,
                checksum
            )
            VALUES (
                @definition_id,
                @version_no,
                @scope_code,
                @scope_value,
                @typed_value::jsonb,
                @valid_from,
                @valid_to,
                'ACTIVE',
                @checksum
            )
            RETURNING parameter_version_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "definition_id",
            NpgsqlDbType.Uuid).Value = definitionId;
        command.Parameters.Add(
            "version_no",
            NpgsqlDbType.Integer).Value = nextVersion;
        command.Parameters.Add(
            "scope_code",
            NpgsqlDbType.Varchar).Value =
            scopeCode.Trim().ToUpperInvariant();
        AddNullableText(
            command,
            "scope_value",
            NormalizeScopeValue(
                scopeCode,
                scopeValue));
        command.Parameters.Add(
            "typed_value",
            NpgsqlDbType.Jsonb).Value = proposed;
        AddTimestamp(command, "valid_from", validFrom);
        AddNullableTimestamp(command, "valid_to", validUntil);
        command.Parameters.Add(
            "checksum",
            NpgsqlDbType.Bytea).Value = checksum;

        var result =
            await command.ExecuteScalarAsync(cancellationToken);
        return result is Guid id
            ? id
            : throw new InvalidOperationException(
                "PostgreSQL no devolvió parameter_version_id.");
    }

    private static async Task<Guid> InsertCatalogEntryAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid definitionId,
        string entryCode,
        string labels,
        string value,
        DateTimeOffset validFrom,
        DateTimeOffset? validUntil,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO configuration.catalog_entry (
                catalog_definition_id,
                entry_code,
                labels,
                value,
                valid_from,
                valid_to,
                status_code,
                version
            )
            VALUES (
                @definition_id,
                @entry_code,
                @labels::jsonb,
                @value::jsonb,
                @valid_from,
                @valid_to,
                'ACTIVE',
                1
            )
            RETURNING catalog_entry_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "definition_id",
            NpgsqlDbType.Uuid).Value = definitionId;
        command.Parameters.Add(
            "entry_code",
            NpgsqlDbType.Varchar).Value =
            entryCode.Trim().ToUpperInvariant();
        command.Parameters.Add(
            "labels",
            NpgsqlDbType.Jsonb).Value = labels;
        command.Parameters.Add(
            "value",
            NpgsqlDbType.Jsonb).Value = value;
        AddTimestamp(command, "valid_from", validFrom);
        AddNullableTimestamp(command, "valid_to", validUntil);

        var result =
            await command.ExecuteScalarAsync(cancellationToken);
        return result is Guid id
            ? id
            : throw new InvalidOperationException(
                "PostgreSQL no devolvió catalog_entry_id.");
    }

    private static async Task UpdateEffectiveParameterAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string parameterKey,
        string scopeCode,
        string? scopeValue,
        Guid newVersionId,
        string proposed,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE configuration.effective_parameter
            SET parameter_version_id = @version_id,
                typed_value = @typed_value::jsonb,
                effective_from = @effective_from,
                projection_version = projection_version + 1
            WHERE parameter_key = @parameter_key
              AND scope_code = @scope_code
              AND scope_value IS NOT DISTINCT FROM @scope_value;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "version_id",
            NpgsqlDbType.Uuid).Value = newVersionId;
        command.Parameters.Add(
            "typed_value",
            NpgsqlDbType.Jsonb).Value = proposed;
        AddTimestamp(command, "effective_from", now);
        command.Parameters.Add(
            "parameter_key",
            NpgsqlDbType.Text).Value = parameterKey;
        command.Parameters.Add(
            "scope_code",
            NpgsqlDbType.Varchar).Value =
            scopeCode.Trim().ToUpperInvariant();
        AddNullableText(
            command,
            "scope_value",
            NormalizeScopeValue(
                scopeCode,
                scopeValue));

        var affected =
            await command.ExecuteNonQueryAsync(cancellationToken);
        if (affected != 1)
        {
            throw new ConfigurationAdministrationException(
                "configuration.projection.conflict",
                "La proyección efectiva no resolvió exactamente una fila.");
        }
    }

    private static async Task<GovernanceWrite> WriteGovernanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        string objectType,
        long expectedVersion,
        Guid newObjectId,
        byte[] checksum,
        string correlationId,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        Guid changeSetId;
        const string changeSetSql = """
            INSERT INTO configuration.configuration_change_set (
                status_code,
                created_by,
                created_at,
                validated_at,
                approved_by,
                checksum,
                version
            )
            VALUES (
                'APPLIED',
                @actor_id,
                @now,
                @now,
                @actor_id,
                @checksum,
                1
            )
            RETURNING change_set_id;
            """;
        await using (var command =
            new NpgsqlCommand(
                changeSetSql,
                connection,
                transaction))
        {
            command.Parameters.Add(
                "actor_id",
                NpgsqlDbType.Uuid).Value = actorAccountId;
            AddTimestamp(command, "now", now);
            command.Parameters.Add(
                "checksum",
                NpgsqlDbType.Bytea).Value = checksum;

            var result =
                await command.ExecuteScalarAsync(cancellationToken);
            changeSetId = result is Guid id
                ? id
                : throw new InvalidOperationException(
                    "PostgreSQL no devolvió change_set_id.");
        }

        const string itemSql = """
            INSERT INTO configuration.configuration_change_item (
                change_set_id,
                object_type,
                catalog_entry_id,
                parameter_version_id,
                action_code,
                expected_version
            )
            VALUES (
                @change_set_id,
                @object_type,
                @catalog_entry_id,
                @parameter_version_id,
                'REPLACE',
                @expected_version
            );
            """;
        await using (var command =
            new NpgsqlCommand(itemSql, connection, transaction))
        {
            command.Parameters.Add(
                "change_set_id",
                NpgsqlDbType.Uuid).Value = changeSetId;
            command.Parameters.Add(
                "object_type",
                NpgsqlDbType.Varchar).Value = objectType;

            var catalogParameter =
                command.Parameters.Add(
                    "catalog_entry_id",
                    NpgsqlDbType.Uuid);
            catalogParameter.Value =
                objectType == "CATALOG_ENTRY"
                    ? newObjectId
                    : DBNull.Value;

            var parameterParameter =
                command.Parameters.Add(
                    "parameter_version_id",
                    NpgsqlDbType.Uuid);
            parameterParameter.Value =
                objectType == "PARAMETER_VERSION"
                    ? newObjectId
                    : DBNull.Value;

            command.Parameters.Add(
                "expected_version",
                NpgsqlDbType.Bigint).Value =
                expectedVersion;

            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        Guid activationId;
        const string activationSql = """
            INSERT INTO configuration.configuration_activation (
                change_set_id,
                action_code,
                effective_at,
                applied_by,
                result_code,
                correlation_id
            )
            VALUES (
                @change_set_id,
                'ACTIVATE',
                @now,
                @actor_id,
                'APPLIED',
                @correlation_id
            )
            RETURNING activation_id;
            """;
        await using (var command =
            new NpgsqlCommand(
                activationSql,
                connection,
                transaction))
        {
            command.Parameters.Add(
                "change_set_id",
                NpgsqlDbType.Uuid).Value = changeSetId;
            AddTimestamp(command, "now", now);
            command.Parameters.Add(
                "actor_id",
                NpgsqlDbType.Uuid).Value = actorAccountId;
            command.Parameters.Add(
                "correlation_id",
                NpgsqlDbType.Uuid).Value =
                CorrelationGuid(correlationId);

            var result =
                await command.ExecuteScalarAsync(cancellationToken);
            activationId = result is Guid id
                ? id
                : throw new InvalidOperationException(
                    "PostgreSQL no devolvió activation_id.");
        }

        return new GovernanceWrite(
            changeSetId,
            activationId);
    }

    private static async Task<ConfigurationActivationResult> BuildAlreadyAppliedParameterAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ParameterDefinitionRow definition,
        ParameterVersionRow current,
        CancellationToken cancellationToken)
    {
        var governance = await ReadLatestGovernanceAsync(
            connection,
            transaction,
            "PARAMETER_VERSION",
            current.ParameterVersionId,
            cancellationToken);

        return new ConfigurationActivationResult(
            "PARAMETER",
            BuildParameterKey(
                definition.ParameterKey,
                current.ScopeCode,
                current.ScopeValue),
            definition.OwnerModule,
            current.ParameterVersionId,
            current.VersionNo,
            current.ValidFrom,
            current.ValidTo,
            current.ParameterVersionId,
            governance.ChangeSetId,
            governance.ActivationId,
            HistoricalValuePreserved: true,
            AlreadyApplied: true);
    }

    private static async Task<ConfigurationActivationResult> BuildAlreadyAppliedCatalogAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CatalogDefinitionRow definition,
        CatalogEntryRow current,
        CancellationToken cancellationToken)
    {
        var governance = await ReadLatestGovernanceAsync(
            connection,
            transaction,
            "CATALOG_ENTRY",
            current.CatalogEntryId,
            cancellationToken);

        return new ConfigurationActivationResult(
            "CATALOG_ENTRY",
            $"{definition.CatalogCode}/{current.EntryCode}",
            definition.OwnerModule,
            current.CatalogEntryId,
            current.Version,
            current.ValidFrom,
            current.ValidTo,
            current.CatalogEntryId,
            governance.ChangeSetId,
            governance.ActivationId,
            HistoricalValuePreserved: true,
            AlreadyApplied: true);
    }

    private static async Task<GovernanceWrite> ReadLatestGovernanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string objectType,
        Guid objectId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                i.change_set_id,
                a.activation_id
            FROM configuration.configuration_change_item i
            JOIN configuration.configuration_activation a
              ON a.change_set_id = i.change_set_id
            WHERE i.object_type = @object_type
              AND (
                    i.catalog_entry_id = @object_id
                 OR i.parameter_version_id = @object_id
              )
            ORDER BY a.effective_at DESC
            LIMIT 1;
            """;
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "object_type",
            NpgsqlDbType.Varchar).Value = objectType;
        command.Parameters.Add(
            "object_id",
            NpgsqlDbType.Uuid).Value = objectId;
        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);
        if (await reader.ReadAsync(cancellationToken))
        {
            return new GovernanceWrite(
                reader.GetGuid(0),
                reader.GetGuid(1));
        }

        return new GovernanceWrite(
            Guid.Empty,
            Guid.Empty);
    }

    private static async Task<ParameterDefinitionRow?> ReadParameterDefinitionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string parameterKey,
        bool lockRow,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT
                parameter_definition_id,
                parameter_key,
                owner_module,
                value_type,
                validation_schema::text
            FROM configuration.parameter_definition
            WHERE parameter_key = @parameter_key
              AND status_code = 'ACTIVE'
            """
            + (lockRow ? " FOR UPDATE;" : ";");

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "parameter_key",
            NpgsqlDbType.Text).Value =
            parameterKey.Trim().ToUpperInvariant();
        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new ParameterDefinitionRow(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4));
    }

    private static async Task<ParameterVersionRow?> ReadCurrentParameterAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid definitionId,
        string scopeCode,
        string? scopeValue,
        bool lockRow,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT
                parameter_version_id,
                version_no,
                scope_code,
                scope_value,
                typed_value::text,
                valid_from,
                valid_to
            FROM configuration.parameter_version
            WHERE parameter_definition_id = @definition_id
              AND scope_code = @scope_code
              AND scope_value IS NOT DISTINCT FROM @scope_value
              AND status_code = 'ACTIVE'
              AND valid_from <= CURRENT_TIMESTAMP
              AND (valid_to IS NULL OR valid_to > CURRENT_TIMESTAMP)
            ORDER BY valid_from DESC
            LIMIT 1
            """
            + (lockRow ? " FOR UPDATE;" : ";");

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "definition_id",
            NpgsqlDbType.Uuid).Value = definitionId;
        command.Parameters.Add(
            "scope_code",
            NpgsqlDbType.Varchar).Value =
            scopeCode.Trim().ToUpperInvariant();
        AddNullableText(
            command,
            "scope_value",
            NormalizeScopeValue(
                scopeCode,
                scopeValue));
        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new ParameterVersionRow(
            reader.GetGuid(0),
            reader.GetInt32(1),
            reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3),
            reader.GetString(4),
            ReadUtc(reader, 5),
            ReadNullableUtc(reader, 6));
    }

    private static async Task<CatalogDefinitionRow?> ReadCatalogDefinitionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string catalogCode,
        bool lockRow,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT
                catalog_definition_id,
                catalog_code,
                owner_module,
                value_schema::text
            FROM configuration.catalog_definition
            WHERE catalog_code = @catalog_code
              AND status_code = 'ACTIVE'
            """
            + (lockRow ? " FOR UPDATE;" : ";");

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "catalog_code",
            NpgsqlDbType.Varchar).Value =
            catalogCode.Trim().ToUpperInvariant();
        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new CatalogDefinitionRow(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3));
    }

    private static async Task<CatalogEntryRow?> ReadCurrentCatalogEntryAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid definitionId,
        string entryCode,
        bool lockRow,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT
                catalog_entry_id,
                entry_code,
                labels::text,
                value::text,
                valid_from,
                valid_to,
                version
            FROM configuration.catalog_entry
            WHERE catalog_definition_id = @definition_id
              AND entry_code = @entry_code
              AND status_code = 'ACTIVE'
              AND valid_from <= CURRENT_TIMESTAMP
              AND (valid_to IS NULL OR valid_to > CURRENT_TIMESTAMP)
            ORDER BY valid_from DESC
            LIMIT 1
            """
            + (lockRow ? " FOR UPDATE;" : ";");

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "definition_id",
            NpgsqlDbType.Uuid).Value = definitionId;
        command.Parameters.Add(
            "entry_code",
            NpgsqlDbType.Varchar).Value =
            entryCode.Trim().ToUpperInvariant();
        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new CatalogEntryRow(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            ReadUtc(reader, 4),
            ReadNullableUtc(reader, 5),
            reader.GetInt64(6));
    }

    private static async Task<int> ReadNextParameterVersionNoAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid definitionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT COALESCE(MAX(version_no), 0) + 1
            FROM configuration.parameter_version
            WHERE parameter_definition_id = @definition_id;
            """;
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "definition_id",
            NpgsqlDbType.Uuid).Value = definitionId;
        var value =
            await command.ExecuteScalarAsync(cancellationToken);
        return Convert.ToInt32(
            value,
            CultureInfo.InvariantCulture);
    }

    private static async Task<DateTimeOffset> ReadDatabaseNowAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT CURRENT_TIMESTAMP;",
            connection,
            transaction);
        var value =
            await command.ExecuteScalarAsync(cancellationToken);
        if (value is not DateTime timestamp)
        {
            throw new InvalidOperationException(
                "PostgreSQL no devolvió CURRENT_TIMESTAMP.");
        }

        return new DateTimeOffset(
            DateTime.SpecifyKind(
                timestamp,
                DateTimeKind.Utc));
    }

    private static async Task EnsureNoParameterValidityOverlapAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid definitionId,
        string scopeCode,
        string? scopeValue,
        Guid excludedId,
        DateTimeOffset validFrom,
        DateTimeOffset? validUntil,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM configuration.parameter_version
                WHERE parameter_definition_id = @definition_id
                  AND scope_code = @scope_code
                  AND scope_value IS NOT DISTINCT FROM @scope_value
                  AND status_code IN ('ACTIVE', 'SCHEDULED')
                  AND parameter_version_id <> @excluded_id
                  AND (@valid_until IS NULL OR valid_from < @valid_until)
                  AND (valid_to IS NULL OR valid_to > @valid_from)
            );
            """;
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "definition_id",
            NpgsqlDbType.Uuid).Value = definitionId;
        command.Parameters.Add(
            "scope_code",
            NpgsqlDbType.Varchar).Value =
            scopeCode.Trim().ToUpperInvariant();
        AddNullableText(
            command,
            "scope_value",
            NormalizeScopeValue(
                scopeCode,
                scopeValue));
        command.Parameters.Add(
            "excluded_id",
            NpgsqlDbType.Uuid).Value = excludedId;
        AddTimestamp(command, "valid_from", validFrom);
        AddNullableTimestamp(command, "valid_until", validUntil);
        var exists =
            await command.ExecuteScalarAsync(cancellationToken);
        if (exists is true)
        {
            throw new ConfigurationAdministrationException(
                "configuration.change.validity-overlap",
                "Existe otra versión activa o programada que se superpone con la vigencia solicitada.");
        }
    }

    private static async Task EnsureNoCatalogValidityOverlapAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid definitionId,
        string entryCode,
        Guid excludedId,
        DateTimeOffset validFrom,
        DateTimeOffset? validUntil,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM configuration.catalog_entry
                WHERE catalog_definition_id = @definition_id
                  AND entry_code = @entry_code
                  AND status_code IN ('ACTIVE', 'SCHEDULED')
                  AND catalog_entry_id <> @excluded_id
                  AND (@valid_until IS NULL OR valid_from < @valid_until)
                  AND (valid_to IS NULL OR valid_to > @valid_from)
            );
            """;
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "definition_id",
            NpgsqlDbType.Uuid).Value = definitionId;
        command.Parameters.Add(
            "entry_code",
            NpgsqlDbType.Varchar).Value =
            entryCode.Trim().ToUpperInvariant();
        command.Parameters.Add(
            "excluded_id",
            NpgsqlDbType.Uuid).Value = excludedId;
        AddTimestamp(command, "valid_from", validFrom);
        AddNullableTimestamp(command, "valid_until", validUntil);
        var exists =
            await command.ExecuteScalarAsync(cancellationToken);
        if (exists is true)
        {
            throw new ConfigurationAdministrationException(
                "configuration.change.validity-overlap",
                "Existe otra entrada activa o programada que se superpone con la vigencia solicitada.");
        }
    }

    private static List<string> ValidateCommon(
        string objectKey,
        string scopeCode,
        string? scopeValue,
        string json,
        DateTimeOffset? validUntil,
        string reason,
        string impact)
    {
        var checks = new List<string>();

        ValidateCode(scopeCode, "Ámbito", checks);

        if (string.Equals(
                scopeCode,
                "GLOBAL",
                StringComparison.OrdinalIgnoreCase)
            && !string.IsNullOrWhiteSpace(scopeValue))
        {
            checks.Add(
                "El ámbito GLOBAL no admite scopeValue.");
        }

        if (!string.Equals(
                scopeCode,
                "GLOBAL",
                StringComparison.OrdinalIgnoreCase)
            && string.IsNullOrWhiteSpace(scopeValue))
        {
            checks.Add(
                "Un ámbito no global requiere scopeValue.");
        }

        if (scopeValue?.Length > 512)
        {
            checks.Add(
                "scopeValue supera 512 caracteres.");
        }

        if (string.IsNullOrWhiteSpace(reason)
            || reason.Trim().Length > MaxReasonLength)
        {
            checks.Add(
                $"El motivo es obligatorio y no puede superar {MaxReasonLength} caracteres.");
        }

        if (string.IsNullOrWhiteSpace(impact)
            || impact.Trim().Length > MaxImpactLength)
        {
            checks.Add(
                $"El impacto es obligatorio y no puede superar {MaxImpactLength} caracteres.");
        }

        if (json.Length == 0
            || json.Length > MaxJsonLength)
        {
            checks.Add(
                $"El valor JSON debe tener entre 1 y {MaxJsonLength} caracteres.");
        }
        else
        {
            try
            {
                using var document = JsonDocument.Parse(json);
                if (ContainsSecretLikeProperty(
                        document.RootElement))
                {
                    checks.Add(
                        "El valor contiene un campo con nombre de secreto; M19 no persiste secretos.");
                }
            }
            catch (JsonException)
            {
                checks.Add(
                    "El valor no contiene JSON válido.");
            }
        }

        if (SecretNamePattern().IsMatch(objectKey))
        {
            checks.Add(
                "La clave parece corresponder a un secreto y debe usar el mecanismo protegido de M18.");
        }

        if (validUntil is { } until
            && until <= DateTimeOffset.UtcNow.AddMinutes(-1))
        {
            checks.Add(
                "La vigencia final no puede estar en el pasado.");
        }

        return checks;
    }

    private static void ValidateParameterValue(
        string valueType,
        string validationSchemaJson,
        string valueJson,
        List<string> checks)
    {
        JsonDocument valueDocument;
        try
        {
            valueDocument = JsonDocument.Parse(valueJson);
        }
        catch (JsonException)
        {
            return;
        }

        using (valueDocument)
        {
            var value = valueDocument.RootElement;
            var type = valueType.Trim().ToUpperInvariant();

            var typeValid = type switch
            {
                "INTEGER" =>
                    value.ValueKind == JsonValueKind.Number
                    && value.TryGetInt64(out _),
                "DECIMAL" =>
                    value.ValueKind == JsonValueKind.Number,
                "BOOLEAN" =>
                    value.ValueKind is JsonValueKind.True
                        or JsonValueKind.False,
                "STRING" or "REFERENCE" =>
                    value.ValueKind == JsonValueKind.String,
                "LIST" =>
                    value.ValueKind == JsonValueKind.Array,
                _ => false
            };

            if (!typeValid)
            {
                checks.Add(
                    $"El valor no cumple el tipo declarado {type}.");
                return;
            }

            ApplySimpleJsonSchema(
                value,
                validationSchemaJson,
                checks);
        }
    }

    private static void ValidateCatalogValue(
        string valueSchemaJson,
        string valueJson,
        List<string> checks)
    {
        JsonDocument valueDocument;
        try
        {
            valueDocument = JsonDocument.Parse(valueJson);
        }
        catch (JsonException)
        {
            return;
        }

        using (valueDocument)
        {
            ApplySimpleJsonSchema(
                valueDocument.RootElement,
                valueSchemaJson,
                checks);
        }
    }

    private static void ApplySimpleJsonSchema(
        JsonElement value,
        string schemaJson,
        List<string> checks)
    {
        JsonDocument schemaDocument;
        try
        {
            schemaDocument = JsonDocument.Parse(schemaJson);
        }
        catch (JsonException)
        {
            checks.Add(
                "El esquema publicado no contiene JSON válido.");
            return;
        }

        using (schemaDocument)
        {
            var schema = schemaDocument.RootElement;
            if (schema.ValueKind != JsonValueKind.Object)
            {
                checks.Add(
                    "El esquema publicado debe ser un objeto JSON.");
                return;
            }

            if (schema.TryGetProperty(
                    "type",
                    out var typeProperty)
                && typeProperty.ValueKind == JsonValueKind.String)
            {
                var expected = typeProperty.GetString();
                var matches = expected switch
                {
                    "string" =>
                        value.ValueKind == JsonValueKind.String,
                    "integer" =>
                        value.ValueKind == JsonValueKind.Number
                        && value.TryGetInt64(out _),
                    "number" =>
                        value.ValueKind == JsonValueKind.Number,
                    "boolean" =>
                        value.ValueKind is JsonValueKind.True
                            or JsonValueKind.False,
                    "object" =>
                        value.ValueKind == JsonValueKind.Object,
                    "array" =>
                        value.ValueKind == JsonValueKind.Array,
                    null => true,
                    _ => false
                };
                if (!matches)
                {
                    checks.Add(
                        $"El valor no cumple schema.type={expected}.");
                }
            }

            if (value.ValueKind == JsonValueKind.Number
                && value.TryGetDecimal(out var number))
            {
                if (schema.TryGetProperty(
                        "minimum",
                        out var minimum)
                    && minimum.TryGetDecimal(out var min)
                    && number < min)
                {
                    checks.Add(
                        $"El valor es menor que el mínimo publicado ({min}).");
                }

                if (schema.TryGetProperty(
                        "maximum",
                        out var maximum)
                    && maximum.TryGetDecimal(out var max)
                    && number > max)
                {
                    checks.Add(
                        $"El valor supera el máximo publicado ({max}).");
                }
            }

            if (value.ValueKind == JsonValueKind.String)
            {
                var text = value.GetString() ?? string.Empty;
                if (schema.TryGetProperty(
                        "minLength",
                        out var minLength)
                    && minLength.TryGetInt32(out var min)
                    && text.Length < min)
                {
                    checks.Add(
                        $"El texto es menor que minLength={min}.");
                }

                if (schema.TryGetProperty(
                        "maxLength",
                        out var maxLength)
                    && maxLength.TryGetInt32(out var max)
                    && text.Length > max)
                {
                    checks.Add(
                        $"El texto supera maxLength={max}.");
                }
            }

            if (schema.TryGetProperty(
                    "enum",
                    out var enumeration)
                && enumeration.ValueKind == JsonValueKind.Array)
            {
                var found = enumeration
                    .EnumerateArray()
                    .Any(candidate =>
                        JsonEquals(
                            candidate.GetRawText(),
                            value.GetRawText()));
                if (!found)
                {
                    checks.Add(
                        "El valor no pertenece al enum publicado.");
                }
            }
        }
    }

    private static void ValidateLabels(
        string labelsJson,
        List<string> checks)
    {
        if (labelsJson.Length == 0
            || labelsJson.Length > MaxJsonLength)
        {
            checks.Add(
                $"Las etiquetas deben tener entre 1 y {MaxJsonLength} caracteres.");
            return;
        }

        try
        {
            using var document =
                JsonDocument.Parse(labelsJson);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                checks.Add(
                    "Las etiquetas deben ser un objeto JSON.");
                return;
            }

            if (!root.TryGetProperty(
                    "es",
                    out var spanish)
                || spanish.ValueKind != JsonValueKind.String
                || string.IsNullOrWhiteSpace(
                    spanish.GetString()))
            {
                checks.Add(
                    "Las etiquetas requieren una localización española no vacía.");
            }

            foreach (var property in root.EnumerateObject())
            {
                if (SecretNamePattern().IsMatch(
                        property.Name))
                {
                    checks.Add(
                        "Las etiquetas contienen un campo con nombre de secreto.");
                    break;
                }

                if (property.Value.ValueKind
                    != JsonValueKind.String)
                {
                    checks.Add(
                        "Cada etiqueta localizada debe ser texto.");
                    break;
                }
            }
        }
        catch (JsonException)
        {
            checks.Add(
                "Las etiquetas no contienen JSON válido.");
        }
    }

    private static void ValidateCode(
        string? value,
        string label,
        List<string> checks)
    {
        if (string.IsNullOrWhiteSpace(value)
            || !CodePattern().IsMatch(
                value.Trim().ToUpperInvariant()))
        {
            checks.Add(
                $"{label} no cumple el formato canónico.");
        }
    }

    private static void ValidateValidUntil(
        DateTimeOffset? validUntil,
        DateTimeOffset now)
    {
        if (validUntil is { } until
            && until <= now)
        {
            throw new ConfigurationAdministrationException(
                "configuration.change.validity.invalid",
                "La vigencia final debe ser posterior al instante de activación.");
        }
    }

    private static void ThrowIfInvalid(
        List<string> checks)
    {
        if (checks.Count == 0)
        {
            return;
        }

        var secret = checks.Any(
            static check =>
                check.Contains(
                    "secreto",
                    StringComparison.OrdinalIgnoreCase));
        throw new ConfigurationAdministrationException(
            secret
                ? "configuration.change.secret-rejected"
                : "configuration.change.invalid",
            string.Join(" ", checks));
    }

    private static ConfigurationAdministrationException Concurrency() =>
        new(
            "configuration.change.concurrency",
            "La configuración cambió desde que se abrió la pantalla. Vuelve a cargar, simula de nuevo y reintenta.");

    private static ConfigurationChangeSimulation BlockedSimulation(
        string objectType,
        string objectKey,
        string ownerModule,
        IReadOnlyList<string> checks,
        string afterJson,
        long expectedVersion,
        DateTimeOffset? proposedValidUntil) =>
        new(
            objectType,
            objectKey,
            ownerModule,
            false,
            checks,
            "Sin valor efectivo editable",
            NormalizeJsonOrOriginal(afterJson),
            expectedVersion,
            null,
            proposedValidUntil,
            HistoricalValueWillBePreserved: true);

    private static string CanonicalizeJson(
        string json,
        string errorCode)
    {
        try
        {
            using var document =
                JsonDocument.Parse(json);
            return JsonSerializer.Serialize(
                document.RootElement);
        }
        catch (JsonException)
        {
            throw new ConfigurationAdministrationException(
                errorCode,
                "El valor enviado no contiene JSON válido.");
        }
    }

    private static string NormalizeJsonOrOriginal(
        string json)
    {
        try
        {
            return CanonicalizeJson(
                json,
                "configuration.change.json.invalid");
        }
        catch (ConfigurationAdministrationException)
        {
            return json;
        }
    }

    private static bool JsonEquals(
        string left,
        string right)
    {
        try
        {
            using var leftDocument =
                JsonDocument.Parse(left);
            using var rightDocument =
                JsonDocument.Parse(right);
            return JsonElement.DeepEquals(
                leftDocument.RootElement,
                rightDocument.RootElement);
        }
        catch (JsonException)
        {
            return string.Equals(
                left,
                right,
                StringComparison.Ordinal);
        }
    }

    private static bool ContainsSecretLikeProperty(
        JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                if (SecretNamePattern().IsMatch(property.Name)
                    || ContainsSecretLikeProperty(property.Value))
                {
                    return true;
                }
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var child in element.EnumerateArray())
            {
                if (ContainsSecretLikeProperty(child))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static string BuildCatalogDocument(
        string labelsJson,
        string valueJson)
    {
        using var labelsDocument =
            JsonDocument.Parse(labelsJson);
        using var valueDocument =
            JsonDocument.Parse(valueJson);

        return JsonSerializer.Serialize(
            new
            {
                labels = labelsDocument.RootElement.Clone(),
                value = valueDocument.RootElement.Clone()
            });
    }

    private static byte[] Digest(string value) =>
        SHA256.HashData(
            Encoding.UTF8.GetBytes(value));

    private static Guid CorrelationGuid(
        string correlationId)
    {
        if (Guid.TryParse(
                correlationId,
                out var parsed)
            && parsed != Guid.Empty)
        {
            return parsed;
        }

        var digest = Digest(
            $"CORRELATION|{correlationId.Trim()}");
        try
        {
            Span<byte> bytes = stackalloc byte[16];
            digest.AsSpan(0, 16).CopyTo(bytes);
            return new Guid(bytes);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(digest);
        }
    }

    private static string BuildAuditReason(
        string reason,
        string impact,
        Guid previousObjectId) =>
        $"Motivo: {reason.Trim()} | Impacto: {impact.Trim()} | Versión anterior: {previousObjectId:D}";

    private static string BuildParameterKey(
        string parameterKey,
        string scopeCode,
        string? scopeValue) =>
        string.IsNullOrWhiteSpace(scopeValue)
            ? $"{parameterKey}@{scopeCode}"
            : $"{parameterKey}@{scopeCode}:{scopeValue}";

    private static string? NormalizeScopeValue(
        string scopeCode,
        string? scopeValue) =>
        string.Equals(
            scopeCode,
            "GLOBAL",
            StringComparison.OrdinalIgnoreCase)
            ? null
            : scopeValue?.Trim();

    private static void AddTimestamp(
        NpgsqlCommand command,
        string name,
        DateTimeOffset value)
    {
        command.Parameters.Add(
            name,
            NpgsqlDbType.TimestampTz).Value =
            value.UtcDateTime;
    }

    private static void AddNullableTimestamp(
        NpgsqlCommand command,
        string name,
        DateTimeOffset? value)
    {
        var parameter =
            command.Parameters.Add(
                name,
                NpgsqlDbType.TimestampTz);
        parameter.Value =
            value is { } timestamp
                ? timestamp.UtcDateTime
                : DBNull.Value;
    }

    private static void AddNullableText(
        NpgsqlCommand command,
        string name,
        string? value)
    {
        var parameter =
            command.Parameters.Add(
                name,
                NpgsqlDbType.Text);
        parameter.Value =
            value is null
                ? DBNull.Value
                : value;
    }

    private static DateTimeOffset ReadUtc(
        NpgsqlDataReader reader,
        int ordinal) =>
        new(
            DateTime.SpecifyKind(
                reader.GetDateTime(ordinal),
                DateTimeKind.Utc));

    private static DateTimeOffset? ReadNullableUtc(
        NpgsqlDataReader reader,
        int ordinal) =>
        reader.IsDBNull(ordinal)
            ? null
            : ReadUtc(reader, ordinal);

    private static bool SameInstant(
        DateTimeOffset? left,
        DateTimeOffset? right)
    {
        if (left is null || right is null)
        {
            return left is null && right is null;
        }

        return Math.Abs(
            (left.Value.ToUniversalTime()
             - right.Value.ToUniversalTime())
            .TotalSeconds) < 1;
    }

    private sealed record ParameterDefinitionRow(
        Guid ParameterDefinitionId,
        string ParameterKey,
        string OwnerModule,
        string ValueType,
        string ValidationSchemaJson);

    private sealed record ParameterVersionRow(
        Guid ParameterVersionId,
        int VersionNo,
        string ScopeCode,
        string? ScopeValue,
        string TypedValueJson,
        DateTimeOffset ValidFrom,
        DateTimeOffset? ValidTo);

    private sealed record CatalogDefinitionRow(
        Guid CatalogDefinitionId,
        string CatalogCode,
        string OwnerModule,
        string ValueSchemaJson);

    private sealed record CatalogEntryRow(
        Guid CatalogEntryId,
        string EntryCode,
        string LabelsJson,
        string ValueJson,
        DateTimeOffset ValidFrom,
        DateTimeOffset? ValidTo,
        long Version);

    private sealed record GovernanceWrite(
        Guid ChangeSetId,
        Guid ActivationId);

    private sealed class CatalogAccumulator(
        string catalogCode,
        string ownerModule,
        string valueSchemaJson,
        long definitionVersion)
    {
        public string CatalogCode { get; } = catalogCode;

        public string OwnerModule { get; } = ownerModule;

        public string ValueSchemaJson { get; } =
            valueSchemaJson;

        public long DefinitionVersion { get; } =
            definitionVersion;

        public List<ConfigurationCatalogEntryView> Entries { get; } =
            [];
    }
}
