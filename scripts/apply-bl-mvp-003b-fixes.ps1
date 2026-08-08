$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Test-Path ".\MusicaAprender.sln")) {
    throw "Ejecute este script dentro del repositorio SistemaMusicaYAprender."
}

Write-Host "BL-MVP-003B: limpiando archivos trasladados por la reorganizacion..."

$obsoleteFiles = @(
    "src\BuildingBlocks\Application\IClock.cs",
    "src\BuildingBlocks\Contracts\IIntegrationEvent.cs",
    "src\BuildingBlocks\Domain\Entity.cs",
    "src\BuildingBlocks\Domain\IDomainEvent.cs",
    "src\BuildingBlocks\Infrastructure\SystemClock.cs",

    "src\Modules\Catalog\ModuleMarker.cs",
    "src\Modules\Configuration\ModuleMarker.cs",
    "src\Modules\Content\ModuleMarker.cs",
    "src\Modules\Editorial\ModuleMarker.cs",
    "src\Modules\Identity\ModuleMarker.cs",
    "src\Modules\Learning\ModuleMarker.cs",
    "src\Modules\Progress\ModuleMarker.cs",
    "src\Modules\Security\ModuleMarker.cs",

    "tests\IntegrationTests\IntegrationTestProjectMarker.cs",
    "tests\UnitTests\UnitTestProjectMarker.cs"
)

foreach ($relativePath in $obsoleteFiles) {
    $fullPath = Join-Path $RepoRoot $relativePath
    if (Test-Path $fullPath) {
        Remove-Item $fullPath -Force
        Write-Host "Eliminado: $relativePath"
    }
}

$workerPath = Join-Path $RepoRoot "apps\worker\Workers\HeartbeatWorker.cs"
$workerContent = @'
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace MusicaAprender.Worker.Workers;

internal sealed class HeartbeatWorker(ILogger<HeartbeatWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Worker scaffold started for {BacklogItem}.", "BL-MVP-001");

        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
        }
    }
}
'@
Set-Content -Path $workerPath -Value $workerContent -Encoding utf8
Write-Host "Corregido: apps\worker\Workers\HeartbeatWorker.cs"

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
Set-Content -Path $entityPath -Value $entityContent -Encoding utf8
Write-Host "Normalizado: src\BuildingBlocks\Domain\Entities\Entity.cs"

$prettierIgnore = Join-Path $RepoRoot ".prettierignore"
$masterSqlPattern = "**/MVP_PostgreSQL_18_Master.sql"

if (Test-Path $prettierIgnore) {
    $lines = Get-Content $prettierIgnore
    if (-not ($lines -contains $masterSqlPattern)) {
        Add-Content -Path $prettierIgnore -Value $masterSqlPattern
        Write-Host "Agregada exclusion del SQL maestro a .prettierignore"
    }
}

Write-Host ""
Write-Host "OK: correccion BL-MVP-003B aplicada."
Write-Host "Ahora ejecute: .\scripts\check-quality.ps1"
