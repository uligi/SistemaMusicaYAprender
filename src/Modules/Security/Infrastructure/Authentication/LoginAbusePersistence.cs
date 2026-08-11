using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Authentication;

public sealed record LoginAbuseState(
    bool AccountLimited,
    bool ClientLimited,
    int RetryAfterSeconds)
{
    public bool IsLimited => AccountLimited || ClientLimited;
}

public static class LoginAbusePersistence
{
    private const string AccountFailureEvent = "LOGIN_FAILURE_ACCOUNT";
    private const string ClientFailureEvent = "LOGIN_FAILURE_CLIENT";
    private const string RateLimitedEvent = "LOGIN_RATE_LIMITED";
    private const string SuccessEvent = "LOGIN_SUCCESS";

    public static async Task AcquireAttemptLocksAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ReadOnlyMemory<byte> accountFingerprint,
        ReadOnlyMemory<byte> clientFingerprint,
        CancellationToken cancellationToken = default)
    {
        ValidateFingerprint(accountFingerprint, nameof(accountFingerprint));
        ValidateFingerprint(clientFingerprint, nameof(clientFingerprint));

        var lockKeys = new[]
        {
            ToLockKey(accountFingerprint.Span),
            ToLockKey(clientFingerprint.Span)
        }
        .Distinct()
        .OrderBy(static key => key)
        .ToArray();

        foreach (var lockKey in lockKeys)
        {
            await using var command = new NpgsqlCommand(
                "SELECT pg_advisory_xact_lock(@lock_key);",
                connection,
                transaction);
            command.Parameters.AddWithValue("lock_key", NpgsqlDbType.Bigint, lockKey);
            await command.ExecuteScalarAsync(cancellationToken);
        }
    }

    public static async Task<LoginAbuseState> EvaluateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ReadOnlyMemory<byte> accountFingerprint,
        ReadOnlyMemory<byte> clientFingerprint,
        LoginAbusePolicy policy,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(policy);
        ValidateFingerprint(accountFingerprint, nameof(accountFingerprint));
        ValidateFingerprint(clientFingerprint, nameof(clientFingerprint));

        const string sql = """
            SELECT
                count(*) FILTER (
                    WHERE event_type = 'LOGIN_FAILURE_ACCOUNT'
                      AND client_fingerprint = @account_fingerprint),
                min(occurred_at) FILTER (
                    WHERE event_type = 'LOGIN_FAILURE_ACCOUNT'
                      AND client_fingerprint = @account_fingerprint),
                count(*) FILTER (
                    WHERE event_type = 'LOGIN_FAILURE_CLIENT'
                      AND client_fingerprint = @client_fingerprint),
                min(occurred_at) FILTER (
                    WHERE event_type = 'LOGIN_FAILURE_CLIENT'
                      AND client_fingerprint = @client_fingerprint)
            FROM security.security_event
            WHERE account_id IS NULL
              AND occurred_at >= CURRENT_TIMESTAMP - @window
              AND (
                    (event_type = 'LOGIN_FAILURE_ACCOUNT'
                     AND client_fingerprint = @account_fingerprint)
                 OR (event_type = 'LOGIN_FAILURE_CLIENT'
                     AND client_fingerprint = @client_fingerprint)
              );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "account_fingerprint",
            NpgsqlDbType.Bytea,
            accountFingerprint.ToArray());
        command.Parameters.AddWithValue(
            "client_fingerprint",
            NpgsqlDbType.Bytea,
            clientFingerprint.ToArray());
        command.Parameters.AddWithValue("window", NpgsqlDbType.Interval, policy.Window);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "No se pudo evaluar el estado de limitación de login.");
        }

        var accountFailures = reader.GetInt64(0);
        var accountOldest = reader.IsDBNull(1)
            ? (DateTimeOffset?)null
            : AsUtcOffset(reader.GetDateTime(1));
        var clientFailures = reader.GetInt64(2);
        var clientOldest = reader.IsDBNull(3)
            ? (DateTimeOffset?)null
            : AsUtcOffset(reader.GetDateTime(3));

        var accountLimited = accountFailures >= policy.AccountFailureLimit;
        var clientLimited = clientFailures >= policy.ClientFailureLimit;

        var retryAfter = Math.Max(
            accountLimited
                ? ComputeRetryAfter(accountOldest, policy.Window)
                : 0,
            clientLimited
                ? ComputeRetryAfter(clientOldest, policy.Window)
                : 0);

        return new LoginAbuseState(
            accountLimited,
            clientLimited,
            retryAfter);
    }

    public static Task RecordFailureAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ReadOnlyMemory<byte> accountFingerprint,
        ReadOnlyMemory<byte> clientFingerprint,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateFingerprint(accountFingerprint, nameof(accountFingerprint));
        ValidateFingerprint(clientFingerprint, nameof(clientFingerprint));

        return InsertTwoAnonymousEventsAsync(
            connection,
            transaction,
            AccountFailureEvent,
            accountFingerprint,
            ClientFailureEvent,
            clientFingerprint,
            "REJECTED",
            ResolveCorrelationGuid(correlationId),
            cancellationToken);
    }

    public static async Task RecordRateLimitedAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ReadOnlyMemory<byte> clientFingerprint,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateFingerprint(clientFingerprint, nameof(clientFingerprint));

        await InsertEventAsync(
            connection,
            transaction,
            accountId: null,
            RateLimitedEvent,
            "THROTTLED",
            ResolveCorrelationGuid(correlationId),
            clientFingerprint,
            cancellationToken);
    }

    public static async Task RecordSuccessAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ReadOnlyMemory<byte> accountFingerprint,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateFingerprint(accountFingerprint, nameof(accountFingerprint));

        await InsertEventAsync(
            connection,
            transaction,
            accountId: null,
            SuccessEvent,
            "SUCCESS",
            ResolveCorrelationGuid(correlationId),
            accountFingerprint,
            cancellationToken);
    }

    private static async Task InsertTwoAnonymousEventsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string firstEventType,
        ReadOnlyMemory<byte> firstFingerprint,
        string secondEventType,
        ReadOnlyMemory<byte> secondFingerprint,
        string resultCode,
        Guid correlationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO security.security_event (
                account_id,
                event_type,
                result_code,
                occurred_at,
                correlation_id,
                client_fingerprint
            )
            VALUES
                (NULL, @first_event_type, @result_code, CURRENT_TIMESTAMP, @correlation_id, @first_fingerprint),
                (NULL, @second_event_type, @result_code, CURRENT_TIMESTAMP, @correlation_id, @second_fingerprint);
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("first_event_type", firstEventType);
        command.Parameters.AddWithValue("second_event_type", secondEventType);
        command.Parameters.AddWithValue("result_code", resultCode);
        command.Parameters.AddWithValue("correlation_id", NpgsqlDbType.Uuid, correlationId);
        command.Parameters.AddWithValue(
            "first_fingerprint",
            NpgsqlDbType.Bytea,
            firstFingerprint.ToArray());
        command.Parameters.AddWithValue(
            "second_fingerprint",
            NpgsqlDbType.Bytea,
            secondFingerprint.ToArray());

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 2)
        {
            throw new InvalidOperationException(
                "No se pudieron registrar exactamente dos dimensiones del fallo de login.");
        }
    }

    private static async Task InsertEventAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid? accountId,
        string eventType,
        string resultCode,
        Guid correlationId,
        ReadOnlyMemory<byte> fingerprint,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO security.security_event (
                account_id,
                event_type,
                result_code,
                occurred_at,
                correlation_id,
                client_fingerprint
            )
            VALUES (
                @account_id,
                @event_type,
                @result_code,
                CURRENT_TIMESTAMP,
                @correlation_id,
                @client_fingerprint
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            new NpgsqlParameter("account_id", NpgsqlDbType.Uuid)
            {
                Value = accountId.HasValue ? (object)accountId.Value : DBNull.Value
            });
        command.Parameters.AddWithValue("event_type", eventType);
        command.Parameters.AddWithValue("result_code", resultCode);
        command.Parameters.AddWithValue("correlation_id", NpgsqlDbType.Uuid, correlationId);
        command.Parameters.AddWithValue(
            "client_fingerprint",
            NpgsqlDbType.Bytea,
            fingerprint.ToArray());

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se pudo registrar exactamente un evento de seguridad de login.");
        }
    }

    private static long ToLockKey(ReadOnlySpan<byte> fingerprint) =>
        BinaryPrimitives.ReadInt64BigEndian(fingerprint[..sizeof(long)]);

    private static int ComputeRetryAfter(
        DateTimeOffset? oldestFailure,
        TimeSpan window)
    {
        if (oldestFailure is null)
        {
            return Math.Max(1, (int)Math.Ceiling(window.TotalSeconds));
        }

        var remaining = oldestFailure.Value + window - DateTimeOffset.UtcNow;
        return Math.Max(1, (int)Math.Ceiling(remaining.TotalSeconds));
    }

    private static DateTimeOffset AsUtcOffset(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static Guid ResolveCorrelationGuid(string correlationId)
    {
        if (Guid.TryParse(correlationId, out var parsed))
        {
            return parsed;
        }

        var bytes = Encoding.UTF8.GetBytes(correlationId);
        try
        {
            var hash = SHA256.HashData(bytes);
            return new Guid(hash.AsSpan(0, 16));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
        }
    }

    private static void ValidateFingerprint(
        ReadOnlyMemory<byte> fingerprint,
        string parameterName)
    {
        if (fingerprint.Length != 32)
        {
            throw new ArgumentException(
                "La huella de control de abuso debe contener 32 bytes.",
                parameterName);
        }
    }
}
