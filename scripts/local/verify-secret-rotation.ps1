$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

& "$PSScriptRoot/ensure-local-secrets.ps1"

$secretNames = @(
    "postgres_password",
    "object_store_access_key",
    "object_store_secret_key"
)

$before = @{}
foreach ($name in $secretNames) {
    $path = Join-Path $Root "secrets\local\$name"
    $value = [System.IO.File]::ReadAllText($path).Trim()
    $before[$name] = $value
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

Write-Host "OK: rotacion demostrada sin recompilar y sin secretos visibles en docker inspect."
