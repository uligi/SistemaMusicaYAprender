using Npgsql;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Administration;

public interface IArtistAdministrationTransactionExecutor
{
    Task<TResult> ExecuteAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default);
}
