using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;

public interface IReliableOperationExecutor
{
    Task<ReliableOperationOutcome> ExecuteAsync(
        DatabaseSessionContext context,
        ReliableOperationRequest request,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<ReliableOperationResult>>
            operation,
        CancellationToken cancellationToken = default);
}
