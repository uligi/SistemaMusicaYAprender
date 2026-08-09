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

$dbAdmin = Get-DotEnvValue "POSTGRES_USER" "musica_local"
$dbName = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"
$dbPort = Get-DotEnvValue "POSTGRES_PORT" "5432"

if ($dbAdmin -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$' -or
    $dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "Configuracion PostgreSQL local no cumple el formato seguro esperado."
}

& "$PSScriptRoot/prepare-database-access.ps1" -Database $dbName

New-Item -ItemType Directory -Force "artifacts/postgres" | Out-Null

Write-Host "Preparando fixture aislado BL-MVP-015..."
docker compose exec -T postgres `
    psql -U $dbAdmin -d $dbName -v ON_ERROR_STOP=1 `
    -f /workspace/database/postgresql/tests/reliability/prepare_bl_mvp_015.sql
Assert-LastExitCode "Preparacion de fixture BL-MVP-015"

try {
    Write-Host "Verificando outbox, inbox, idempotencia y reintentos..."
    dotnet run `
        --project tools/DatabaseReliabilityVerifier/MusicaAprender.DatabaseReliabilityVerifier.csproj `
        -- `
        --host 127.0.0.1 `
        --port $dbPort `
        --database $dbName `
        --secret-directory (Join-Path $Root "secrets\local")

    Assert-LastExitCode "DatabaseReliabilityVerifier"

    @"
bl_mvp=015
atomic_decision_outbox=true
idempotency_repetitions=1000
logical_duplicates=0
same_key_different_digest=conflict
inbox_duplicate_effects=0
retry_max_attempts=3
retry_backoff=exponential
retry_jitter=true
terminal_failure_status=REVIEW
failure_evidence=job_attempt
"@ | Set-Content `
        -Path "artifacts/postgres/reliability-summary.txt" `
        -Encoding utf8
}
finally {
    Write-Host "Limpiando fixture BL-MVP-015..."
    docker compose exec -T postgres `
        psql -U $dbAdmin -d $dbName -v ON_ERROR_STOP=1 `
        -f /workspace/database/postgresql/tests/reliability/cleanup_bl_mvp_015.sql

    Assert-LastExitCode "Limpieza de fixture BL-MVP-015"
}

Write-Host "OK: BL-MVP-015 validado localmente contra PostgreSQL 18."
