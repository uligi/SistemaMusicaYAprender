using MusicaAprender.Modules.Security.Infrastructure.Credentials;
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
        PasswordCredential credential,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(email);
        ArgumentNullException.ThrowIfNull(credential);

        const string sql = """
            WITH created_account AS (
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
                RETURNING account_id
            )
            INSERT INTO security.credential (
                credential_id,
                account_id,
                hash,
                algorithm,
                parameters,
                changed_at,
                active
            )
            SELECT
                @credential_id,
                account_id,
                @credential_hash,
                @credential_algorithm,
                @credential_parameters,
                CURRENT_TIMESTAMP,
                TRUE
            FROM created_account
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
        command.Parameters.AddWithValue("credential_id", Guid.CreateVersion7());
        command.Parameters.AddWithValue("credential_hash", credential.Hash);
        command.Parameters.AddWithValue("credential_algorithm", credential.Algorithm);
        command.Parameters.AddWithValue("credential_parameters", credential.Parameters);

        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is Guid createdAccountId && createdAccountId == accountId;
    }
}
