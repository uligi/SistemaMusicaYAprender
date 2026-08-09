namespace MusicaAprender.Api.Health;

internal static class HealthConstants
{
    public const string HttpClientName = "dependency-health";
    public const string LiveTag = "live";
    public const string ReadyTag = "ready";
    public const string DependencyTag = "dependency";

    public static readonly TimeSpan DependencyTimeout = TimeSpan.FromSeconds(2);

    public static readonly string[] LiveTags = [LiveTag];

    public static readonly string[] ReadyDependencyTags = [ReadyTag, DependencyTag];
}
