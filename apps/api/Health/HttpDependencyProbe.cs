using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MusicaAprender.Api.Health;

internal static class HttpDependencyProbe
{
    public static async Task<HealthCheckResult> CheckAsync(
        IHttpClientFactory httpClientFactory,
        string? healthUrl,
        string displayName,
        HealthCheckContext context,
        CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(healthUrl, UriKind.Absolute, out var uri))
        {
            return Failure(context, $"{displayName} health configuration is missing.");
        }

        try
        {
            using var client = httpClientFactory.CreateClient(HealthConstants.HttpClientName);
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            using var response = await client.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);

            return response.IsSuccessStatusCode
                ? HealthCheckResult.Healthy($"{displayName} is reachable.")
                : Failure(context, $"{displayName} reported an unhealthy status.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Failure(context, $"{displayName} did not answer in time.");
        }
        catch (HttpRequestException)
        {
            return Failure(context, $"{displayName} is unavailable.");
        }
        catch (InvalidOperationException)
        {
            return Failure(context, $"{displayName} health configuration is invalid.");
        }
    }

    private static HealthCheckResult Failure(
        HealthCheckContext context,
        string description)
    {
        return new HealthCheckResult(
            context.Registration.FailureStatus,
            description);
    }
}
