using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Common;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Inbox;

public sealed class InboxConsumerExecutor : IInboxConsumerExecutor
{
    public async Task<InboxExecutionOutcome> ExecuteAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        OutboxEnvelope message,
        IOutboxConsumer consumer,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(message);
        ArgumentNullException.ThrowIfNull(consumer);

        var consumerCode = ReliabilityCode.RequireCode(
            consumer.ConsumerCode,
            nameof(consumer.ConsumerCode));

        const string reserveSql = """
            INSERT INTO ops.inbox_message (
                consumer_code,
                event_id,
                received_at,
                processed_at,
                result_code
            )
            VALUES (
                @consumer_code,
                @event_id,
                CURRENT_TIMESTAMP,
                NULL,
                'PROCESSING'
            )
            ON CONFLICT (consumer_code, event_id) DO NOTHING
            RETURNING 1;
            """;

        await using (var reserveCommand =
                     new NpgsqlCommand(reserveSql, connection, transaction))
        {
            reserveCommand.Parameters.AddWithValue("consumer_code", consumerCode);
            reserveCommand.Parameters.AddWithValue("event_id", message.EventId);

            var reserved = await reserveCommand.ExecuteScalarAsync(cancellationToken);

            if (reserved is null)
            {
                return await ResolveExistingAsync(
                    connection,
                    transaction,
                    consumerCode,
                    message.EventId,
                    cancellationToken);
            }
        }

        await consumer.HandleAsync(
            message,
            connection,
            transaction,
            cancellationToken);

        const string completeSql = """
            UPDATE ops.inbox_message
            SET
                processed_at = CURRENT_TIMESTAMP,
                result_code = 'PROCESSED'
            WHERE
                consumer_code = @consumer_code
                AND event_id = @event_id
                AND result_code = 'PROCESSING';
            """;

        await using var completeCommand =
            new NpgsqlCommand(completeSql, connection, transaction);

        completeCommand.Parameters.AddWithValue("consumer_code", consumerCode);
        completeCommand.Parameters.AddWithValue("event_id", message.EventId);

        var changed = await completeCommand.ExecuteNonQueryAsync(cancellationToken);

        if (changed != 1)
        {
            throw new InvalidOperationException(
                "El inbox reservado no pudo confirmarse exactamente una vez.");
        }

        return new InboxExecutionOutcome(Duplicate: false);
    }

    private static async Task<InboxExecutionOutcome> ResolveExistingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string consumerCode,
        Guid eventId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT result_code
            FROM ops.inbox_message
            WHERE
                consumer_code = @consumer_code
                AND event_id = @event_id
            FOR UPDATE;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("consumer_code", consumerCode);
        command.Parameters.AddWithValue("event_id", eventId);

        var result = await command.ExecuteScalarAsync(cancellationToken);

        if (result is string resultCode
            && string.Equals(
                resultCode,
                "PROCESSED",
                StringComparison.Ordinal))
        {
            return new InboxExecutionOutcome(Duplicate: true);
        }

        throw new InvalidOperationException(
            "Existe una reserva de inbox incompleta que requiere revision.");
    }
}
