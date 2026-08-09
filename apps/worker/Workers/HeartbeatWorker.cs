using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MusicaAprender.Worker.Observability;

namespace MusicaAprender.Worker.Workers;

internal sealed partial class HeartbeatWorker(ILogger<HeartbeatWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        LogWorkerStarted(logger, "BL-MVP-008");

        while (!stoppingToken.IsCancellationRequested)
        {
            EmitHeartbeat();

            await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
        }
    }

    private void EmitHeartbeat()
    {
        var correlationId = $"worker-{Guid.NewGuid():N}";

        using var activity = WorkerTelemetry.ActivitySource.StartActivity("worker.heartbeat");
        activity?.SetTag("app.correlation_id", correlationId);
        activity?.SetTag("app.operation.version", "v1");

        WorkerTelemetry.Heartbeats.Add(
            1,
            new KeyValuePair<string, object?>("operation.version", "v1"));

        using var scope = logger.BeginScope(new Dictionary<string, object?>
        {
            ["correlation_id"] = correlationId,
            ["trace_id"] = activity?.TraceId.ToHexString() ?? string.Empty,
            ["span_id"] = activity?.SpanId.ToHexString() ?? string.Empty,
            ["service"] = WorkerTelemetry.ServiceName,
            ["service_version"] = WorkerTelemetry.ServiceVersion
        });

        LogWorkerHeartbeat(logger, correlationId);
    }

    [LoggerMessage(
        EventId = 1000,
        Level = LogLevel.Information,
        Message = "Worker iniciado para {BacklogItem}.")]
    private static partial void LogWorkerStarted(ILogger logger, string backlogItem);

    [LoggerMessage(
        EventId = 1001,
        Level = LogLevel.Information,
        Message = "Heartbeat del worker emitido. CorrelationId={CorrelationId}.")]
    private static partial void LogWorkerHeartbeat(
        ILogger logger,
        string correlationId);
}
