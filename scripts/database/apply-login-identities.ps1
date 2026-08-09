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

$dbUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"
$dbName = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"

if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$' -or
    $dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "POSTGRES_USER/POSTGRES_DB local no cumple el formato seguro esperado."
}

docker compose up --detach postgres
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo iniciar PostgreSQL."
}

$containerSql = "/workspace/database/postgresql/bootstrap/roles/01_login_identities.sql"

Write-Host "Aplicando identidades LOGIN separadas..."
docker compose exec -T postgres `
    psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1 -f $containerSql

if ($LASTEXITCODE -ne 0) {
    throw "No se pudieron aplicar las identidades LOGIN."
}

& "$Root/scripts/local/sync-postgres-identities.ps1"

Write-Host "OK: identidades LOGIN PostgreSQL aplicadas."
