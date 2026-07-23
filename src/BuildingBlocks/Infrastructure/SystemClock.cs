using MusicaAprender.BuildingBlocks.Application;

namespace MusicaAprender.BuildingBlocks.Infrastructure;

public sealed class SystemClock : IClock
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}
