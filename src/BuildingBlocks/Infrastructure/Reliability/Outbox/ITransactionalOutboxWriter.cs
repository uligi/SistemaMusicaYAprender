using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public interface ITransactionalOutboxWriter
{
    Task EnqueueAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        OutboxMessageDraft message,
        CancellationToken cancellationToken = default);
}
