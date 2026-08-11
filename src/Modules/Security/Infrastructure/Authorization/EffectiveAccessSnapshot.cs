namespace MusicaAprender.Modules.Security.Infrastructure.Authorization;

public sealed record EffectiveAccessSnapshot(
    IReadOnlyList<string> Roles,
    IReadOnlyList<string> Permissions)
{
    public static EffectiveAccessSnapshot Empty { get; } =
        new(Array.Empty<string>(), Array.Empty<string>());
}
