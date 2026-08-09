namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Delivery;

public enum EmailDeliveryJobOutcomeKind
{
    None = 0,
    Succeeded = 1,
    RetryScheduled = 2,
    Review = 3
}

public sealed record EmailDeliveryJobOutcome(
    EmailDeliveryJobOutcomeKind Kind,
    Guid? JobId = null,
    Guid? CorrelationId = null,
    int AttemptNo = 0,
    string? TemplateCode = null,
    int TemplateVersion = 0,
    string? ErrorCode = null)
{
    public static EmailDeliveryJobOutcome NoWork { get; } =
        new(EmailDeliveryJobOutcomeKind.None);
}
