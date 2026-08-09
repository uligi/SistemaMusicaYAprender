$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-015: implementando outbox, inbox e idempotencia comun..."

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Creado .env con configuracion no secreta."
}

& "$PSScriptRoot/local/ensure-local-secrets.ps1"
& "$PSScriptRoot/local/sync-postgres-secret.ps1"
& "$PSScriptRoot/database/apply-bootstrap.ps1"
& "$PSScriptRoot/database/apply-login-identities.ps1"
& "$PSScriptRoot/database/apply-initial-migration.ps1"

$projectPath = "tools\DatabaseReliabilityVerifier\MusicaAprender.DatabaseReliabilityVerifier.csproj"
$solutionProjects = @(dotnet sln MusicaAprender.sln list)
Assert-LastExitCode "Lectura de solucion"

if (-not ($solutionProjects -match [regex]::Escape($projectPath))) {
    dotnet sln MusicaAprender.sln add $projectPath
    Assert-LastExitCode "Agregar DatabaseReliabilityVerifier a la solucion"
}

Write-Host "Actualizando lockfiles .NET..."
dotnet restore MusicaAprender.sln --force-evaluate
Assert-LastExitCode "Restauracion .NET"

Write-Host "Formateando C#..."
dotnet format MusicaAprender.sln --no-restore
Assert-LastExitCode "dotnet format"

Write-Host "Formateando archivos de repositorio..."
npm.cmd run format
Assert-LastExitCode "npm format"

Write-Host "Compilando verificador de confiabilidad..."
dotnet build $projectPath --no-restore
Assert-LastExitCode "Compilacion DatabaseReliabilityVerifier"

Write-Host "Verificando BL-MVP-015..."
& "$PSScriptRoot/database/verify-reliability.ps1"

Write-Host "Confirmando BL-MVP-014..."
& "$PSScriptRoot/database/verify-ef-model.ps1"

Write-Host "Confirmando BL-MVP-013..."
& "$PSScriptRoot/database/verify-transaction-context.ps1"

Write-Host "Confirmando BL-MVP-012..."
& "$PSScriptRoot/database/verify-database-access.ps1"

Write-Host "Confirmando BL-MVP-011..."
& "$PSScriptRoot/database/verify-physical-schema.ps1"
& "$PSScriptRoot/database/verify-master-source.ps1"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-015 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Despues:    .\scripts\database\verify-reliability.ps1"
