$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-011: integrando SQL maestro como migracion inicial embebida..."

& "$PSScriptRoot/database/verify-master-source.ps1"

$projectPath = "tools\DatabaseMigrator\MusicaAprender.DatabaseMigrator.csproj"
$solutionProjects = @(dotnet sln MusicaAprender.sln list)
Assert-LastExitCode "Lectura de solucion"

if (-not ($solutionProjects -match [regex]::Escape($projectPath))) {
    dotnet sln MusicaAprender.sln add $projectPath
    Assert-LastExitCode "Agregar DatabaseMigrator a la solucion"
}

Write-Host "Actualizando lockfiles .NET..."
dotnet restore MusicaAprender.sln --force-evaluate
Assert-LastExitCode "Restauracion .NET"

Write-Host "Compilando migrador EF Core..."
dotnet build $projectPath --no-restore
Assert-LastExitCode "Compilacion DatabaseMigrator"

& "$PSScriptRoot/database/verify-initial-migration.ps1"

npm.cmd run format
Assert-LastExitCode "Formateo"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-011 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Finalmente: .\scripts\database\verify-physical-schema.ps1"
