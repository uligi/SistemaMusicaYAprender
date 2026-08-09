using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public sealed class TransactionalOutboxWriter : ITransactionalOutboxWriter
{
    public async Task EnqueueAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        OutboxMessageDraft message,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(message);

        const string sql = """
            INSERT INTO ops.outbox_message (
                event_id,
                event_name,
                schema_version,
                aggregate_type,
                aggregate_id,
                payload,
                occurred_at,
                correlation_id,
                causation_id,
                status_code,
                next_attempt_at
            )
            VALUES (
                @event_id,
                @event_name,
                @schema_version,
                @aggregate_type,
                @aggregate_id,
                @payload,
                CURRENT_TIMESTAMP,
                @correlation_id,
                @causation_id,
                'PENDING',
                NULL
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("event_id", message.EventId);
        command.Parameters.AddWithValue("event_name", message.EventName);
        command.Parameters.AddWithValue("schema_version", message.SchemaVersion);
        command.Parameters.AddWithValue("aggregate_type", message.AggregateType);
        command.Parameters.AddWithValue("aggregate_id", message.AggregateId);
        command.Parameters.AddWithValue("payload", NpgsqlDbType.Jsonb, message.PayloadJson);
        command.Parameters.AddWithValue("correlation_id", message.CorrelationId);
        command.Parameters.AddWithValue(
            "causation_id",
            NpgsqlDbType.Uuid,
            message.CausationId is null
                ? DBNull.Value
                : message.CausationId.Value);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
