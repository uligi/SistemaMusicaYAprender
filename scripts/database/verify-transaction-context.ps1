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

Write-Host "Preparando fixture aislado BL-MVP-013..."
docker compose exec -T postgres `
    psql -U $dbAdmin -d $dbName -v ON_ERROR_STOP=1 `
    -f /workspace/database/postgresql/tests/rls/prepare_transaction_context_fixture.sql
Assert-LastExitCode "Preparacion de fixture BL-MVP-013"

try {
    Write-Host "Verificando SET LOCAL equivalente, RLS cruzado y limpieza del pool..."
    dotnet run `
        --project tools/DatabaseContextVerifier/MusicaAprender.DatabaseContextVerifier.csproj `
        -- `
        --host 127.0.0.1 `
        --port $dbPort `
        --database $dbName `
        --secret-directory (Join-Path $Root "secrets\local")

    Assert-LastExitCode "DatabaseContextVerifier"
}
finally {
    Write-Host "Limpiando fixture BL-MVP-013..."
    docker compose exec -T postgres `
        psql -U $dbAdmin -d $dbName -v ON_ERROR_STOP=1 `
        -f /workspace/database/postgresql/tests/rls/cleanup_transaction_context_fixture.sql

    Assert-LastExitCode "Limpieza de fixture BL-MVP-013"
}

Write-Host "OK: BL-MVP-013 validado localmente: contexto, RLS cruzado y pool limpio."
