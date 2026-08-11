using System.Security.Cryptography;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Security.Infrastructure.Audit;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Authentication;

public static class SecuritySessionPolicy
{
    public const string AssuranceLevel = "PASSWORD";
    public const string SafeRoleCode = "STUDENT";
    public const string AnonymousRoleCode = "ANONYMOUS";
    public static readonly TimeSpan IdleLifetime = TimeSpan.FromHours(12);
    public static readonly TimeSpan AbsoluteLifetime = TimeSpan.FromDays(30);
}

public sealed record ActiveSecuritySession(
    Guid SessionId,
    Guid AccountId,
    string AssuranceLevel,
    DateTimeOffset CreatedAt,
    DateTimeOffset IdleExpiresAt,
    DateTimeOffset AbsoluteExpiresAt);

public sealed class SecuritySessionPersistence(IRlsTransactionExecutor transactionExecutor)
{
    public Task CreateAsync(
        Guid accountId,
        ReadOnlyMemory<byte> sessionHash,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateHash(sessionHash);

        var context = DatabaseSessionContext.Create(
            accountId,
            SecuritySessionPolicy.SafeRoleCode,
            correlationId);

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                const string sql = """
                    INSERT INTO security.session (
                        session_id,
                        account_id,
                        session_hash,
                        assurance_level,
                        created_at,
                        idle_expires_at,
                        absolute_expires_at,
                        revoked_at
                    )
                    VALUES (
                        @session_id,
                        @account_id,
                        @session_hash,
                        @assurance_level,
                        CURRENT_TIMESTAMP,
                        CURRENT_TIMESTAMP + @idle_lifetime,
                        CURRENT_TIMESTAMP + @absolute_lifetime,
                        NULL
                    );
                    """;

                await using var command = new NpgsqlCommand(sql, connection, transaction);
                command.Parameters.AddWithValue("session_id", Guid.CreateVersion7());
                command.Parameters.AddWithValue("account_id", accountId);
                command.Parameters.AddWithValue(
                    "session_hash",
                    NpgsqlDbType.Bytea,
                    sessionHash.ToArray());
                command.Parameters.AddWithValue(
                    "assurance_level",
                    SecuritySessionPolicy.AssuranceLevel);
                command.Parameters.AddWithValue(
                    "idle_lifetime",
                    NpgsqlDbType.Interval,
                    SecuritySessionPolicy.IdleLifetime);
                command.Parameters.AddWithValue(
                    "absolute_lifetime",
                    NpgsqlDbType.Interval,
                    SecuritySessionPolicy.AbsoluteLifetime);

                if (await command.ExecuteNonQueryAsync(token) != 1)
                {
                    throw new InvalidOperationException(
                        "No se pudo crear exactamente una sesion de seguridad.");
                }

                await PrimaryAuditWriter.WriteSecurityEventAsync(
                    connection,
                    transaction,
                    accountId,
                    "SESSION_CREATED",
                    "SUCCEEDED",
                    correlationId,
                    cancellationToken: token);
            },
            cancellationToken);
    }

    public Task<ActiveSecuritySession?> ResolveAsync(
        ReadOnlyMemory<byte> sessionHash,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateHash(sessionHash);

        var provisionalContext = DatabaseSessionContext.Create(
            Guid.CreateVersion7(),
            SecuritySessionPolicy.AnonymousRoleCode,
            correlationId);

        return transactionExecutor.ExecuteAsync(
            provisionalContext,
            (connection, transaction, token) => ResolveAsync(
                connection,
                transaction,
                sessionHash,
                token),
            cancellationToken);
    }

    public Task RevokeAsync(
        ReadOnlyMemory<byte> sessionHash,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateHash(sessionHash);

        var provisionalContext = DatabaseSessionContext.Create(
            Guid.CreateVersion7(),
            SecuritySessionPolicy.AnonymousRoleCode,
            correlationId);

        return transactionExecutor.ExecuteAsync(
            provisionalContext,
            async (connection, transaction, token) =>
            {
                await using var command = new NpgsqlCommand(
                    "SELECT security.revoke_active_session(@session_hash);",
                    connection,
                    transaction);
                command.Parameters.AddWithValue(
                    "session_hash",
                    NpgsqlDbType.Bytea,
                    sessionHash.ToArray());

                var revoked =
                    await command.ExecuteScalarAsync(token) is true;

                if (revoked)
                {
                    var fingerprint =
                        SHA256.HashData(sessionHash.Span);

                    try
                    {
                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            accountId: null,
                            eventType: "SESSION_REVOKED",
                            resultCode: "SUCCEEDED",
                            correlationId: correlationId,
                            clientFingerprint: fingerprint,
                            cancellationToken: token);
                    }
                    finally
                    {
                        CryptographicOperations.ZeroMemory(fingerprint);
                    }
                }
            },
            cancellationToken);
    }

    private static async Task<ActiveSecuritySession?> ResolveAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ReadOnlyMemory<byte> sessionHash,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT
                session_id,
                account_id,
                assurance_level,
                created_at,
                idle_expires_at,
                absolute_expires_at
            FROM security.resolve_active_session(@session_hash);
            """,
            connection,
            transaction);
        command.Parameters.AddWithValue(
            "session_hash",
            NpgsqlDbType.Bytea,
            sessionHash.ToArray());

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new ActiveSecuritySession(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            AsUtcOffset(reader.GetDateTime(3)),
            AsUtcOffset(reader.GetDateTime(4)),
            AsUtcOffset(reader.GetDateTime(5)));
    }

    private static DateTimeOffset AsUtcOffset(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static void ValidateHash(ReadOnlyMemory<byte> sessionHash)
    {
        if (sessionHash.Length != 32)
        {
            throw new ArgumentException(
                "El hash de sesion debe contener 32 bytes.",
                nameof(sessionHash));
        }
    }
}
