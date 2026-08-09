$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-008: instalando y fijando dependencias OpenTelemetry..."

npm.cmd install `
    --workspace @musica-aprender/web `
    --save-exact `
    @opentelemetry/api@1.9.1 `
    @opentelemetry/api-logs@0.221.0 `
    @opentelemetry/resources@2.10.0 `
    @opentelemetry/sdk-trace-web@2.10.0 `
    @opentelemetry/sdk-metrics@2.10.0 `
    @opentelemetry/sdk-logs@0.221.0 `
    @opentelemetry/exporter-trace-otlp-http@0.221.0 `
    @opentelemetry/exporter-metrics-otlp-http@0.221.0 `
    @opentelemetry/exporter-logs-otlp-http@0.221.0
Assert-LastExitCode "Instalacion OpenTelemetry del cliente"

Write-Host "Actualizando lockfiles .NET..."
dotnet restore MusicaAprender.sln --force-evaluate
Assert-LastExitCode "Restauracion y actualizacion de lockfiles .NET"

docker compose config --quiet
Assert-LastExitCode "Validacion de Docker Compose"

npm.cmd run format
Assert-LastExitCode "Formateo"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-008 compila y supera la puerta local."
Write-Host "Ahora ejecute: .\scripts\local\start.ps1"
Write-Host "Luego: .\scripts\local\verify-running.ps1"
Write-Host "Y finalmente: .\scripts\local\verify-telemetry.ps1"
