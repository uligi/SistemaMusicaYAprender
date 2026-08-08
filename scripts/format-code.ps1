$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

& "$PSScriptRoot/check-toolchain.ps1"

dotnet restore MusicaAprender.sln

if (-not (Test-Path "$Root/package-lock.json")) {
    npm.cmd install --package-lock-only
}

npm.cmd ci

dotnet format MusicaAprender.sln --no-restore
npm.cmd run format

Write-Host "Formato aplicado a backend, frontend, documentación y SQL."
