using Npgsql;

namespace MusicaAprender.Modules.Configuration.Infrastructure.Administration;

public sealed record ConfigurationAuditIntent(
    string ObjectType,
    Guid ObjectId,
    string ActionCode,
    byte[] BeforeDigest,
    byte[] AfterDigest,
    string Reason);

public interface IConfigurationAdministrationTransactionExecutor
{
    Task<TResult> ExecuteAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default);

    Task<TResult> ExecuteAuditedAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<
            NpgsqlConnection,
            NpgsqlTransaction,
            CancellationToken,
            Task<(TResult Result, ConfigurationAuditIntent? Audit)>> operation,
        CancellationToken cancellationToken = default);
}
