$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

function New-RandomHex([int]$Bytes) {
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($buffer)
    }
    finally {
        $rng.Dispose()
    }

    return -join ($buffer | ForEach-Object { $_.ToString("x2") })
}

function Write-Secret([string]$Name, [string]$Value) {
    $path = Join-Path $Root "secrets\local\$Name"
    $tempPath = "$path.tmp"

    [System.IO.File]::WriteAllText(
        $tempPath,
        $Value,
        (New-Object System.Text.UTF8Encoding($false)))

    Move-Item -Force $tempPath $path
}

& "$PSScriptRoot/ensure-local-secrets.ps1"

Write-Host "Deteniendo consumidores runtime antes de rotar..."
docker compose stop api worker object-store
if ($LASTEXITCODE -ne 0) {
    throw "No se pudieron detener los consumidores de secretos."
}

Write-Secret "postgres_password" (New-RandomHex 32)

try {
    & "$PSScriptRoot/sync-postgres-secret.ps1"
}
catch {
    throw "La rotacion DBA PostgreSQL no pudo confirmarse. $($_.Exception.Message)"
}

Write-Secret "postgres_migrator_password" (New-RandomHex 32)
Write-Secret "postgres_api_password" (New-RandomHex 32)
Write-Secret "postgres_backoffice_password" (New-RandomHex 32)
Write-Secret "postgres_worker_password" (New-RandomHex 32)
Write-Secret "postgres_readonly_password" (New-RandomHex 32)

& "$Root/scripts/database/apply-login-identities.ps1"

Write-Secret "object_store_access_key" ("local-" + (New-RandomHex 16))
Write-Secret "object_store_secret_key" (New-RandomHex 32)

Write-Host "Recreando servicios consumidores sin reconstruir imagenes..."
docker compose up --detach --force-recreate object-store api worker
if ($LASTEXITCODE -ne 0) {
    throw "No se pudieron recrear los consumidores despues de la rotacion."
}

Write-Host "OK: secretos locales rotados sin recompilar imagenes."
