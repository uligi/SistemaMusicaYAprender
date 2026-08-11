using Microsoft.Extensions.Configuration;

namespace MusicaAprender.Modules.Security.Infrastructure.Authentication;

public sealed record LoginAbusePolicy(
    int AccountFailureLimit,
    int ClientFailureLimit,
    TimeSpan Window,
    bool TrustClientAddressHeader)
{
    public const int DefaultAccountFailureLimit = 5;
    public const int DefaultClientFailureLimit = 20;
    public const int DefaultWindowSeconds = 15 * 60;

    public static LoginAbusePolicy FromConfiguration(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        return new LoginAbusePolicy(
            ReadInt(
                configuration["Security:LoginAbuse:AccountFailureLimit"],
                DefaultAccountFailureLimit,
                minimum: 1,
                maximum: 100,
                configurationKey: "Security:LoginAbuse:AccountFailureLimit"),
            ReadInt(
                configuration["Security:LoginAbuse:ClientFailureLimit"],
                DefaultClientFailureLimit,
                minimum: 1,
                maximum: 1000,
                configurationKey: "Security:LoginAbuse:ClientFailureLimit"),
            TimeSpan.FromSeconds(
                ReadInt(
                    configuration["Security:LoginAbuse:WindowSeconds"],
                    DefaultWindowSeconds,
                    minimum: 1,
                    maximum: 3600,
                    configurationKey: "Security:LoginAbuse:WindowSeconds")),
            ReadBoolean(
                configuration["Security:LoginAbuse:TrustClientAddressHeader"],
                defaultValue: false,
                configurationKey: "Security:LoginAbuse:TrustClientAddressHeader"));
    }

    private static int ReadInt(
        string? value,
        int defaultValue,
        int minimum,
        int maximum,
        string configurationKey)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultValue;
        }

        if (!int.TryParse(value, out var parsed) || parsed < minimum || parsed > maximum)
        {
            throw new InvalidOperationException(
                $"{configurationKey} debe estar entre {minimum} y {maximum}.");
        }

        return parsed;
    }

    private static bool ReadBoolean(
        string? value,
        bool defaultValue,
        string configurationKey)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultValue;
        }

        if (!bool.TryParse(value, out var parsed))
        {
            throw new InvalidOperationException(
                $"{configurationKey} debe ser true o false.");
        }

        return parsed;
    }
}
