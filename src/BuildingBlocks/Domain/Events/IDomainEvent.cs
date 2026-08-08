namespace MusicaAprender.BuildingBlocks.Domain;

public interface IDomainEvent
{
    DateTimeOffset OccurredAtUtc { get; }
}
