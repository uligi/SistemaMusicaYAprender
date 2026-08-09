using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public interface IOutboxConsumer
{
    string ConsumerCode { get; }

    bool CanHandle(string eventName, int schemaVersion);

    Task HandleAsync(
        OutboxEnvelope message,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken);
}
