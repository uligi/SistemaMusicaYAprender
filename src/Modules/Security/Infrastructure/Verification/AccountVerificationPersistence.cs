using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Verification;

public sealed record RequiredAccountVerificationConsent(
    string PurposeCode,
    string NoticeVersion);

public enum AccountVerificationConsumeResult
{
    Verified,
    AlreadyVerified,
    Invalid,
    Expired,
    PrerequisitesNotCurrent
}

public static class AccountVerificationPersistence
{
    public static readonly TimeSpan TokenLifetime = TimeSpan.FromMinutes(30);

    public static async Task CreateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid verificationId,
        ReadOnlyMemory<byte> tokenHash,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        if (accountId == Guid.Empty || verificationId == Guid.Empty)
        {
            throw new ArgumentException("Las referencias de verificacion deben ser no vacias.");
        }

        if (tokenHash.Length != 32)
        {
            throw new ArgumentException(
                "El hash del token debe contener 32 bytes.",
                nameof(tokenHash));
        }

        const string sql = """
            INSERT INTO security.account_verification (
                verification_id,
                account_id,
                token_hash,
                expires_at,
                consumed_at,
                created_at
            )
            VALUES (
                @verification_id,
                @account_id,
                @token_hash,
                CURRENT_TIMESTAMP + @lifetime,
                NULL,
                CURRENT_TIMESTAMP
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("verification_id", verificationId);
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue("token_hash", NpgsqlDbType.Bytea, tokenHash.ToArray());
        command.Parameters.AddWithValue("lifetime", NpgsqlDbType.Interval, TokenLifetime);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se pudo crear exactamente un desafio de verificacion.");
        }
    }

    public static async Task<Guid?> ResolvePendingAccountAsync(
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
            "SELECT security.resolve_pending_account_for_verification(@email_lookup_hash);",
            connection,
            transaction);
        command.Parameters.AddWithValue(
            "email_lookup_hash",
            NpgsqlDbType.Bytea,
            emailLookupHash.ToArray());

        var value = await command.ExecuteScalarAsync(cancellationToken);
        return value is Guid accountId ? accountId : null;
    }

    public static async Task<AccountVerificationConsumeResult> ConsumeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        AccountVerificationTokenClaims claims,
        IReadOnlyList<RequiredAccountVerificationConsent> requiredConsents,
        Guid correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(claims);
        ArgumentNullException.ThrowIfNull(requiredConsents);

        if (claims.TokenHash.Length != 32 || requiredConsents.Count == 0)
        {
            throw new ArgumentException("La verificacion no contiene los prerrequisitos esperados.");
        }

        const string selectSql = """
            SELECT
                verification.consumed_at IS NOT NULL AS consumed,
                verification.expires_at <= CURRENT_TIMESTAMP AS expired,
                account.status_code,
                account.verified_at IS NOT NULL AS account_verified
            FROM security.account_verification AS verification
            INNER JOIN security.account AS account
                ON account.account_id = verification.account_id
            WHERE verification.verification_id = @verification_id
              AND verification.account_id = @account_id
              AND verification.token_hash = @token_hash
            FOR UPDATE OF verification, account;
            """;

        bool consumed;
        bool expired;
        string statusCode;
        bool accountVerified;

        await using (var command = new NpgsqlCommand(selectSql, connection, transaction))
        {
            command.Parameters.AddWithValue("verification_id", claims.VerificationId);
            command.Parameters.AddWithValue("account_id", claims.AccountId);
            command.Parameters.AddWithValue(
                "token_hash",
                NpgsqlDbType.Bytea,
                claims.TokenHash.ToArray());

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return AccountVerificationConsumeResult.Invalid;
            }

            consumed = reader.GetBoolean(0);
            expired = reader.GetBoolean(1);
            statusCode = reader.GetString(2);
            accountVerified = reader.GetBoolean(3);
        }

        if (statusCode == "ACTIVE" && accountVerified && consumed)
        {
            return AccountVerificationConsumeResult.AlreadyVerified;
        }

        if (statusCode != "PENDING" || consumed)
        {
            await InsertSecurityEventAsync(
                connection,
                transaction,
                claims.AccountId,
                "INVALID",
                correlationId,
                cancellationToken);
            return AccountVerificationConsumeResult.Invalid;
        }

        if (expired)
        {
            await InsertSecurityEventAsync(
                connection,
                transaction,
                claims.AccountId,
                "EXPIRED",
                correlationId,
                cancellationToken);
            return AccountVerificationConsumeResult.Expired;
        }

        if (!await HasCurrentConsentsAsync(
                connection,
                transaction,
                claims.AccountId,
                requiredConsents,
                cancellationToken))
        {
            await InsertSecurityEventAsync(
                connection,
                transaction,
                claims.AccountId,
                "PREREQUISITE_FAILED",
                correlationId,
                cancellationToken);
            return AccountVerificationConsumeResult.PrerequisitesNotCurrent;
        }

        const string consumeSql = """
            UPDATE security.account_verification
            SET consumed_at = CURRENT_TIMESTAMP
            WHERE account_id = @account_id
              AND consumed_at IS NULL;

            UPDATE security.account
            SET
                status_code = 'ACTIVE',
                verified_at = CURRENT_TIMESTAMP
            WHERE account_id = @account_id
              AND status_code = 'PENDING'
              AND verified_at IS NULL;
            """;

        await using (var command = new NpgsqlCommand(consumeSql, connection, transaction))
        {
            command.Parameters.AddWithValue("account_id", claims.AccountId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await InsertSecurityEventAsync(
            connection,
            transaction,
            claims.AccountId,
            "SUCCEEDED",
            correlationId,
            cancellationToken);

        return AccountVerificationConsumeResult.Verified;
    }

    private static async Task<bool> HasCurrentConsentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        IReadOnlyList<RequiredAccountVerificationConsent> requiredConsents,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT bool_and(
                COALESCE((
                    SELECT consent.decision
                           AND consent.notice_version = required.notice_version
                    FROM identity.consent_record AS consent
                    WHERE consent.account_id = @account_id
                      AND consent.purpose_code = required.purpose_code
                    ORDER BY consent.decided_at DESC, consent.consent_id DESC
                    LIMIT 1
                ), FALSE)
            )
            FROM unnest(@purpose_codes, @notice_versions)
                AS required(purpose_code, notice_version);
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue(
            "purpose_codes",
            NpgsqlDbType.Array | NpgsqlDbType.Varchar,
            requiredConsents.Select(static consent => consent.PurposeCode).ToArray());
        command.Parameters.AddWithValue(
            "notice_versions",
            NpgsqlDbType.Array | NpgsqlDbType.Varchar,
            requiredConsents.Select(static consent => consent.NoticeVersion).ToArray());

        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    private static async Task InsertSecurityEventAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        string resultCode,
        Guid correlationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO security.security_event (
                event_id,
                account_id,
                event_type,
                result_code,
                occurred_at,
                correlation_id,
                client_fingerprint
            )
            VALUES (
                @event_id,
                @account_id,
                'ACCOUNT_VERIFICATION',
                @result_code,
                CURRENT_TIMESTAMP,
                @correlation_id,
                NULL
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("event_id", Guid.CreateVersion7());
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue("result_code", resultCode);
        command.Parameters.AddWithValue("correlation_id", correlationId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
