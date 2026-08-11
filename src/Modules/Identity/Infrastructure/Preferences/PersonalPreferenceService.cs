using System.Text.Json;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Identity.Application.Preferences;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Identity.Infrastructure.Preferences;

public sealed record PersonalProfileSummary(
    string? DisplayName,
    string UiLanguage,
    string TimeZone,
    long Version);

public sealed record PersonalPreferenceSnapshot(
    Guid PreferenceSetId,
    long Version,
    int RevisionNo,
    PersonalPreferenceValues Values,
    DateTimeOffset UpdatedAt,
    PersonalProfileSummary Profile);

public sealed class PersonalPreferenceService(
    IRlsTransactionExecutor transactionExecutor)
{
    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);

    public Task<PersonalPreferenceSnapshot> GetAsync(
        DatabaseSessionContext context,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await EnsureInitialAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    token);

                return await ReadCurrentAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    token);
            },
            cancellationToken);
    }

    public Task<PersonalPreferenceSnapshot> UpdateAsync(
        DatabaseSessionContext context,
        PersonalPreferenceDraft draft,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(draft);

        var validation = PersonalPreferencePolicy.Validate(draft);
        if (!validation.IsValid)
        {
            throw new PersonalPreferenceValidationException(validation);
        }

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await EnsureInitialAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    token);

                var current = await ReadCurrentForUpdateAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    token);

                if (current.Version != draft.Version)
                {
                    throw new PersonalPreferenceConcurrencyException(
                        current.Version);
                }

                var languageCatalogVersion =
                    await ResolveSpanishLanguageVersionAsync(
                        connection,
                        transaction,
                        token);
                var normalized =
                    PersonalPreferencePolicy.Normalize(
                        draft,
                        languageCatalogVersion);

                var currentJson = JsonSerializer.Serialize(
                    current.Values,
                    JsonOptions);
                var nextJson = JsonSerializer.Serialize(
                    normalized,
                    JsonOptions);

                if (string.Equals(
                        currentJson,
                        nextJson,
                        StringComparison.Ordinal))
                {
                    return current;
                }

                var revisionId = Guid.CreateVersion7();
                var nextRevisionNo = checked(current.RevisionNo + 1);

                const string insertRevisionSql = """
                    INSERT INTO identity.preference_revision (
                        revision_id,
                        preference_set_id,
                        revision_no,
                        values,
                        created_at,
                        created_by
                    )
                    VALUES (
                        @revision_id,
                        @preference_set_id,
                        @revision_no,
                        @values,
                        CURRENT_TIMESTAMP,
                        @account_id
                    );
                    """;

                await using (var command = new NpgsqlCommand(
                    insertRevisionSql,
                    connection,
                    transaction))
                {
                    command.Parameters.AddWithValue(
                        "revision_id",
                        NpgsqlDbType.Uuid,
                        revisionId);
                    command.Parameters.AddWithValue(
                        "preference_set_id",
                        NpgsqlDbType.Uuid,
                        current.PreferenceSetId);
                    command.Parameters.AddWithValue(
                        "revision_no",
                        NpgsqlDbType.Integer,
                        nextRevisionNo);
                    command.Parameters.AddWithValue(
                        "values",
                        NpgsqlDbType.Jsonb,
                        nextJson);
                    command.Parameters.AddWithValue(
                        "account_id",
                        NpgsqlDbType.Uuid,
                        context.AccountId);

                    if (await command.ExecuteNonQueryAsync(token) != 1)
                    {
                        throw new InvalidOperationException(
                            "No se pudo insertar la nueva revisión de preferencias.");
                    }
                }

                const string updateSetSql = """
                    UPDATE identity.preference_set
                    SET current_revision_id = @revision_id,
                        version = version + 1
                    WHERE preference_set_id = @preference_set_id
                      AND account_id = @account_id
                      AND version = @expected_version;
                    """;

                await using (var command = new NpgsqlCommand(
                    updateSetSql,
                    connection,
                    transaction))
                {
                    command.Parameters.AddWithValue(
                        "revision_id",
                        NpgsqlDbType.Uuid,
                        revisionId);
                    command.Parameters.AddWithValue(
                        "preference_set_id",
                        NpgsqlDbType.Uuid,
                        current.PreferenceSetId);
                    command.Parameters.AddWithValue(
                        "account_id",
                        NpgsqlDbType.Uuid,
                        context.AccountId);
                    command.Parameters.AddWithValue(
                        "expected_version",
                        NpgsqlDbType.Bigint,
                        draft.Version);

                    if (await command.ExecuteNonQueryAsync(token) != 1)
                    {
                        throw new PersonalPreferenceConcurrencyException(
                            current.Version);
                    }
                }

                return await ReadCurrentAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    token);
            },
            cancellationToken);
    }

    public static async Task<bool> TryCreateInitialAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        if (accountId == Guid.Empty)
        {
            throw new ArgumentException(
                "AccountId no puede ser Guid.Empty.",
                nameof(accountId));
        }

        var languageCatalogVersion =
            await ResolveSpanishLanguageVersionAsync(
                connection,
                transaction,
                cancellationToken);
        var defaults =
            PersonalPreferencePolicy.CreateSafeDefaults(
                languageCatalogVersion);
        var valuesJson = JsonSerializer.Serialize(
            defaults,
            JsonOptions);
        var preferenceSetId = Guid.CreateVersion7();
        var revisionId = Guid.CreateVersion7();

        const string insertSetSql = """
            INSERT INTO identity.preference_set (
                preference_set_id,
                account_id,
                current_revision_id,
                version
            )
            VALUES (
                @preference_set_id,
                @account_id,
                @revision_id,
                1
            )
            ON CONFLICT (account_id) DO NOTHING
            RETURNING preference_set_id;
            """;

        await using var insertSet = new NpgsqlCommand(
            insertSetSql,
            connection,
            transaction);
        insertSet.Parameters.AddWithValue(
            "preference_set_id",
            NpgsqlDbType.Uuid,
            preferenceSetId);
        insertSet.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);
        insertSet.Parameters.AddWithValue(
            "revision_id",
            NpgsqlDbType.Uuid,
            revisionId);

        var inserted = await insertSet.ExecuteScalarAsync(
            cancellationToken);

        if (inserted is not Guid)
        {
            return false;
        }

        const string insertRevisionSql = """
            INSERT INTO identity.preference_revision (
                revision_id,
                preference_set_id,
                revision_no,
                values,
                created_at,
                created_by
            )
            VALUES (
                @revision_id,
                @preference_set_id,
                1,
                @values,
                CURRENT_TIMESTAMP,
                @account_id
            );
            """;

        await using var insertRevision = new NpgsqlCommand(
            insertRevisionSql,
            connection,
            transaction);
        insertRevision.Parameters.AddWithValue(
            "revision_id",
            NpgsqlDbType.Uuid,
            revisionId);
        insertRevision.Parameters.AddWithValue(
            "preference_set_id",
            NpgsqlDbType.Uuid,
            preferenceSetId);
        insertRevision.Parameters.AddWithValue(
            "values",
            NpgsqlDbType.Jsonb,
            valuesJson);
        insertRevision.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        if (await insertRevision.ExecuteNonQueryAsync(
                cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se pudo insertar la revisión inicial de preferencias.");
        }

        return true;
    }

    private static async Task EnsureInitialAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        await TryCreateInitialAsync(
            connection,
            transaction,
            accountId,
            cancellationToken);
    }

    private static Task<PersonalPreferenceSnapshot> ReadCurrentAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken) =>
        ReadCurrentCoreAsync(
            connection,
            transaction,
            accountId,
            forUpdate: false,
            cancellationToken);

    private static Task<PersonalPreferenceSnapshot> ReadCurrentForUpdateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken) =>
        ReadCurrentCoreAsync(
            connection,
            transaction,
            accountId,
            forUpdate: true,
            cancellationToken);

    private static async Task<PersonalPreferenceSnapshot> ReadCurrentCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        bool forUpdate,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT
                preference.preference_set_id,
                preference.version,
                revision.revision_no,
                revision.values::text,
                revision.created_at,
                profile.display_name,
                profile.ui_language,
                profile.time_zone,
                profile.version
            FROM identity.preference_set AS preference
            INNER JOIN identity.preference_revision AS revision
                ON revision.revision_id = preference.current_revision_id
            INNER JOIN identity.user_profile AS profile
                ON profile.account_id = preference.account_id
            WHERE preference.account_id = @account_id
            """;

        if (forUpdate)
        {
            sql += " FOR UPDATE OF preference;";
        }
        else
        {
            sql += ";";
        }

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "La cuenta no tiene un conjunto de preferencias legible.");
        }

        var valuesJson = reader.GetString(3);
        var values = JsonSerializer.Deserialize<PersonalPreferenceValues>(
                         valuesJson,
                         JsonOptions)
                     ?? throw new InvalidOperationException(
                         "La revisión de preferencias no cumple el contrato tipado.");

        return new PersonalPreferenceSnapshot(
            reader.GetGuid(0),
            reader.GetInt64(1),
            reader.GetInt32(2),
            values,
            AsUtcOffset(reader.GetDateTime(4)),
            new PersonalProfileSummary(
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.GetString(6),
                reader.GetString(7),
                reader.GetInt64(8)));
    }

    private static DateTimeOffset AsUtcOffset(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static async Task<long> ResolveSpanishLanguageVersionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT entry.version
            FROM configuration.catalog_definition AS definition
            INNER JOIN configuration.catalog_entry AS entry
                ON entry.catalog_definition_id =
                   definition.catalog_definition_id
            WHERE definition.catalog_code = 'LANGUAGE'
              AND definition.status_code = 'ACTIVE'
              AND definition.version > 0
              AND entry.entry_code = 'ES'
              AND entry.status_code = 'ACTIVE'
              AND entry.version > 0
              AND entry.valid_from <= CURRENT_TIMESTAMP
              AND (
                  entry.valid_to IS NULL
                  OR entry.valid_to > CURRENT_TIMESTAMP
              )
              AND entry.labels ? 'es'
            ORDER BY entry.version DESC
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        var result = await command.ExecuteScalarAsync(
            cancellationToken);

        return result switch
        {
            long version when version > 0 => version,
            int version when version > 0 => version,
            _ => throw new InvalidOperationException(
                "LANGUAGE/ES no está publicado como valor seguro vigente.")
        };
    }
}
