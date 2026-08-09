using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using MusicaAprender.BuildingBlocks.Infrastructure.Observability;
using MusicaAprender.Worker.Observability;
using MusicaAprender.Worker.Workers;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddMusicaAprenderOpenTelemetry(
    builder.Configuration,
    WorkerTelemetry.ServiceName,
    WorkerTelemetry.ServiceVersion,
    WorkerTelemetry.ActivitySourceName,
    WorkerTelemetry.MeterName,
    instrumentAspNetCore: false);

builder.Logging.AddMusicaAprenderOpenTelemetryLogging(
    builder.Configuration,
    WorkerTelemetry.ServiceName,
    WorkerTelemetry.ServiceVersion);

builder.Services.AddHostedService<HeartbeatWorker>();

var host = builder.Build();
await host.RunAsync();
