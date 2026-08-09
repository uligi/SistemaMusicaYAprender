using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Observability;

public static class ObservabilityExtensions
{
    private const string DefaultOtlpEndpoint = "http://localhost:4317";

    public static IServiceCollection AddMusicaAprenderOpenTelemetry(
        this IServiceCollection services,
        IConfiguration configuration,
        string serviceName,
        string serviceVersion,
        string activitySourceName,
        string meterName,
        bool instrumentAspNetCore)
    {
        var endpoint = ResolveOtlpEndpoint(configuration);

        services
            .AddOpenTelemetry()
            .ConfigureResource(resource => resource.AddService(
                serviceName: serviceName,
                serviceVersion: serviceVersion))
            .WithTracing(tracing =>
            {
                tracing
                    .AddSource(activitySourceName)
                    .AddHttpClientInstrumentation(options => options.RecordException = true)
                    .AddOtlpExporter(options => options.Endpoint = endpoint);

                if (instrumentAspNetCore)
                {
                    tracing.AddAspNetCoreInstrumentation(options => options.RecordException = true);
                }
            })
            .WithMetrics(metrics =>
            {
                metrics
                    .AddMeter(meterName)
                    .AddRuntimeInstrumentation()
                    .AddOtlpExporter(options => options.Endpoint = endpoint);

                if (instrumentAspNetCore)
                {
                    metrics.AddAspNetCoreInstrumentation();
                }
            });

        return services;
    }

    public static ILoggingBuilder AddMusicaAprenderOpenTelemetryLogging(
        this ILoggingBuilder logging,
        IConfiguration configuration,
        string serviceName,
        string serviceVersion)
    {
        var endpoint = ResolveOtlpEndpoint(configuration);

        logging.AddOpenTelemetry(options =>
        {
            options.IncludeFormattedMessage = true;
            options.IncludeScopes = true;
            options.ParseStateValues = true;
            options.SetResourceBuilder(
                ResourceBuilder.CreateDefault()
                    .AddService(
                        serviceName: serviceName,
                        serviceVersion: serviceVersion));
            options.AddOtlpExporter(exporter => exporter.Endpoint = endpoint);
        });

        return logging;
    }

    private static Uri ResolveOtlpEndpoint(IConfiguration configuration)
    {
        var configured =
            configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]
            ?? configuration["OpenTelemetry:OtlpEndpoint"]
            ?? DefaultOtlpEndpoint;

        if (!Uri.TryCreate(configured, UriKind.Absolute, out var endpoint))
        {
            throw new InvalidOperationException(
                "OTEL_EXPORTER_OTLP_ENDPOINT debe ser una URI absoluta.");
        }

        return endpoint;
    }
}
