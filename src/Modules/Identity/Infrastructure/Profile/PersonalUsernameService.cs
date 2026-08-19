using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Identity.Application.Profile;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Identity.Infrastructure.Profile;

public sealed record PersonalUsernameSnapshot(
    string? Username,
    bool CanClaim);

public sealed class PersonalUsernameException(
    string code,
    string message,
    int statusCode = 400) : Exception(message)
{
    public string Code { get; } = code;
    public int StatusCode { get; } = statusCode;
}

public sealed class PersonalUsernameService(
    IRlsTransactionExecutor transactionExecutor)
{
    private const string UniqueIndexName =
        "uq_identity_user_profile_username";

    public Task<PersonalUsernameSnapshot> GetAsync(
        DatabaseSessionContext context,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
                await ReadAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    forUpdate: false,
                    token),
            cancellationToken);
    }

    public Task<PersonalUsernameSnapshot> ClaimAsync(
        DatabaseSessionContext context,
        string? requestedUsername,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        var validation = UsernamePolicy.Validate(requestedUsername);
        if (!validation.IsValid
            || validation.NormalizedUsername is null)
        {
            throw new PersonalUsernameException(
                "identity.username.invalid",
                ValidationMessage(validation.Error),
                400);
        }

        var normalized = validation.NormalizedUsername;

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                var current = await ReadAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    forUpdate: true,
                    token);

                if (string.Equals(
                        current.Username,
                        normalized,
                        StringComparison.Ordinal))
                {
                    return current;
                }

                if (current.Username is not null)
                {
                    throw new PersonalUsernameException(
                        "identity.username.immutable",
                        "El nombre de usuario ya fue fijado para esta cuenta y no se cambia desde preferencias.",
                        409);
                }

                const string sql = """
                    UPDATE identity.user_profile
                    SET username = @username
                    WHERE account_id = @account_id
                      AND username IS NULL
                    RETURNING username;
                    """;

                try
                {
                    await using var command =
                        new NpgsqlCommand(sql, connection, transaction);
                    command.Parameters.AddWithValue(
                        "username",
                        NpgsqlDbType.Varchar,
                        normalized);
                    command.Parameters.AddWithValue(
                        "account_id",
                        NpgsqlDbType.Uuid,
                        context.AccountId);

                    var stored =
                        (string?)(await command.ExecuteScalarAsync(token));

                    if (!string.Equals(
                            stored,
                            normalized,
                            StringComparison.Ordinal))
                    {
                        throw new PersonalUsernameException(
                            "identity.username.concurrent",
                            "El perfil cambió mientras fijabas el nombre de usuario. Recarga antes de continuar.",
                            409);
                    }
                }
                catch (PostgresException exception)
                    when (
                        exception.SqlState
                            == PostgresErrorCodes.UniqueViolation
                        && string.Equals(
                            exception.ConstraintName,
                            UniqueIndexName,
                            StringComparison.Ordinal))
                {
                    throw new PersonalUsernameException(
                        "identity.username.unavailable",
                        "Ese nombre de usuario ya está en uso. Elige otro.",
                        409);
                }

                return new PersonalUsernameSnapshot(
                    normalized,
                    CanClaim: false);
            },
            cancellationToken);
    }

    private static async Task<PersonalUsernameSnapshot> ReadAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        bool forUpdate,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT username
            FROM identity.user_profile
            WHERE account_id = @account_id
            """;

        sql += forUpdate ? " FOR UPDATE;" : ";";

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "La cuenta autenticada no tiene perfil de producto.");
        }

        var username =
            reader.IsDBNull(0) ? null : reader.GetString(0);

        return new PersonalUsernameSnapshot(
            username,
            CanClaim: username is null);
    }

    private static string ValidationMessage(
        UsernameValidationError error) =>
        error switch
        {
            UsernameValidationError.Required =>
                "Escribe un nombre de usuario.",
            UsernameValidationError.Length =>
                "Usa entre 3 y 32 caracteres.",
            UsernameValidationError.Reserved =>
                "Ese nombre está reservado por el sistema. Elige otro.",
            _ =>
                "Usa letras a-z, números, punto, guion o guion bajo; empieza y termina con letra o número."
        };
}
