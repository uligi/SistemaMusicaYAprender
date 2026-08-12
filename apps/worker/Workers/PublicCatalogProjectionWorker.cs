using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;
using Npgsql;

namespace MusicaAprender.Worker.Workers;

internal sealed partial class PublicCatalogProjectionWorker(
    PublicCatalogProjectionService projectionService,
    ILogger<PublicCatalogProjectionWorker> logger) : BackgroundService
{
    private static readonly TimeSpan RefreshInterval = TimeSpan.FromSeconds(15);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await RefreshAsync(stoppingToken);

        using var timer = new PeriodicTimer(RefreshInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            await RefreshAsync(stoppingToken);
        }
    }

    private async Task RefreshAsync(CancellationToken cancellationToken)
    {
        try
        {
            var result = await projectionService.RebuildAsync(cancellationToken);
            LogRebuilt(
                logger,
                result.EligiblePublications,
                result.InsertedOrUpdated,
                result.Removed);
        }
        catch (NpgsqlException exception)
        {
            LogInfrastructureFailure(logger, exception.GetType().Name);
        }
        catch (TimeoutException exception)
        {
            LogInfrastructureFailure(logger, exception.GetType().Name);
        }
    }

    [LoggerMessage(
        EventId = 4101,
        Level = LogLevel.Information,
        Message = "BL-MVP-041 public catalog projection rebuilt. Eligible={Eligible} Changed={Changed} Removed={Removed}")]
    private static partial void LogRebuilt(
        ILogger logger,
        long eligible,
        long changed,
        long removed);

    [LoggerMessage(
        EventId = 4102,
        Level = LogLevel.Error,
        Message = "BL-MVP-041 public catalog projection rebuild failed with {ErrorType}; the last confirmed projection is preserved.")]
    private static partial void LogInfrastructureFailure(
        ILogger logger,
        string errorType);
}
