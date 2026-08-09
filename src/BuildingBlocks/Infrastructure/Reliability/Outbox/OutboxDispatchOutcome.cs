namespace MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;

public enum OutboxDispatchOutcomeKind
{
    None = 0,
    Processed = 1,
    RetryScheduled = 2,
    Review = 3
}

public sealed record OutboxDispatchOutcome(
    OutboxDispatchOutcomeKind Kind,
    Guid? EventId,
    Guid? CorrelationId,
    int AttemptNo,
    int ConsumerCount,
    TimeSpan? RetryDelay,
    DateTime? NextAttemptAt,
    string? ErrorCode)
{
    public static OutboxDispatchOutcome NoWork { get; } =
        new(
            OutboxDispatchOutcomeKind.None,
            null,
            null,
            0,
            0,
            null,
            null,
            null);
}
