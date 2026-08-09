$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

& "$RepoRoot/scripts/local/ensure-local-secrets.ps1"
& "$RepoRoot/scripts/local/sync-postgres-secret.ps1"

Write-Host "Asegurando PostgreSQL y Mailpit..."
docker compose up --detach postgres smtp-sink
Assert-LastExitCode "Inicio PostgreSQL/Mailpit"

$ready = $false

for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri "http://127.0.0.1:8025/api/v1/messages" `
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
    docker compose logs smtp-sink
    throw "Mailpit no quedo listo para BL-MVP-017."
}

Write-Host "Verificando BL-MVP-017 contra PostgreSQL 18 y SMTP interno..."

$env:SMTP_HOST = "127.0.0.1"
$env:SMTP_PORT = "1025"
$env:MAILPIT_API_BASE = "http://127.0.0.1:8025/"

dotnet run `
    --project tools/EmailDeliveryVerifier/MusicaAprender.EmailDeliveryVerifier.csproj `
    --no-restore
Assert-LastExitCode "EmailDeliveryVerifier"

Write-Host "OK: BL-MVP-017 validado localmente contra cola PostgreSQL y Mailpit."
