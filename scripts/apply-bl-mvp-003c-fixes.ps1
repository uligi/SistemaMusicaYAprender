$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Test-Path ".\MusicaAprender.sln")) {
    throw "Ejecute este script dentro del repositorio SistemaMusicaYAprender."
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8Lf([string]$Path, [string]$Content) {
    $normalized = $Content -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"

    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }

    [System.IO.File]::WriteAllText($Path, $normalized, $Utf8NoBom)
}

$workerPath = Join-Path $RepoRoot "apps\worker\Workers\HeartbeatWorker.cs"
$workerContent = @'
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
'@

$entityPath = Join-Path $RepoRoot "src\BuildingBlocks\Domain\Entities\Entity.cs"
$entityContent = @'
namespace MusicaAprender.BuildingBlocks.Domain;

public abstract class Entity<TId>
    where TId : notnull
{
    protected Entity(TId id)
    {
        Id = id;
    }

    public TId Id { get; }
}
'@

Write-Utf8Lf $workerPath $workerContent
Write-Utf8Lf $entityPath $entityContent

Write-Host "Corregido: HeartbeatWorker.cs (UTF-8 sin BOM, LF y LoggerMessage)"
Write-Host "Corregido: Entity.cs (UTF-8 sin BOM y LF)"
Write-Host ""
Write-Host "OK: correccion BL-MVP-003C aplicada."
Write-Host "Ahora ejecute: .\scripts\check-quality.ps1"
