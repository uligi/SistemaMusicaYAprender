using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace MusicaAprender.Api.Observability;

internal static class ApiTelemetry
{
    public const string ServiceName = "musica-aprender-api";
    public const string ServiceVersion = "0.1.0";
    public const string ActivitySourceName = "MusicaAprender.Api";
    public const string MeterName = "MusicaAprender.Api";

    public static readonly ActivitySource ActivitySource =
        new(ActivitySourceName, ServiceVersion);

    public static readonly Meter Meter =
        new(MeterName, ServiceVersion);

    public static readonly Counter<long> Requests =
        Meter.CreateCounter<long>(
            "musica_aprender.api.requests",
            unit: "{request}",
            description: "Solicitudes procesadas por la API.");

    public static readonly Histogram<double> RequestDuration =
        Meter.CreateHistogram<double>(
            "musica_aprender.api.request.duration",
            unit: "ms",
            description: "Duracion de solicitudes de la API.");
}
