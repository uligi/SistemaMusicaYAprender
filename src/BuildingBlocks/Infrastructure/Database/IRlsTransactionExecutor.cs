using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Database;

public interface IRlsTransactionExecutor
{
    Task ExecuteAsync(
        DatabaseSessionContext context,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task> operation,
        CancellationToken cancellationToken = default);

    Task<TResult> ExecuteAsync<TResult>(
        DatabaseSessionContext context,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default);
}
