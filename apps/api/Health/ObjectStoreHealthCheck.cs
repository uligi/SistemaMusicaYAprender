using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MusicaAprender.Api.Health;

internal sealed class ObjectStoreHealthCheck : IHealthCheck
{
    private readonly IConfiguration _configuration;
    private readonly IHttpClientFactory _httpClientFactory;

    public ObjectStoreHealthCheck(
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
        var healthUrl = _configuration["Dependencies:ObjectStoreHealthUrl"];

        return HttpDependencyProbe.CheckAsync(
            _httpClientFactory,
            healthUrl,
            "Object store",
            context,
            cancellationToken);
    }
}
