$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

& "$PSScriptRoot/restore-and-build.ps1"

dotnet run --project tests/ArchitectureTests/MusicaAprender.ArchitectureTests.csproj --no-restore
& "$PSScriptRoot/check-module-boundaries.ps1"

Write-Host "OK: puerta local BL-MVP-003 aprobada."
