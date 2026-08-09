using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;

public sealed class EmailJobProjectionConsumer : IOutboxConsumer
{
    public const string JobType = "EMAIL_DELIVERY";
    public const string Consumer = "EMAIL_JOB_PROJECTOR";

    public string ConsumerCode => Consumer;

    public bool CanHandle(string eventName, int schemaVersion)
    {
        return string.Equals(
                   eventName,
                   TransactionalEmailEnqueuer.EventName,
                   StringComparison.Ordinal)
               && schemaVersion == TransactionalEmailEnqueuer.SchemaVersion;
    }

    public async Task HandleAsync(
        OutboxEnvelope message,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(message);
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        EmailDeliveryPayload payload;

        try
        {
            payload = EmailDeliveryPayload.Parse(message.PayloadJson);
        }
        catch (InvalidOperationException)
        {
            throw new OutboxConsumerException("EMAIL_PAYLOAD_INVALID");
        }

        if (payload.AggregateId != message.AggregateId)
        {
            throw new OutboxConsumerException("EMAIL_AGGREGATE_MISMATCH");
        }

        const string sql = """
            INSERT INTO ops.background_job (
                job_id,
                job_type,
                owner_module,
                payload,
                status_code,
                scheduled_at,
                next_attempt_at,
                attempt_count,
                correlation_id
            )
            VALUES (
                @job_id,
                @job_type,
                @owner_module,
                @payload,
                'PENDING',
                CURRENT_TIMESTAMP,
                NULL,
                0,
                @correlation_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);

        command.Parameters.AddWithValue(
            "job_id",
            payload.DeliveryId);
        command.Parameters.AddWithValue(
            "job_type",
            JobType);
        command.Parameters.AddWithValue(
            "owner_module",
            payload.OwnerModule);
        command.Parameters.AddWithValue(
            "payload",
            NpgsqlDbType.Jsonb,
            payload.Serialize());
        command.Parameters.AddWithValue(
            "correlation_id",
            message.CorrelationId);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
