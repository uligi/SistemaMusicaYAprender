$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-010: integrando bootstrap PostgreSQL de roles y extensiones..."

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

& "$PSScriptRoot/security/check-no-secrets.ps1"

& "$PSScriptRoot/database/apply-bootstrap.ps1"
& "$PSScriptRoot/database/verify-bootstrap.ps1"

npm.cmd run format
Assert-LastExitCode "Formateo"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-010 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Finalmente: .\scripts\database\verify-bootstrap.ps1"
