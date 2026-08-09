namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public sealed record OutboxEnvelope(
    Guid EventId,
    string EventName,
    int SchemaVersion,
    string AggregateType,
    Guid AggregateId,
    string PayloadJson,
    DateTime OccurredAt,
    Guid CorrelationId,
    Guid? CausationId);
