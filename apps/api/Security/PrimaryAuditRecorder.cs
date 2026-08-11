using System.Security.Cryptography;
using System.Text;
using MusicaAprender.Modules.Security.Infrastructure.Administration;
using MusicaAprender.Modules.Security.Infrastructure.Audit;
using MusicaAprender.Modules.Security.Infrastructure.Authorization;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Api.Security;

public sealed class PrimaryAuditRecorder(
    IPrivilegedSecurityTransactionExecutor executor)
{
    public Task RecordAuthorizationDecisionAsync(
        Guid accountId,
        string permissionCode,
        AuthorizationScope requiredScope,
        AuthorizationDecision decision,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(requiredScope);
        ArgumentNullException.ThrowIfNull(decision);

        var objectType = requiredScope.Kind switch
        {
            AuthorizationScopeKind.Global => "AUTHORIZATION_GLOBAL",
            AuthorizationScopeKind.Module => "AUTHORIZATION_MODULE",
            AuthorizationScopeKind.Target => "AUTHORIZATION_OBJECT",
            _ => throw new ArgumentOutOfRangeException(nameof(requiredScope))
        };

        var canonicalScope =
            $"{requiredScope.Kind}|{requiredScope.ModuleCode ?? "GLOBAL"}"
            + $"|{requiredScope.ObjectId?.ToString("D") ?? "-"}";
        var objectId = requiredScope.ObjectId
            ?? PrimaryAuditCorrelation.ResolveObjectId(
                $"AUTHORIZATION_SCOPE|{canonicalScope}");
        var resultCode = decision.Allowed ? "ALLOWED" : "DENIED";

        return RecordDecisionAsync(
            accountId,
            permissionCode,
            objectType,
            objectId,
            resultCode,
            decision.ReasonCode,
            canonicalScope,
            correlationId,
            cancellationToken);
    }

    public Task RecordPrivilegedAssuranceDecisionAsync(
        Guid accountId,
        Guid sessionId,
        bool allowed,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (sessionId == Guid.Empty)
        {
            throw new ArgumentException(
                "SessionId no puede ser Guid.Empty.",
                nameof(sessionId));
        }

        return RecordDecisionAsync(
            accountId,
            "SECURITY.PRIVILEGED_ASSURANCE",
            "SECURITY_SESSION",
            sessionId,
            allowed ? "ALLOWED" : "DENIED",
            allowed ? "RECENT_MFA" : "STEP_UP_REQUIRED",
            $"SESSION|{sessionId:D}",
            correlationId,
            cancellationToken);
    }

    private Task<bool> RecordDecisionAsync(
        Guid accountId,
        string actionCode,
        string objectType,
        Guid objectId,
        string resultCode,
        string reasonCode,
        string canonicalObject,
        string correlationId,
        CancellationToken cancellationToken)
    {
        if (accountId == Guid.Empty)
        {
            throw new ArgumentException(
                "AccountId no puede ser Guid.Empty.",
                nameof(accountId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(actionCode);
        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);

        return executor.ExecuteAsync(
            accountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                var roleCode = await ResolveEffectiveRoleAsync(
                    connection,
                    transaction,
                    accountId,
                    token);
                var digest = CreateDecisionDigest(
                    actionCode,
                    canonicalObject,
                    resultCode,
                    reasonCode);

                try
                {
                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "AUTHORIZATION_DECISION",
                        resultCode,
                        correlationId,
                        cancellationToken: token);

                    await PrimaryAuditWriter.WriteAuditEventAsync(
                        connection,
                        transaction,
                        accountId,
                        roleCode,
                        objectType,
                        objectId,
                        actionCode,
                        beforeDigest: null,
                        afterDigest: digest,
                        reason: reasonCode,
                        correlationId: correlationId,
                        cancellationToken: token);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(digest);
                }

                return true;
            },
            cancellationToken);
    }

    private static async Task<string> ResolveEffectiveRoleAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH effective_role AS (
                SELECT role.role_code
                FROM security.role AS role
                WHERE role.role_code = 'STUDENT'
                  AND role.status_code = 'ACTIVE'

                UNION

                SELECT role.role_code
                FROM security.role_assignment AS assignment
                INNER JOIN security.role AS role
                    ON role.role_id = assignment.role_id
                WHERE assignment.account_id = @account_id
                  AND assignment.valid_from <= CURRENT_TIMESTAMP
                  AND (
                      assignment.valid_to IS NULL
                      OR assignment.valid_to > CURRENT_TIMESTAMP
                  )
                  AND role.status_code = 'ACTIVE'
            )
            SELECT role_code
            FROM effective_role
            ORDER BY
                CASE WHEN role_code = 'STUDENT' THEN 1 ELSE 0 END,
                role_code
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        return await command.ExecuteScalarAsync(cancellationToken) as string
            ?? "STUDENT";
    }

    private static byte[] CreateDecisionDigest(
        string actionCode,
        string canonicalObject,
        string resultCode,
        string reasonCode)
    {
        var canonical = Encoding.UTF8.GetBytes(
            $"{actionCode.Trim().ToUpperInvariant()}|"
            + $"{canonicalObject}|"
            + $"{resultCode}|"
            + $"{reasonCode}");

        try
        {
            return SHA256.HashData(canonical);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(canonical);
        }
    }
}
