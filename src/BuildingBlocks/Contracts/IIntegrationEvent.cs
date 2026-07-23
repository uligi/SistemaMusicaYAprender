namespace MusicaAprender.BuildingBlocks.Contracts;

public interface IIntegrationEvent
{
    Guid EventId { get; }
    DateTimeOffset OccurredAtUtc { get; }
    string EventName { get; }
    int EventVersion { get; }
}
