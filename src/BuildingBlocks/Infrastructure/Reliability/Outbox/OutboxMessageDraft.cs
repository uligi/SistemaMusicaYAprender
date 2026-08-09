using System.Text.Json;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Common;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public sealed class OutboxMessageDraft
{
    private OutboxMessageDraft(
        Guid eventId,
        string eventName,
        int schemaVersion,
        string aggregateType,
        Guid aggregateId,
        string payloadJson,
        Guid correlationId,
        Guid? causationId)
    {
        EventId = eventId;
        EventName = eventName;
        SchemaVersion = schemaVersion;
        AggregateType = aggregateType;
        AggregateId = aggregateId;
        PayloadJson = payloadJson;
        CorrelationId = correlationId;
        CausationId = causationId;
    }

    public Guid EventId { get; }

    public string EventName { get; }

    public int SchemaVersion { get; }

    public string AggregateType { get; }

    public Guid AggregateId { get; }

    public string PayloadJson { get; }

    public Guid CorrelationId { get; }

    public Guid? CausationId { get; }

    public static OutboxMessageDraft Create(
        string eventName,
        int schemaVersion,
        string aggregateType,
        Guid aggregateId,
        string payloadJson,
        Guid correlationId,
        Guid? causationId = null,
        Guid? eventId = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventName);
        ArgumentException.ThrowIfNullOrWhiteSpace(payloadJson);

        var normalizedEventName = eventName.Trim();

        if (normalizedEventName.Length > 256)
        {
            throw new ArgumentException(
                "EventName no puede exceder 256 caracteres.",
                nameof(eventName));
        }

        if (schemaVersion <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(schemaVersion),
                "SchemaVersion debe ser mayor que cero.");
        }

        if (aggregateId == Guid.Empty)
        {
            throw new ArgumentException(
                "AggregateId no puede ser Guid.Empty.",
                nameof(aggregateId));
        }

        if (correlationId == Guid.Empty)
        {
            throw new ArgumentException(
                "CorrelationId no puede ser Guid.Empty.",
                nameof(correlationId));
        }

        var resolvedEventId = eventId ?? Guid.CreateVersion7();

        if (resolvedEventId == Guid.Empty)
        {
            throw new ArgumentException(
                "EventId no puede ser Guid.Empty.",
                nameof(eventId));
        }

        using var payload = JsonDocument.Parse(payloadJson);

        if (payload.RootElement.ValueKind != JsonValueKind.Object)
        {
            throw new ArgumentException(
                "PayloadJson debe representar un objeto JSON.",
                nameof(payloadJson));
        }

        return new OutboxMessageDraft(
            resolvedEventId,
            normalizedEventName,
            schemaVersion,
            ReliabilityCode.RequireCode(aggregateType, nameof(aggregateType)),
            aggregateId,
            payload.RootElement.GetRawText(),
            correlationId,
            causationId);
    }
}
