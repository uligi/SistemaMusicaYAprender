using System.Security.Cryptography;
using MusicaAprender.Modules.Configuration.Infrastructure.Administration;
using MusicaAprender.Modules.Security.Infrastructure.Audit;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Api.Security;

public sealed class ConfigurationAdministrationTransactionExecutor(
    BackofficeSecurityTransactionExecutor inner) :
    IConfigurationAdministrationTransactionExecutor
{
    public Task<TResult> ExecuteAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default) =>
        inner.ExecuteAsync(
            actorAccountId,
            correlationId,
            operation,
            cancellationToken);

    public Task<TResult> ExecuteAuditedAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<
            NpgsqlConnection,
            NpgsqlTransaction,
            CancellationToken,
            Task<(TResult Result, ConfigurationAuditIntent? Audit)>> operation,
        CancellationToken cancellationToken = default) =>
        inner.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                var (result, audit) =
                    await operation(
                        connection,
                        transaction,
                        token);

                if (audit is null)
                {
                    return result;
                }

                try
                {
                    var roleCode = await ResolveEffectiveRoleAsync(
                        connection,
                        transaction,
                        actorAccountId,
                        token);

                    await PrimaryAuditWriter.WriteAuditEventAsync(
                        connection,
                        transaction,
                        actorAccountId,
                        roleCode,
                        audit.ObjectType,
                        audit.ObjectId,
                        audit.ActionCode,
                        audit.BeforeDigest,
                        audit.AfterDigest,
                        audit.Reason,
                        correlationId,
                        token);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(
                        audit.BeforeDigest);
                    CryptographicOperations.ZeroMemory(
                        audit.AfterDigest);
                }

                return result;
            },
            cancellationToken);

    private static async Task<string> ResolveEffectiveRoleAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT r.role_code
            FROM security.role_assignment a
            JOIN security.role r
              ON r.role_id = a.role_id
            JOIN security.role_permission rp
              ON rp.role_id = r.role_id
            JOIN security.permission p
              ON p.permission_id = rp.permission_id
            WHERE a.account_id = @actor_id
              AND p.permission_code = 'CONFIG.APPROVE'
              AND r.status_code = 'ACTIVE'
              AND a.valid_from <= CURRENT_TIMESTAMP
              AND (a.valid_to IS NULL OR a.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL OR rp.valid_to > CURRENT_TIMESTAMP)
            ORDER BY r.role_code
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(
            "actor_id",
            NpgsqlDbType.Uuid).Value = actorAccountId;

        return await command.ExecuteScalarAsync(cancellationToken)
            as string
            ?? throw new ConfigurationAdministrationException(
                "configuration.authorization.approver-missing",
                "No se pudo resolver una función aprobadora vigente para la auditoría.");
    }
}
