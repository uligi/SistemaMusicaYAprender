$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

& "$PSScriptRoot/restore-and-build.ps1"

dotnet test tests/UnitTests/MusicaAprender.UnitTests.csproj --no-build --no-restore
Assert-LastExitCode "Pruebas unitarias"

dotnet run --project tests/ArchitectureTests/MusicaAprender.ArchitectureTests.csproj --no-build --no-restore
Assert-LastExitCode "Pruebas de arquitectura"

& "$PSScriptRoot/check-module-boundaries.ps1"

Write-Host "OK: puerta local BL-MVP-004 aprobada."
