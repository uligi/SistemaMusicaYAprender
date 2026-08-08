using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace MusicaAprender.Worker.Workers;

internal sealed partial class HeartbeatWorker(ILogger<HeartbeatWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        LogWorkerStarted(logger, "BL-MVP-001");

        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
        }
    }

    [LoggerMessage(
        EventId = 1000,
        Level = LogLevel.Information,
        Message = "Worker scaffold started for {BacklogItem}.")]
    private static partial void LogWorkerStarted(ILogger logger, string backlogItem);
}
