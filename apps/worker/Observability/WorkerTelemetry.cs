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
}
