$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

& "$PSScriptRoot/check-toolchain.ps1"

dotnet tool restore
Assert-LastExitCode "dotnet tool restore"

dotnet restore MusicaAprender.sln
Assert-LastExitCode "dotnet restore"

if (-not (Test-Path "$Root/package-lock.json")) {
    Write-Host "Generando package-lock.json por primera vez..."
    npm.cmd install --package-lock-only
    Assert-LastExitCode "npm install --package-lock-only"
}

npm.cmd ci
Assert-LastExitCode "npm ci"

npm.cmd run typecheck
Assert-LastExitCode "npm run typecheck"

npm.cmd run format:check
Assert-LastExitCode "npm run format:check"

npm.cmd run build
Assert-LastExitCode "npm run build"

dotnet format MusicaAprender.sln --verify-no-changes --no-restore
Assert-LastExitCode "dotnet format --verify-no-changes"

dotnet build MusicaAprender.sln --no-restore
Assert-LastExitCode "dotnet build"

Write-Host "OK: restauracion, analisis, formato y compilacion completados."
