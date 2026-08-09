$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

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

if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "POSTGRES_USER local no cumple el formato seguro esperado."
}

if ($dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "POSTGRES_DB local no cumple el formato seguro esperado."
}

Write-Host "Asegurando PostgreSQL con el bootstrap montado..."
docker compose up --detach postgres
Assert-LastExitCode "Inicio de PostgreSQL"

$ready = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    docker compose exec -T postgres `
        pg_isready -U $dbUser -d $dbName *> $null

    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }

    Start-Sleep -Seconds 1
}

if (-not $ready) {
    throw "PostgreSQL no quedo listo a tiempo."
}

$containerSql = "/docker-entrypoint-initdb.d/00_bootstrap_roles_extensions.sql"

Write-Host "Aplicando roles y extensiones autorizadas..."
docker compose exec -T postgres `
    psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1 -f $containerSql
Assert-LastExitCode "Bootstrap PostgreSQL"

Write-Host "OK: bootstrap PostgreSQL aplicado."
