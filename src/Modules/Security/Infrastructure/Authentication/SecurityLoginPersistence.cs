using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Authentication;

public static class SecurityLoginPersistence
{
    public static async Task<ActivePasswordCredential?> ResolveActiveCredentialAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ReadOnlyMemory<byte> emailLookupHash,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        if (emailLookupHash.Length != 32)
        {
            throw new ArgumentException(
                "El hash de busqueda de correo debe contener 32 bytes.",
                nameof(emailLookupHash));
        }

        await using var command = new NpgsqlCommand(
            """
            SELECT
                account_id,
                credential_hash,
                credential_algorithm,
                credential_parameters
            FROM security.resolve_active_password_credential(@email_lookup_hash);
            """,
            connection,
            transaction);
        command.Parameters.AddWithValue(
            "email_lookup_hash",
            NpgsqlDbType.Bytea,
            emailLookupHash.ToArray());

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new ActivePasswordCredential(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3));
    }
}
