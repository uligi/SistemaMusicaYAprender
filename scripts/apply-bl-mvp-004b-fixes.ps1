$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$testPath = Join-Path $RepoRoot "tests\UnitTests\BuildingBlocks\Domain\Entities\EntityTests.cs"
if (-not (Test-Path $testPath)) {
    throw "No se encontro tests\UnitTests\BuildingBlocks\Domain\Entities\EntityTests.cs."
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$content = @'
using MusicaAprender.BuildingBlocks.Domain;
using Xunit;

namespace MusicaAprender.UnitTests.BuildingBlocks.Domain.Entities;

public sealed class EntityTests
{
    [Fact]
    public void ConstructorPreservesIdentifier()
    {
        var id = Guid.NewGuid();

        var entity = new TestEntity(id);

        Assert.Equal(id, entity.Id);
    }

    private sealed class TestEntity(Guid id) : Entity<Guid>(id);
}
'@

$content = ($content -replace "`r`n", "`n") -replace "`r", "`n"
if (-not $content.EndsWith("`n")) {
    $content += "`n"
}

[System.IO.File]::WriteAllText($testPath, $content, $Utf8NoBom)

Write-Host "Corregido: EntityTests.cs"
Write-Host " - Constructor_PreservesIdentifier -> ConstructorPreservesIdentifier"
Write-Host " - UTF-8 sin BOM"
Write-Host " - finales de linea LF"
Write-Host ""
Write-Host "Ahora ejecute: .\scripts\check-quality.ps1"
