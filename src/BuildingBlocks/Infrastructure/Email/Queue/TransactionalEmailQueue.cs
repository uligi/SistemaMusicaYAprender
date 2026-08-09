using MusicaAprender.BuildingBlocks.Contracts.Email;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;

public sealed class TransactionalEmailEnqueuer(
    ITransactionalOutboxWriter outboxWriter)
    : ITransactionalEmailEnqueuer
{
    public const string EventName = "email.delivery.requested";
    public const int SchemaVersion = 1;
    private const string AggregateType = "EMAIL_DELIVERY";

    public async Task<EmailQueueReceipt> EnqueueAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        EmailQueueRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(request);

        var deliveryId = Guid.CreateVersion7();
        var eventId = Guid.CreateVersion7();

        var payload = EmailDeliveryPayload.Create(
            deliveryId,
            request);

        var message = OutboxMessageDraft.Create(
            EventName,
            SchemaVersion,
            AggregateType,
            request.AggregateId,
            payload.Serialize(),
            request.CorrelationId,
            request.CausationId,
            eventId);

        await outboxWriter.EnqueueAsync(
            connection,
            transaction,
            message,
            cancellationToken);

        return new EmailQueueReceipt(
            eventId,
            deliveryId);
    }
}
