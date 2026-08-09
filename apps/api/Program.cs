using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using MusicaAprender.Api.Health;
using MusicaAprender.Api.Observability;
using MusicaAprender.Api.Security;
using MusicaAprender.BuildingBlocks.Infrastructure.Configuration;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.DependencyInjection;
using MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage.DependencyInjection;
using MusicaAprender.BuildingBlocks.Infrastructure.Observability;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.DependencyInjection;

var builder = WebApplication.CreateBuilder(args);

builder.Configuration.AddMusicaAprenderExternalConfiguration();

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<IHttpDatabaseSessionContextFactory, HttpDatabaseSessionContextFactory>();
builder.Services.AddSingleton<IRlsTransactionExecutor, RlsTransactionExecutor>();
builder.Services.AddMusicaAprenderReliableOperations();
builder.Services.AddMusicaAprenderEmailQueue();
builder.Services.AddMusicaAprenderPrivateObjectStore(builder.Configuration);

builder.Services.AddMusicaAprenderOpenTelemetry(
    builder.Configuration,
    ApiTelemetry.ServiceName,
    ApiTelemetry.ServiceVersion,
    ApiTelemetry.ActivitySourceName,
    ApiTelemetry.MeterName,
    instrumentAspNetCore: true);

builder.Logging.AddMusicaAprenderOpenTelemetryLogging(
    builder.Configuration,
    ApiTelemetry.ServiceName,
    ApiTelemetry.ServiceVersion);

builder.Services.AddHttpClient(
    HealthConstants.HttpClientName,
    client => client.Timeout = HealthConstants.DependencyTimeout);

builder.Services
    .AddHealthChecks()
    .AddCheck(
        "self",
        () => HealthCheckResult.Healthy("Process is alive."),
        tags: HealthConstants.LiveTags)
    .AddCheck<PostgreSqlHealthCheck>(
        "postgresql",
        failureStatus: HealthStatus.Unhealthy,
        tags: HealthConstants.ReadyDependencyTags)
    .AddCheck<ObjectStoreHealthCheck>(
        "object-store",
        failureStatus: HealthStatus.Degraded,
        tags: HealthConstants.ReadyDependencyTags)
    .AddCheck<SmtpHealthCheck>(
        "smtp",
        failureStatus: HealthStatus.Degraded,
        tags: HealthConstants.ReadyDependencyTags)
    .AddCheck<OpenTelemetryCollectorHealthCheck>(
        "otel-collector",
        failureStatus: HealthStatus.Degraded,
        tags: HealthConstants.ReadyDependencyTags);

var app = builder.Build();

app.UseMiddleware<CorrelationMiddleware>();

using (var startupActivity = ApiTelemetry.ActivitySource.StartActivity("application.start"))
{
    startupActivity?.SetTag("app.operation.version", "v1");
}

app.MapGet("/", () => Results.Ok(new
{
    service = "MusicaAprender.Api",
    status = "scaffold",
    backlogItem = "BL-MVP-009"
}));

app.MapHealthChecks(
    "/health/live",
    HealthEndpointOptions.Create(HealthConstants.LiveTag));

app.MapHealthChecks(
    "/health/ready",
    HealthEndpointOptions.Create(HealthConstants.ReadyTag));

app.MapHealthChecks(
    "/health/dependencies",
    HealthEndpointOptions.Create(HealthConstants.DependencyTag));

app.Run();

public partial class Program;
