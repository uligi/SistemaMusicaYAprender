using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Delivery;
using MusicaAprender.Worker.Observability;
using Npgsql;

namespace MusicaAprender.Worker.Workers;

internal sealed partial class EmailDeliveryWorker(
    EmailDeliveryJobDispatcher dispatcher,
    ILogger<EmailDeliveryWorker> logger)
    : BackgroundService
{
    private static readonly TimeSpan IdleDelay =
        TimeSpan.FromSeconds(1);

    private static readonly TimeSpan NoTemplateDelay =
        TimeSpan.FromSeconds(5);

    private static readonly TimeSpan InfrastructureFailureDelay =
        TimeSpan.FromSeconds(2);

    protected override async Task ExecuteAsync(
        CancellationToken stoppingToken)
    {
        LogWorkerStarted(logger);

        while (!stoppingToken.IsCancellationRequested)
        {
            if (dispatcher.RegisteredTemplateCount == 0)
            {
                await Task.Delay(
                    NoTemplateDelay,
                    stoppingToken);
                continue;
            }

            try
            {
                var outcome =
                    await dispatcher.DispatchNextAsync(stoppingToken);

                EmitOutcome(outcome);

                if (outcome.Kind
                    == EmailDeliveryJobOutcomeKind.None)
                {
                    await Task.Delay(
                        IdleDelay,
                        stoppingToken);
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

    private void EmitOutcome(
        EmailDeliveryJobOutcome outcome)
    {
        if (outcome.Kind == EmailDeliveryJobOutcomeKind.None
            || outcome.JobId is null)
        {
            return;
        }

        using var activity =
            WorkerTelemetry.ActivitySource.StartActivity(
                "worker.email.delivery");

        activity?.SetTag(
            "app.correlation_id",
            outcome.CorrelationId?.ToString("D"));
        activity?.SetTag(
            "messaging.message.id",
            outcome.JobId.Value.ToString("D"));
        activity?.SetTag(
            "email.template.code",
            outcome.TemplateCode);
        activity?.SetTag(
            "email.template.version",
            outcome.TemplateVersion);
        activity?.SetTag(
            "email.attempt_no",
            outcome.AttemptNo);
        activity?.SetTag(
            "email.result",
            outcome.Kind.ToString());

        switch (outcome.Kind)
        {
            case EmailDeliveryJobOutcomeKind.Succeeded:
                WorkerTelemetry.EmailDelivered.Add(1);
                LogDelivered(
                    logger,
                    outcome.JobId.Value,
                    outcome.AttemptNo,
                    outcome.TemplateCode ?? string.Empty,
                    outcome.TemplateVersion);
                break;

            case EmailDeliveryJobOutcomeKind.RetryScheduled:
                WorkerTelemetry.EmailRetries.Add(1);
                LogRetry(
                    logger,
                    outcome.JobId.Value,
                    outcome.AttemptNo,
                    outcome.ErrorCode ?? "EMAIL_DELIVERY_FAILED");
                break;

            case EmailDeliveryJobOutcomeKind.Review:
                WorkerTelemetry.EmailReview.Add(1);
                LogReview(
                    logger,
                    outcome.JobId.Value,
                    outcome.AttemptNo,
                    outcome.ErrorCode ?? "EMAIL_DELIVERY_FAILED");
                break;
        }
    }

    [LoggerMessage(
        EventId = 1700,
        Level = LogLevel.Information,
        Message = "Worker de correo BL-MVP-017 iniciado.")]
    private static partial void LogWorkerStarted(ILogger logger);

    [LoggerMessage(
        EventId = 1701,
        Level = LogLevel.Information,
        Message = "Correo entregado. JobId={JobId}; Attempt={Attempt}; Template={Template}; Version={Version}.")]
    private static partial void LogDelivered(
        ILogger logger,
        Guid jobId,
        int attempt,
        string template,
        int version);

    [LoggerMessage(
        EventId = 1702,
        Level = LogLevel.Warning,
        Message = "Correo programado para reintento. JobId={JobId}; Attempt={Attempt}; ErrorCode={ErrorCode}.")]
    private static partial void LogRetry(
        ILogger logger,
        Guid jobId,
        int attempt,
        string errorCode);

    [LoggerMessage(
        EventId = 1703,
        Level = LogLevel.Error,
        Message = "Correo requiere revision. JobId={JobId}; Attempt={Attempt}; ErrorCode={ErrorCode}.")]
    private static partial void LogReview(
        ILogger logger,
        Guid jobId,
        int attempt,
        string errorCode);

    [LoggerMessage(
        EventId = 1704,
        Level = LogLevel.Warning,
        Message = "Fallo de infraestructura al sondear correo. ErrorType={ErrorType}.")]
    private static partial void LogInfrastructureFailure(
        ILogger logger,
        string errorType);
}
