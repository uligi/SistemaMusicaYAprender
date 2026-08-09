$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-012: separando identidades PostgreSQL y aplicando minimo privilegio..."

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Creado .env con configuracion no secreta."
}

& "$PSScriptRoot/local/ensure-local-secrets.ps1"
& "$PSScriptRoot/local/sync-postgres-secret.ps1"
& "$PSScriptRoot/database/apply-bootstrap.ps1"
& "$PSScriptRoot/database/apply-login-identities.ps1"

$projectPath = "tools\DatabaseAccessVerifier\MusicaAprender.DatabaseAccessVerifier.csproj"
$solutionProjects = @(dotnet sln MusicaAprender.sln list)
Assert-LastExitCode "Lectura de solucion"

if (-not ($solutionProjects -match [regex]::Escape($projectPath))) {
    dotnet sln MusicaAprender.sln add $projectPath
    Assert-LastExitCode "Agregar DatabaseAccessVerifier a la solucion"
}

Write-Host "Actualizando lockfiles .NET..."
dotnet restore MusicaAprender.sln --force-evaluate
Assert-LastExitCode "Restauracion .NET"

Write-Host "Compilando verificador de acceso..."
dotnet build $projectPath --no-restore
Assert-LastExitCode "Compilacion DatabaseAccessVerifier"

Write-Host "Aplicando/regresando la migracion con la identidad separada..."
& "$PSScriptRoot/database/apply-initial-migration.ps1"

Write-Host "Probando una instalacion vacia con jp_login_migrator..."
& "$PSScriptRoot/database/verify-initial-migration.ps1"

Write-Host "Verificando que la linea base fisica siga intacta..."
& "$PSScriptRoot/database/verify-physical-schema.ps1"

Write-Host "Ejecutando matriz de permisos y pruebas negativas..."
& "$PSScriptRoot/database/verify-database-access.ps1"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

npm.cmd run format
Assert-LastExitCode "Formateo"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-012 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Despues:    .\scripts\database\verify-database-access.ps1"
Write-Host "Finalmente: .\scripts\local\verify-secret-rotation.ps1"
