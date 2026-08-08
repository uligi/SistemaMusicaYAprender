$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

& "$PSScriptRoot/check-toolchain.ps1"

dotnet restore MusicaAprender.sln
Assert-LastExitCode "dotnet restore"

if (-not (Test-Path "$Root/package-lock.json")) {
    npm.cmd install --package-lock-only
    Assert-LastExitCode "npm install --package-lock-only"
}

npm.cmd ci
Assert-LastExitCode "npm ci"

dotnet format MusicaAprender.sln --no-restore
Assert-LastExitCode "dotnet format"

npm.cmd run format
Assert-LastExitCode "npm run format"

Write-Host "OK: formato aplicado a backend, frontend, documentacion y SQL."
