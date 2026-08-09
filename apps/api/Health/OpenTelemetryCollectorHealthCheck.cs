using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MusicaAprender.Api.Health;

internal sealed class OpenTelemetryCollectorHealthCheck : IHealthCheck
{
    private readonly IConfiguration _configuration;
    private readonly IHttpClientFactory _httpClientFactory;

    public OpenTelemetryCollectorHealthCheck(
        IConfiguration configuration,
        IHttpClientFactory httpClientFactory)
    {
        _configuration = configuration;
        _httpClientFactory = httpClientFactory;
    }

    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var healthUrl = _configuration["Dependencies:OpenTelemetryHealthUrl"];

        return HttpDependencyProbe.CheckAsync(
            _httpClientFactory,
            healthUrl,
            "OpenTelemetry collector",
            context,
            cancellationToken);
    }
}
