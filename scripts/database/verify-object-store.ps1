$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

function Get-DotEnvValue([string]$Name, [string]$DefaultValue) {
    if (-not (Test-Path ".env")) {
        return $DefaultValue
    }

    $match = Get-Content ".env" |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -Last 1

    if ($null -eq $match) {
        return $DefaultValue
    }

    return (($match -split "=", 2)[1]).Trim()
}

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

& "$Root/scripts/local/ensure-local-secrets.ps1"

Write-Host "Asegurando object store privado de desarrollo..."
docker compose up --detach object-store
Assert-LastExitCode "docker compose up object-store"

$ready = $false

for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri "http://localhost:$(Get-DotEnvValue 'OBJECT_STORE_PORT' '9000')/minio/health/ready" `
            -TimeoutSec 2

        if ($response.StatusCode -eq 200) {
            $ready = $true
            break
        }
    }
    catch {
        Start-Sleep -Seconds 1
    }
}

if (-not $ready) {
    docker compose logs object-store
    throw "MinIO no alcanzo readiness dentro del tiempo esperado."
}

$endpoint = "http://127.0.0.1:$(Get-DotEnvValue 'OBJECT_STORE_PORT' '9000')"
$bucket = Get-DotEnvValue "OBJECT_STORE_BUCKET" "musica-aprender-private"
$databaseHost = "127.0.0.1"
$databasePort = Get-DotEnvValue "POSTGRES_PORT" "5432"
$databaseName = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"
$secretDirectory = Join-Path $Root "secrets\local"
$project = "tools/ObjectStoreVerifier/MusicaAprender.ObjectStoreVerifier.csproj"

Write-Host "Verificando BL-MVP-016 contra MinIO privado y PostgreSQL 18..."

dotnet run `
    --project $project `
    --no-restore `
    -- `
    --endpoint $endpoint `
    --bucket $bucket `
    --secret-dir $secretDirectory `
    --pg-host $databaseHost `
    --pg-port $databasePort `
    --pg-database $databaseName

Assert-LastExitCode "ObjectStoreVerifier"

Write-Host "OK: BL-MVP-016 validado localmente: cifrado, checksum, metadatos y acceso privado."
