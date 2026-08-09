using System.Diagnostics;

namespace MusicaAprender.Api.Observability;

internal sealed partial class CorrelationMiddleware
{
    public const string HeaderName = "X-Correlation-Id";

    private readonly RequestDelegate _next;
    private readonly ILogger<CorrelationMiddleware> _logger;

    public CorrelationMiddleware(
        RequestDelegate next,
        ILogger<CorrelationMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = ResolveCorrelationId(context);
        var activity = Activity.Current;

        activity?.SetTag("app.correlation_id", correlationId);
        activity?.SetTag("app.operation.version", "v1");

        context.TraceIdentifier = correlationId;
        context.Response.Headers[HeaderName] = correlationId;

        var started = Stopwatch.GetTimestamp();

        using var scope = _logger.BeginScope(new Dictionary<string, object?>
        {
            ["correlation_id"] = correlationId,
            ["trace_id"] = activity?.TraceId.ToHexString() ?? string.Empty,
            ["span_id"] = activity?.SpanId.ToHexString() ?? string.Empty,
            ["service"] = ApiTelemetry.ServiceName,
            ["service_version"] = ApiTelemetry.ServiceVersion
        });

        ApiTelemetry.Requests.Add(
            1,
            new KeyValuePair<string, object?>(
                "http.request.method",
                context.Request.Method));

        try
        {
            await _next(context);

            LogRequestCompleted(
                _logger,
                context.Request.Method,
                context.Request.Path.Value ?? "/",
                context.Response.StatusCode,
                correlationId);
        }
        catch (Exception)
        {
            LogRequestFailed(
                _logger,
                context.Request.Method,
                context.Request.Path.Value ?? "/",
                correlationId);

            throw;
        }
        finally
        {
            ApiTelemetry.RequestDuration.Record(
                Stopwatch.GetElapsedTime(started).TotalMilliseconds,
                new KeyValuePair<string, object?>(
                    "http.request.method",
                    context.Request.Method));
        }
    }

    private static string ResolveCorrelationId(HttpContext context)
    {
        if (context.Request.Headers.TryGetValue(HeaderName, out var values))
        {
            var candidate = values.ToString();

            if (IsSafeCorrelationId(candidate))
            {
                return candidate;
            }
        }

        return Activity.Current?.TraceId.ToHexString()
            ?? Guid.NewGuid().ToString("N");
    }

    private static bool IsSafeCorrelationId(string value)
    {
        if (value.Length is < 8 or > 64)
        {
            return false;
        }

        return value.All(static character =>
            char.IsAsciiLetterOrDigit(character)
            || character is '-' or '_');
    }

    [LoggerMessage(
        EventId = 1100,
        Level = LogLevel.Information,
        Message = "HTTP {Method} {Path} termino con {StatusCode}. CorrelationId={CorrelationId}.")]
    private static partial void LogRequestCompleted(
        ILogger logger,
        string method,
        string path,
        int statusCode,
        string correlationId);

    [LoggerMessage(
        EventId = 1101,
        Level = LogLevel.Error,
        Message = "HTTP {Method} {Path} fallo. CorrelationId={CorrelationId}.")]
    private static partial void LogRequestFailed(
        ILogger logger,
        string method,
        string path,
        string correlationId);
}
