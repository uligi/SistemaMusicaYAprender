using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using MusicaAprender.Worker.Observability;
using Npgsql;

namespace MusicaAprender.Worker.Workers;

internal sealed partial class OutboxDispatchWorker(
    OutboxDispatcher dispatcher,
    ILogger<OutboxDispatchWorker> logger)
    : BackgroundService
{
    private static readonly TimeSpan IdleDelay = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan NoConsumerDelay = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan InfrastructureFailureDelay = TimeSpan.FromSeconds(2);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        LogOutboxWorkerStarted(logger);

        while (!stoppingToken.IsCancellationRequested)
        {
            if (dispatcher.RegisteredConsumerCount == 0)
            {
                await Task.Delay(NoConsumerDelay, stoppingToken);
                continue;
            }

            try
            {
                var outcome =
                    await dispatcher.DispatchNextAsync(stoppingToken);

                EmitOutcome(outcome);

                if (outcome.Kind == OutboxDispatchOutcomeKind.None)
                {
                    await Task.Delay(IdleDelay, stoppingToken);
                }
            }
            catch (NpgsqlException exception)
            {
                LogInfrastructureFailure(
                    logger,
                    exception.GetType().Name);

                await Task.Delay(
                    InfrastructureFailureDelay,
                    stoppingToken);
            }
            catch (TimeoutException exception)
            {
                LogInfrastructureFailure(
                    logger,
                    exception.GetType().Name);

                await Task.Delay(
                    InfrastructureFailureDelay,
                    stoppingToken);
            }
        }
    }

    private void EmitOutcome(OutboxDispatchOutcome outcome)
    {
        if (outcome.Kind == OutboxDispatchOutcomeKind.None
            || outcome.EventId is null)
        {
            return;
        }

        using var activity =
            WorkerTelemetry.ActivitySource.StartActivity(
                "worker.outbox.dispatch");

        activity?.SetTag(
            "app.correlation_id",
            outcome.CorrelationId?.ToString("D"));
        activity?.SetTag(
            "messaging.message.id",
            outcome.EventId.Value.ToString("D"));
        activity?.SetTag(
            "messaging.operation.type",
            "process");
        activity?.SetTag(
            "outbox.attempt_no",
            outcome.AttemptNo);
        activity?.SetTag(
            "outbox.result",
            outcome.Kind.ToString());

        using var scope = logger.BeginScope(
            new Dictionary<string, object?>
            {
                ["correlation_id"] =
                    outcome.CorrelationId?.ToString("D") ?? string.Empty,
                ["event_id"] =
                    outcome.EventId.Value.ToString("D"),
                ["attempt_no"] = outcome.AttemptNo,
                ["result"] = outcome.Kind.ToString()
            });

        switch (outcome.Kind)
        {
            case OutboxDispatchOutcomeKind.Processed:
                WorkerTelemetry.OutboxProcessed.Add(1);
                LogProcessed(
                    logger,
                    outcome.EventId.Value,
                    outcome.AttemptNo,
                    outcome.ConsumerCount);
                break;

            case OutboxDispatchOutcomeKind.RetryScheduled:
                WorkerTelemetry.OutboxRetries.Add(1);
                LogRetry(
                    logger,
                    outcome.EventId.Value,
                    outcome.AttemptNo,
                    outcome.ErrorCode ?? "UNEXPECTED_ERROR");
                break;

            case OutboxDispatchOutcomeKind.Review:
                WorkerTelemetry.OutboxReview.Add(1);
                LogReview(
                    logger,
                    outcome.EventId.Value,
                    outcome.AttemptNo,
                    outcome.ErrorCode ?? "UNEXPECTED_ERROR");
                break;
        }
    }

    [LoggerMessage(
        EventId = 1500,
        Level = LogLevel.Information,
        Message = "Worker de outbox BL-MVP-015 iniciado.")]
    private static partial void LogOutboxWorkerStarted(ILogger logger);

    [LoggerMessage(
        EventId = 1501,
        Level = LogLevel.Information,
        Message = "Outbox procesado. EventId={EventId}; Attempt={Attempt}; Consumers={Consumers}.")]
    private static partial void LogProcessed(
        ILogger logger,
        Guid eventId,
        int attempt,
        int consumers);

    [LoggerMessage(
        EventId = 1502,
        Level = LogLevel.Warning,
        Message = "Outbox programado para reintento. EventId={EventId}; Attempt={Attempt}; ErrorCode={ErrorCode}.")]
    private static partial void LogRetry(
        ILogger logger,
        Guid eventId,
        int attempt,
        string errorCode);

    [LoggerMessage(
        EventId = 1503,
        Level = LogLevel.Error,
        Message = "Outbox requiere revision. EventId={EventId}; Attempt={Attempt}; ErrorCode={ErrorCode}.")]
    private static partial void LogReview(
        ILogger logger,
        Guid eventId,
        int attempt,
        string errorCode);

    [LoggerMessage(
        EventId = 1504,
        Level = LogLevel.Warning,
        Message = "Fallo de infraestructura al sondear outbox. ErrorType={ErrorType}.")]
    private static partial void LogInfrastructureFailure(
        ILogger logger,
        string errorType);
}
