using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Inbox;

public interface IInboxConsumerExecutor
{
    Task<InboxExecutionOutcome> ExecuteAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        OutboxEnvelope message,
        IOutboxConsumer consumer,
        CancellationToken cancellationToken = default);
}
