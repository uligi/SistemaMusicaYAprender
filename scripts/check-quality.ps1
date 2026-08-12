$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

& "$PSScriptRoot/security/check-no-secrets.ps1"
& "$PSScriptRoot/restore-and-build.ps1"

node scripts/frontend/verify-design-tokens.mjs
Assert-LastExitCode "Verificador BL-MVP-018"

node scripts/frontend/verify-accessible-components.mjs
Assert-LastExitCode "Verificador BL-MVP-019"

node scripts/frontend/verify-app-shell.mjs
Assert-LastExitCode "Verificador BL-MVP-020"

node scripts/frontend/verify-http-client.mjs
Assert-LastExitCode "Verificador BL-MVP-021"

node scripts/frontend/verify-e2e-harness.mjs
Assert-LastExitCode "Verificador BL-MVP-022"

npm.cmd run typecheck:e2e
Assert-LastExitCode "TypeScript E2E"

npm.cmd run test:e2e
Assert-LastExitCode "Playwright E2E"
dotnet test tests/UnitTests/MusicaAprender.UnitTests.csproj --no-build --no-restore
Assert-LastExitCode "Pruebas unitarias"

dotnet run --project tests/ArchitectureTests/MusicaAprender.ArchitectureTests.csproj --no-build --no-restore
Assert-LastExitCode "Pruebas de arquitectura"

& "$PSScriptRoot/check-module-boundaries.ps1"
& "$PSScriptRoot/governance/check-templates.ps1"

Write-Host "OK: puerta local de calidad aprobada."
