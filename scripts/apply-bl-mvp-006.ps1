$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-006: validando infraestructura Docker Compose local..."

& "$PSScriptRoot/local/check-compose.ps1"

npm.cmd exec -- prettier compose.yml infrastructure/containers docs/engineering/local-environment --write --ignore-unknown
Assert-LastExitCode "Formateo de infraestructura"

npm.cmd run format:check
Assert-LastExitCode "Verificacion de formato"

Write-Host ""
Write-Host "OK: BL-MVP-006 configurado."
Write-Host "Siguiente comando: .\scripts\local\start.ps1"
