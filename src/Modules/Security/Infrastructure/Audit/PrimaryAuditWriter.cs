using System.Security.Cryptography;
using System.Text;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Audit;

public static class PrimaryAuditCorrelation
{
    public static Guid Resolve(string correlationId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);

        var normalized = correlationId.Trim();
        if (Guid.TryParse(normalized, out var parsed) && parsed != Guid.Empty)
        {
            return parsed;
        }

        return ResolveObjectId($"CORRELATION|{normalized}");
    }

    public static Guid ResolveObjectId(string canonicalObject)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(canonicalObject);

        var bytes = Encoding.UTF8.GetBytes(canonicalObject.Trim());
        var digest = SHA256.HashData(bytes);

        try
        {
            return new Guid(digest.AsSpan(0, 16));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
            CryptographicOperations.ZeroMemory(digest);
        }
    }
}

public static class PrimaryAuditWriter
{
    public static async Task WriteSecurityEventAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid? accountId,
        string eventType,
        string resultCode,
        string correlationId,
        ReadOnlyMemory<byte>? clientFingerprint = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        var normalizedEventType = NormalizeCode(eventType, nameof(eventType));
        var normalizedResultCode = NormalizeCode(resultCode, nameof(resultCode));
        var correlationGuid = PrimaryAuditCorrelation.Resolve(correlationId);

        if (accountId == Guid.Empty)
        {
            throw new ArgumentException(
                "AccountId debe ser nulo o un UUID no vacío.",
                nameof(accountId));
        }

        if (clientFingerprint.HasValue
            && clientFingerprint.Value.Length != 32)
        {
            throw new ArgumentException(
                "ClientFingerprint debe contener exactamente 32 bytes.",
                nameof(clientFingerprint));
        }

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
                @event_type,
                @result_code,
                CURRENT_TIMESTAMP,
                @correlation_id,
                @client_fingerprint
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("event_id", Guid.CreateVersion7());
        command.Parameters.Add(NullableUuid("account_id", accountId));
        command.Parameters.AddWithValue(
            "event_type",
            NpgsqlDbType.Varchar,
            normalizedEventType);
        command.Parameters.AddWithValue(
            "result_code",
            NpgsqlDbType.Varchar,
            normalizedResultCode);
        command.Parameters.AddWithValue(
            "correlation_id",
            NpgsqlDbType.Uuid,
            correlationGuid);
        command.Parameters.Add(
            NullableBytes(
                "client_fingerprint",
                clientFingerprint?.ToArray()));

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se insertó exactamente un security_event.");
        }
    }

    public static async Task WriteAuditEventAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid? actorId,
        string roleCode,
        string objectType,
        Guid objectId,
        string actionCode,
        ReadOnlyMemory<byte>? beforeDigest,
        ReadOnlyMemory<byte>? afterDigest,
        string? reason,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        if (actorId == Guid.Empty)
        {
            throw new ArgumentException(
                "ActorId debe ser nulo o un UUID no vacío.",
                nameof(actorId));
        }

        if (objectId == Guid.Empty)
        {
            throw new ArgumentException(
                "ObjectId no puede ser Guid.Empty.",
                nameof(objectId));
        }

        ValidateDigest(beforeDigest, nameof(beforeDigest));
        ValidateDigest(afterDigest, nameof(afterDigest));

        var normalizedRole = NormalizeCode(roleCode, nameof(roleCode));
        var normalizedObjectType = NormalizeCode(objectType, nameof(objectType));
        var normalizedAction = NormalizeCode(actionCode, nameof(actionCode));
        var normalizedReason = NormalizeReason(reason);
        var correlationGuid = PrimaryAuditCorrelation.Resolve(correlationId);

        const string sql = """
            INSERT INTO security.audit_event (
                audit_id,
                actor_id,
                role_code,
                object_type,
                object_id,
                action_code,
                before_digest,
                after_digest,
                reason,
                occurred_at,
                correlation_id
            )
            VALUES (
                @audit_id,
                @actor_id,
                @role_code,
                @object_type,
                @object_id,
                @action_code,
                @before_digest,
                @after_digest,
                @reason,
                CURRENT_TIMESTAMP,
                @correlation_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("audit_id", Guid.CreateVersion7());
        command.Parameters.Add(NullableUuid("actor_id", actorId));
        command.Parameters.AddWithValue("role_code", NpgsqlDbType.Varchar, normalizedRole);
        command.Parameters.AddWithValue("object_type", NpgsqlDbType.Varchar, normalizedObjectType);
        command.Parameters.AddWithValue("object_id", NpgsqlDbType.Uuid, objectId);
        command.Parameters.AddWithValue("action_code", NpgsqlDbType.Varchar, normalizedAction);
        command.Parameters.Add(NullableBytes("before_digest", beforeDigest?.ToArray()));
        command.Parameters.Add(NullableBytes("after_digest", afterDigest?.ToArray()));
        command.Parameters.Add(
            new NpgsqlParameter("reason", NpgsqlDbType.Text)
            {
                Value = normalizedReason is null
                    ? DBNull.Value
                    : normalizedReason
            });
        command.Parameters.AddWithValue(
            "correlation_id",
            NpgsqlDbType.Uuid,
            correlationGuid);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se insertó exactamente un audit_event.");
        }
    }

    private static string NormalizeCode(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length is < 1 or > 64
            || !IsUpperAsciiLetterOrDigit(normalized[0]))
        {
            throw new ArgumentException(
                "El código no cumple el formato seguro esperado.",
                parameterName);
        }

        for (var index = 1; index < normalized.Length; index++)
        {
            var character = normalized[index];
            if (!(IsUpperAsciiLetterOrDigit(character)
                  || character is '.' or '_' or '-'))
            {
                throw new ArgumentException(
                    "El código no cumple el formato seguro esperado.",
                    parameterName);
            }
        }

        return normalized;
    }

    private static string? NormalizeReason(string? reason)
    {
        if (reason is null)
        {
            return null;
        }

        var normalized = reason.Trim();
        if (normalized.Length == 0)
        {
            return null;
        }

        if (normalized.Length > 512)
        {
            throw new ArgumentException(
                "Reason excede 512 caracteres.",
                nameof(reason));
        }

        return normalized;
    }

    private static void ValidateDigest(
        ReadOnlyMemory<byte>? digest,
        string parameterName)
    {
        if (digest.HasValue && digest.Value.Length is < 16 or > 128)
        {
            throw new ArgumentException(
                "El digest debe contener entre 16 y 128 bytes.",
                parameterName);
        }
    }

    private static NpgsqlParameter NullableUuid(
        string name,
        Guid? value) =>
        new(name, NpgsqlDbType.Uuid)
        {
            Value = value.HasValue
                ? (object)value.Value
                : DBNull.Value
        };

    private static NpgsqlParameter NullableBytes(
        string name,
        byte[]? value) =>
        new(name, NpgsqlDbType.Bytea)
        {
            Value = value is null
                ? DBNull.Value
                : value
        };

    private static bool IsUpperAsciiLetterOrDigit(char character) =>
        character is >= 'A' and <= 'Z'
        || char.IsAsciiDigit(character);
}
