using Microsoft.Extensions.Configuration;
using Npgsql;

namespace MusicaAprender.Modules.Configuration.Infrastructure.Publication;

public sealed record MinimumCatalogExpectation(
    string CatalogCode,
    string SafeEntryCode);

public sealed record MinimumParameterExpectation(
    string ParameterKey,
    string SafeValueJson);

public sealed record MinimumRetentionPolicyExpectation(
    string DataClass,
    string PurposeCode,
    int RetentionDays,
    string TriggerCode);

public static class MinimumPublishedConfigurationManifest
{
    public const int MinimumCatalogEntryCount = 59;

    public static IReadOnlyList<MinimumCatalogExpectation> Catalogs { get; } =
    [
        new("ACCOUNT_STATUS", "DISABLED"),
        new("REVISION_STATUS", "DRAFT"),
        new("PUBLICATION_STATUS", "WITHDRAWN"),
        new("PACKAGE_STATUS", "DRAFT"),
        new("SESSION_STATUS", "PAUSED"),
        new("INSTANCE_STATUS", "CREATED"),
        new("JOB_STATUS", "NEEDS_REVIEW"),
        new("PRIVACY_STATUS", "RECEIVED"),
        new("LANGUAGE", "ES"),
        new("PROVIDER", "YOUTUBE"),
        new("JLPT_LEVEL", "N5"),
        new("DATA_CLASS", "RESTRICTED")
    ];

    public static IReadOnlyList<MinimumParameterExpectation> Parameters { get; } =
    [
        new("PLAYER_SYNC_TOLERANCE_MS", "120"),
        new("SESSION_IDLE_MINUTES", "30"),
        new("SESSION_ABSOLUTE_HOURS", "24"),
        new("EDITORIAL_LOCK_SECONDS", "300"),
        new("IDEMPOTENCY_RETENTION_HOURS", "24"),
        new("MAX_JOB_ATTEMPTS", "8"),
        new("SEARCH_MIN_QUERY_LENGTH", "2"),
        new("MFA_REQUIRED_PRIVILEGED", "true"),
        new("PUBLICATION_DEFAULT_LANGUAGE", "\"es\""),
        new("JOB_ATTEMPT_RETENTION_DAYS", "90")
    ];

    public static IReadOnlyList<MinimumRetentionPolicyExpectation> RetentionPolicies { get; } =
    [
        new("INTERNAL", "JOB_ATTEMPT", 90, "FINISHED_AT"),
        new("RESTRICTED", "SECURITY_EVENT", 365, "OCCURRED_AT"),
        new("RESTRICTED", "SECURITY_TOKEN", 7, "EXPIRES_AT")
    ];
}

public sealed record MinimumPublishedConfigurationStatus(
    bool StorageAvailable,
    int PublishedCatalogCount,
    int PublishedCatalogEntryCount,
    int EffectiveParameterCount,
    int RetentionPolicyCount,
    IReadOnlyList<string> MissingItems)
{
    public bool IsComplete =>
        StorageAvailable
        && PublishedCatalogCount == MinimumPublishedConfigurationManifest.Catalogs.Count
        && PublishedCatalogEntryCount >= MinimumPublishedConfigurationManifest.MinimumCatalogEntryCount
        && EffectiveParameterCount == MinimumPublishedConfigurationManifest.Parameters.Count
        && RetentionPolicyCount >= MinimumPublishedConfigurationManifest.RetentionPolicies.Count
        && MissingItems.Count == 0;
}

public sealed class MinimumPublishedConfigurationReader(IConfiguration configuration)
{
    public async Task<MinimumPublishedConfigurationStatus> InspectAsync(
        CancellationToken cancellationToken = default)
    {
        var connectionString = configuration.GetConnectionString("PostgreSQL");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return UnavailableStatus();
        }

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            var catalogs = await ReadCurrentCatalogEntriesAsync(
                connection,
                cancellationToken);
            var parameters = await ReadCurrentEffectiveParametersAsync(
                connection,
                cancellationToken);
            var policies = await ReadCurrentRetentionPoliciesAsync(
                connection,
                cancellationToken);

            var missing = new List<string>();

            foreach (var expected in MinimumPublishedConfigurationManifest.Catalogs)
            {
                if (!catalogs.Contains(CatalogEntryKey(
                        expected.CatalogCode,
                        expected.SafeEntryCode)))
                {
                    missing.Add($"catalog:{expected.CatalogCode}/{expected.SafeEntryCode}");
                }
            }

            foreach (var expected in MinimumPublishedConfigurationManifest.Parameters)
            {
                if (!parameters.TryGetValue(expected.ParameterKey, out var safeValueJson)
                    || !string.Equals(
                        safeValueJson,
                        expected.SafeValueJson,
                        StringComparison.Ordinal))
                {
                    missing.Add($"parameter:{expected.ParameterKey}");
                }
            }

            foreach (var expected in MinimumPublishedConfigurationManifest.RetentionPolicies)
            {
                var key = RetentionPolicyKey(
                    expected.DataClass,
                    expected.PurposeCode);
                if (!policies.TryGetValue(key, out var published)
                    || published.RetentionDays != expected.RetentionDays
                    || !string.Equals(
                        published.TriggerCode,
                        expected.TriggerCode,
                        StringComparison.Ordinal))
                {
                    missing.Add($"retention:{expected.DataClass}/{expected.PurposeCode}");
                }
            }

