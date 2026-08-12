using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MusicaAprender.Modules.Catalog.Infrastructure.Search;
using MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;
using Npgsql;

namespace MusicaAprender.Worker.Workers;

internal sealed partial class PublicCatalogProjectionWorker(
    PublicCatalogProjectionService projectionService,
    PublicCatalogSearchService searchService,
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
            var projection =
                await projectionService.RebuildAsync(cancellationToken);
            LogProjectionRebuilt(
                logger,
                projection.EligiblePublications,
                projection.InsertedOrUpdated,
                projection.Removed);

            var search =
                await searchService.RebuildIndexAsync(cancellationToken);
            LogSearchIndexRebuilt(
                logger,
                search.EligibleDocuments,
                search.InsertedOrUpdated,
                search.Removed);
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
    private static partial void LogProjectionRebuilt(
        ILogger logger,
        long eligible,
        long changed,
        long removed);

    [LoggerMessage(
        EventId = 4201,
        Level = LogLevel.Information,
        Message = "BL-MVP-042 public catalog search index rebuilt. Eligible={Eligible} Changed={Changed} Removed={Removed}")]
    private static partial void LogSearchIndexRebuilt(
        ILogger logger,
        long eligible,
        long changed,
        long removed);

    [LoggerMessage(
        EventId = 4102,
        Level = LogLevel.Error,
        Message = "Public catalog projection/search refresh failed with {ErrorType}; the last confirmed projections are preserved.")]
    private static partial void LogInfrastructureFailure(
        ILogger logger,
        string errorType);
}
