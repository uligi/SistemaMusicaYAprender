using Npgsql;

namespace MusicaAprender.Modules.Security.Infrastructure.Administration;

public interface IPrivilegedSecurityTransactionExecutor
{
    Task<TResult> ExecuteAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default);
}
