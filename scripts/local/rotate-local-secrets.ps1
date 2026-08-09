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

Write-Host "Deteniendo consumidores antes de rotar..."
docker compose stop api worker object-store
if ($LASTEXITCODE -ne 0) {
    throw "No se pudieron detener los consumidores de secretos."
}

$newPostgresPassword = New-RandomHex 32
$newObjectAccessKey = "local-" + (New-RandomHex 16)
$newObjectSecretKey = New-RandomHex 32

Write-Secret "postgres_password" $newPostgresPassword

try {
    & "$PSScriptRoot/sync-postgres-secret.ps1"
}
catch {
    throw "La rotacion PostgreSQL no pudo confirmarse. Revise el estado antes de continuar. $($_.Exception.Message)"
}

Write-Secret "object_store_access_key" $newObjectAccessKey
Write-Secret "object_store_secret_key" $newObjectSecretKey

Write-Host "Recreando servicios consumidores sin reconstruir imagenes..."
docker compose up --detach --force-recreate object-store api worker
if ($LASTEXITCODE -ne 0) {
    throw "No se pudieron recrear los consumidores despues de la rotacion."
}

Write-Host "OK: secretos locales rotados sin recompilar imagenes."
