using Npgsql;

namespace MusicaAprender.Modules.Identity.Infrastructure.Registration;

public static class IdentityProfileRegistrationWriter
{
    public static async Task CreateMinimalAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        const string sql = """
            INSERT INTO identity.user_profile (
                account_id,
                display_name,
                ui_language,
                time_zone,
                created_at,
                version
            )
            VALUES (
                @account_id,
                NULL,
                'es-CR',
                'America/Costa_Rica',
                CURRENT_TIMESTAMP,
                1
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);

        var changed = await command.ExecuteNonQueryAsync(cancellationToken);
        if (changed != 1)
        {
            throw new InvalidOperationException(
                "No se pudo crear exactamente un perfil minimo para la cuenta pendiente.");
        }
    }
}
