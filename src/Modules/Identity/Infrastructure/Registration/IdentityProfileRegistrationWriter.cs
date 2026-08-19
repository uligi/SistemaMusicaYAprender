using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Identity.Infrastructure.Registration;

public sealed class UsernameUnavailableException(
    string username,
    Exception innerException)
    : Exception(
        $"El nombre de usuario '{username}' ya está en uso.",
        innerException);

public static class IdentityProfileRegistrationWriter
{
    private const string UsernameUniqueIndex =
        "uq_identity_user_profile_username";

    public static async Task CreateMinimalAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        string username,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        const string sql = """
            INSERT INTO identity.user_profile (
                account_id,
                username,
                display_name,
                ui_language,
                time_zone,
                created_at,
                version
            )
            VALUES (
                @account_id,
                @username,
                NULL,
                'es-CR',
                'America/Costa_Rica',
                CURRENT_TIMESTAMP,
                1
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);
        command.Parameters.AddWithValue(
            "username",
            NpgsqlDbType.Varchar,
            username);

        try
        {
            var changed = await command.ExecuteNonQueryAsync(cancellationToken);
            if (changed != 1)
            {
                throw new InvalidOperationException(
                    "No se pudo crear exactamente un perfil minimo para la cuenta pendiente.");
            }
        }
        catch (PostgresException exception)
            when (
                exception.SqlState == PostgresErrorCodes.UniqueViolation
                && string.Equals(
                    exception.ConstraintName,
                    UsernameUniqueIndex,
                    StringComparison.Ordinal))
        {
            throw new UsernameUnavailableException(
                username,
                exception);
        }
    }
}
