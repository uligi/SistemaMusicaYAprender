$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$Target = Join-Path $RepoRoot "src\BuildingBlocks\Infrastructure\Configuration\ExternalConfigurationExtensions.cs"

if (-not (Test-Path $Target)) {
    throw "No se encontro ExternalConfigurationExtensions.cs."
}

$content = [System.IO.File]::ReadAllText($Target)

if ($content -notmatch 'RequireNonSecret\(\s*ConfigurationManager configuration,') {
    throw "La correccion CA1859 no esta presente en ExternalConfigurationExtensions.cs."
}

Write-Host "BL-MVP-009B: firma RequireNonSecret corregida a ConfigurationManager."

dotnet build MusicaAprender.sln --no-restore
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build fallo con codigo de salida $LASTEXITCODE."
}

Write-Host ""
Write-Host "OK: BL-MVP-009B compila."
Write-Host "Ahora vuelva a ejecutar: .\scripts\apply-bl-mvp-009.ps1"
