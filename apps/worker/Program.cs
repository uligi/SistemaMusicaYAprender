using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using MusicaAprender.BuildingBlocks.Contracts.Email;
using MusicaAprender.BuildingBlocks.Infrastructure.Configuration;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.DependencyInjection;
using MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage.DependencyInjection;
using MusicaAprender.BuildingBlocks.Infrastructure.Observability;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.DependencyInjection;
using MusicaAprender.Modules.Security.Infrastructure.Registration;
using MusicaAprender.Modules.Security.Infrastructure.Verification;
using MusicaAprender.Worker.Observability;
using MusicaAprender.Worker.Workers;

var builder = Host.CreateApplicationBuilder(args);

builder.Configuration.AddMusicaAprenderExternalConfiguration();

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

builder.Services.AddMusicaAprenderOutboxDispatch();
builder.Services.AddMusicaAprenderEmailDelivery(builder.Configuration);
builder.Services.AddSingleton(
    PersonalEmailProtector.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton(
    AccountVerificationTokenService.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton<IVersionedEmailTemplate>(services =>
    AccountVerificationEmailTemplate.FromConfiguration(
        builder.Configuration,
        services.GetRequiredService<PersonalEmailProtector>(),
        services.GetRequiredService<AccountVerificationTokenService>()));
builder.Services.AddMusicaAprenderPrivateObjectStore(builder.Configuration);
builder.Services.AddHostedService<HeartbeatWorker>();
builder.Services.AddHostedService<OutboxDispatchWorker>();
builder.Services.AddHostedService<EmailDeliveryWorker>();

var host = builder.Build();
await host.RunAsync();
