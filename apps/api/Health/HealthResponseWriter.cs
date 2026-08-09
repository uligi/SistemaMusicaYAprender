using System.Text.Json;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MusicaAprender.Api.Health;

internal static class HealthResponseWriter
{
    public static Task WriteAsync(HttpContext context, HealthReport report)
    {
        context.Response.ContentType = "application/json; charset=utf-8";
        context.Response.Headers.CacheControl = "no-store";

        var payload = new
        {
            status = report.Status.ToString(),
            totalDurationMs = ToMilliseconds(report.TotalDuration),
            checks = report.Entries
                .OrderBy(static entry => entry.Key, StringComparer.Ordinal)
                .Select(static entry => new
                {
                    name = entry.Key,
                    status = entry.Value.Status.ToString(),
                    durationMs = ToMilliseconds(entry.Value.Duration),
                    description = entry.Value.Description
                })
        };

        return JsonSerializer.SerializeAsync(
            context.Response.Body,
            payload,
            cancellationToken: context.RequestAborted);
    }

    private static long ToMilliseconds(TimeSpan duration)
    {
        return (long)Math.Round(duration.TotalMilliseconds, MidpointRounding.AwayFromZero);
    }
}
