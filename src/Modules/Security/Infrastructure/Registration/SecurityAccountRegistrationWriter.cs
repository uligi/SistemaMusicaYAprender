using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Registration;

public static class SecurityAccountRegistrationWriter
{
    public static async Task<bool> TryCreatePendingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        ProtectedEmail email,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(email);

        const string sql = """
            INSERT INTO security.account (
                account_id,
                email_lookup_hash,
                email_cipher,
                status_code,
                verified_at,
                created_at,
                version
            )
            VALUES (
                @account_id,
                @email_lookup_hash,
                @email_cipher,
                'PENDING',
                NULL,
                CURRENT_TIMESTAMP,
                1
            )
            ON CONFLICT (email_lookup_hash)
            DO NOTHING
            RETURNING account_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue(
            "email_lookup_hash",
            NpgsqlDbType.Bytea,
            email.LookupHash.ToArray());
        command.Parameters.AddWithValue(
            "email_cipher",
            NpgsqlDbType.Bytea,
            email.Ciphertext.ToArray());

        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is Guid createdAccountId && createdAccountId == accountId;
    }
}
