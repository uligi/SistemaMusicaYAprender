using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MusicaAprender.Api.Health;

internal static class HealthEndpointOptions
{
    public static HealthCheckOptions Create(string requiredTag)
    {
        return new HealthCheckOptions
        {
            Predicate = registration => registration.Tags.Contains(requiredTag),
            ResponseWriter = HealthResponseWriter.WriteAsync,
            ResultStatusCodes =
            {
                [HealthStatus.Healthy] = StatusCodes.Status200OK,
                [HealthStatus.Degraded] = StatusCodes.Status200OK,
                [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
            }
        };
    }
}