            return new MinimumPublishedConfigurationStatus(
                StorageAvailable: true,
                PublishedCatalogCount: catalogs
                    .Select(static item => item[..item.IndexOf('\u001f')])
                    .Distinct(StringComparer.Ordinal)
                    .Count(),
                PublishedCatalogEntryCount: catalogs.Count,
                EffectiveParameterCount: parameters.Count,
                RetentionPolicyCount: policies.Count,
                MissingItems: missing);
        }
        catch (NpgsqlException)
        {
            return UnavailableStatus();
        }
        catch (InvalidOperationException)
        {
            return UnavailableStatus();
        }
        catch (ArgumentException)
        {
            return UnavailableStatus();
        }
    }

    private static async Task<HashSet<string>> ReadCurrentCatalogEntriesAsync(
        NpgsqlConnection connection,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT d.catalog_code, e.entry_code
            FROM configuration.catalog_definition d
            JOIN configuration.catalog_entry e
              ON e.catalog_definition_id = d.catalog_definition_id
            WHERE d.catalog_code = ANY (@catalog_codes)
              AND d.status_code = 'ACTIVE'
              AND d.version > 0
              AND e.status_code = 'ACTIVE'
              AND e.version > 0
              AND e.labels ? 'es'
              AND e.valid_from <= CURRENT_TIMESTAMP
              AND (e.valid_to IS NULL OR e.valid_to > CURRENT_TIMESTAMP);
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "catalog_codes",
            MinimumPublishedConfigurationManifest.Catalogs
                .Select(static item => item.CatalogCode)
                .ToArray());

        var result = new HashSet<string>(StringComparer.Ordinal);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(CatalogEntryKey(reader.GetString(0), reader.GetString(1)));
        }

        return result;
    }

    private static async Task<Dictionary<string, string>> ReadCurrentEffectiveParametersAsync(
        NpgsqlConnection connection,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT d.parameter_key, d.default_value::text
            FROM configuration.parameter_definition d
            JOIN configuration.parameter_version v
              ON v.parameter_definition_id = d.parameter_definition_id
            JOIN configuration.effective_parameter e
              ON e.parameter_version_id = v.parameter_version_id
             AND e.parameter_key = d.parameter_key
            WHERE d.parameter_key = ANY (@parameter_keys)
              AND d.status_code = 'ACTIVE'
              AND d.default_value IS NOT NULL
              AND v.status_code = 'ACTIVE'
              AND v.version_no > 0
              AND v.scope_code = 'GLOBAL'
              AND v.scope_value IS NULL
              AND jsonb_typeof(v.typed_value) = CASE d.value_type
                    WHEN 'INTEGER' THEN 'number'
                    WHEN 'BOOLEAN' THEN 'boolean'
                    WHEN 'STRING' THEN 'string'
                    ELSE jsonb_typeof(v.typed_value)
                  END
              AND v.valid_from <= CURRENT_TIMESTAMP
              AND (v.valid_to IS NULL OR v.valid_to > CURRENT_TIMESTAMP)
              AND e.scope_code = v.scope_code
              AND e.scope_value IS NOT DISTINCT FROM v.scope_value
              AND e.typed_value = v.typed_value
              AND e.effective_from <= CURRENT_TIMESTAMP
              AND e.projection_version > 0;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "parameter_keys",
            MinimumPublishedConfigurationManifest.Parameters
                .Select(static item => item.ParameterKey)
                .ToArray());

        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result[reader.GetString(0)] = reader.GetString(1);
        }

        return result;
    }

    private static async Task<Dictionary<string, PublishedRetentionPolicy>> ReadCurrentRetentionPoliciesAsync(
        NpgsqlConnection connection,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT data_class, purpose_code, retention_days, trigger_code
            FROM configuration.retention_policy
            WHERE version > 0
              AND retention_days >= 0
              AND valid_from <= CURRENT_TIMESTAMP;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        var result = new Dictionary<string, PublishedRetentionPolicy>(StringComparer.Ordinal);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result[RetentionPolicyKey(reader.GetString(0), reader.GetString(1))] =
                new PublishedRetentionPolicy(reader.GetInt32(2), reader.GetString(3));
        }

        return result;
    }

    private static MinimumPublishedConfigurationStatus UnavailableStatus()
    {
        var missing = MinimumPublishedConfigurationManifest.Catalogs
            .Select(static item => $"catalog:{item.CatalogCode}/{item.SafeEntryCode}")
            .Concat(MinimumPublishedConfigurationManifest.Parameters.Select(
                static item => $"parameter:{item.ParameterKey}"))
            .Concat(MinimumPublishedConfigurationManifest.RetentionPolicies.Select(
                static item => $"retention:{item.DataClass}/{item.PurposeCode}"))
            .ToArray();

        return new MinimumPublishedConfigurationStatus(
            StorageAvailable: false,
            PublishedCatalogCount: 0,
            PublishedCatalogEntryCount: 0,
            EffectiveParameterCount: 0,
            RetentionPolicyCount: 0,
            MissingItems: missing);
    }

    private static string CatalogEntryKey(string catalogCode, string entryCode) =>
        $"{catalogCode}\u001f{entryCode}";

    private static string RetentionPolicyKey(string dataClass, string purposeCode) =>
        $"{dataClass}\u001f{purposeCode}";

    private sealed record PublishedRetentionPolicy(
        int RetentionDays,
        string TriggerCode);
}
