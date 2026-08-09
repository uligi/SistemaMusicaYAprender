$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-009: separando configuracion y secretos..."

if (Test-Path ".env") {
    $filtered = @(
        Get-Content ".env" |
            Where-Object {
                $_ -notmatch '^\s*POSTGRES_PASSWORD\s*=' -and
                $_ -notmatch '^\s*OBJECT_STORE_PASSWORD\s*=' -and
                $_ -notmatch '^\s*OBJECT_STORE_USER\s*='
            }
    )

    [System.IO.File]::WriteAllLines(
        (Join-Path $RepoRoot ".env"),
        $filtered,
        (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "Sanitizado .env local: se retiraron credenciales heredadas."
}
else {
    Copy-Item ".env.example" ".env"
    Write-Host "Creado .env con configuracion no secreta."
}

& "$PSScriptRoot/local/ensure-local-secrets.ps1"
& "$PSScriptRoot/security/check-no-secrets.ps1"

Write-Host "Sincronizando la credencial de la base existente/fresca..."
& "$PSScriptRoot/local/sync-postgres-secret.ps1"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

Write-Host "Actualizando lockfiles por la referencia directa a Npgsql..."
dotnet restore MusicaAprender.sln --force-evaluate
Assert-LastExitCode "Restauracion .NET"

npm.cmd run format
Assert-LastExitCode "Formateo"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-009 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Finalmente: .\scripts\local\verify-secret-rotation.ps1"
