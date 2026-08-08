$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

& "$PSScriptRoot/check-toolchain.ps1"

dotnet tool restore
dotnet restore MusicaAprender.sln

if (-not (Test-Path "$Root/package-lock.json")) {
    Write-Host "Generando package-lock.json por primera vez..."
    npm.cmd install --package-lock-only
}

npm.cmd ci
npm.cmd run typecheck
npm.cmd run format:check
npm.cmd run build

dotnet format MusicaAprender.sln --verify-no-changes --no-restore
dotnet build MusicaAprender.sln --no-restore

Write-Host "Restauración, análisis, formato y compilación completados."
