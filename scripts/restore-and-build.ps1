$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

& "$PSScriptRoot/check-toolchain.ps1"

dotnet tool restore
dotnet restore MusicaAprender.sln

if (-not (Test-Path "$Root/package-lock.json")) {
    Write-Host "Generando package-lock.json por primera vez..."
    npm install --package-lock-only
}

npm ci
npm run typecheck
npm run build
dotnet build MusicaAprender.sln --no-restore

Write-Host "Restauración y compilación reproducibles completadas."
