$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

& "$PSScriptRoot/ensure-local-secrets.ps1"

$secretNames = @(
    "postgres_password",
    "postgres_migrator_password",
    "postgres_api_password",
    "postgres_backoffice_password",
    "postgres_worker_password",
    "postgres_readonly_password",
    "object_store_access_key",
    "object_store_secret_key"
)

$before = @{}
foreach ($name in $secretNames) {
    $path = Join-Path $Root "secrets\local\$name"
    $before[$name] = [System.IO.File]::ReadAllText($path).Trim()
}

& "$PSScriptRoot/rotate-local-secrets.ps1"

foreach ($name in $secretNames) {
    $path = Join-Path $Root "secrets\local\$name"
    $after = [System.IO.File]::ReadAllText($path).Trim()

    if ($after -eq $before[$name]) {
        throw "El secreto '$name' no cambio durante la rotacion."
    }
}

& "$PSScriptRoot/verify-running.ps1"
& "$Root/scripts/database/verify-database-access.ps1"

$inspect = docker inspect `
    musica-aprender-local-api-1 `
    musica-aprender-local-worker-1 `
    musica-aprender-local-postgres-1 `
    musica-aprender-local-object-store-1

if ($LASTEXITCODE -ne 0) {
    throw "No se pudo inspeccionar la configuracion de los contenedores."
}

foreach ($name in $secretNames) {
    $path = Join-Path $Root "secrets\local\$name"
    $secretValue = [System.IO.File]::ReadAllText($path).Trim()

    if ($inspect -match [regex]::Escape($secretValue)) {
        throw "El valor de '$name' aparece en docker inspect; no debe viajar como variable de entorno."
    }
}

Write-Host "OK: rotacion de 8 secretos demostrada, accesos revalidados y valores ausentes de docker inspect."
