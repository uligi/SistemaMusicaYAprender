$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

$SecretDirectory = Join-Path $Root "secrets\local"
New-Item -ItemType Directory -Force -Path $SecretDirectory | Out-Null

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

function Ensure-Secret(
    [string]$Name,
    [int]$Bytes,
    [string]$Prefix = "") {

    $path = Join-Path $SecretDirectory $Name

    if (Test-Path $path) {
        $existing = [System.IO.File]::ReadAllText($path).Trim()

        if ($existing.Length -lt 16) {
            throw "El secreto local '$Name' existe pero es demasiado corto."
        }

        return
    }

    $value = $Prefix + (New-RandomHex $Bytes)
    [System.IO.File]::WriteAllText(
        $path,
        $value,
        (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "Creado secreto local: $Name"
}

Ensure-Secret "postgres_password" 32
Ensure-Secret "postgres_migrator_password" 32
Ensure-Secret "postgres_api_password" 32
Ensure-Secret "postgres_backoffice_password" 32
Ensure-Secret "postgres_worker_password" 32
Ensure-Secret "postgres_readonly_password" 32
Ensure-Secret "object_store_access_key" 16 "local-"
Ensure-Secret "object_store_secret_key" 32
Ensure-Secret "object_store_encryption_key" 32
Ensure-Secret "identity_email_lookup_key" 32
Ensure-Secret "identity_email_encryption_key" 32
Ensure-Secret "identity_verification_token_key" 32
Ensure-Secret "identity_password_fingerprint_key" 32

Write-Host "OK: secret store local preparado fuera del repositorio."
