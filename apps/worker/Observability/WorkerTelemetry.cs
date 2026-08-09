using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace MusicaAprender.Worker.Observability;

internal static class WorkerTelemetry
{
    public const string ServiceName = "musica-aprender-worker";
    public const string ServiceVersion = "0.1.0";
    public const string ActivitySourceName = "MusicaAprender.Worker";
    public const string MeterName = "MusicaAprender.Worker";

    public static readonly ActivitySource ActivitySource =
        new(ActivitySourceName, ServiceVersion);

    public static readonly Meter Meter =
        new(MeterName, ServiceVersion);

    public static readonly Counter<long> Heartbeats =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.heartbeats",
            unit: "{heartbeat}",
            description: "Latidos emitidos por el worker.");

    public static readonly Counter<long> OutboxProcessed =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.outbox.processed",
            unit: "{event}",
            description: "Eventos de outbox procesados.");

    public static readonly Counter<long> OutboxRetries =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.outbox.retries",
            unit: "{retry}",
            description: "Reintentos de outbox programados.");

    public static readonly Counter<long> OutboxReview =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.outbox.review",
            unit: "{event}",
            description: "Eventos de outbox enviados a revision.");

    public static readonly Counter<long> EmailDelivered =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.email.delivered",
            unit: "{email}",
            description: "Trabajos de correo entregados por SMTP.");

    public static readonly Counter<long> EmailRetries =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.email.retries",
            unit: "{retry}",
            description: "Reintentos de trabajos de correo.");

    public static readonly Counter<long> EmailReview =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.email.review",
            unit: "{email}",
            description: "Trabajos de correo enviados a revision.");
}
