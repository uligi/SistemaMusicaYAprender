$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-007: preparando health checks de liveness, readiness y dependencias..."

dotnet restore MusicaAprender.sln
Assert-LastExitCode "Restauracion .NET"

docker compose config --quiet
Assert-LastExitCode "Validacion de Docker Compose"

npm.cmd run format
Assert-LastExitCode "Formateo"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-007 compila y supera la puerta local."
Write-Host "Ahora reconstruya el entorno con: .\scripts\local\start.ps1"
Write-Host "Despues ejecute: .\scripts\local\verify-running.ps1"
Write-Host "Y finalmente: .\scripts\local\verify-health-degradation.ps1"
