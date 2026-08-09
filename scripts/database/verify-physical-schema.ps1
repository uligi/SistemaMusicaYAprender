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

function Assert-SafeIdentifier([string]$Value, [string]$Name) {
    if ($Value -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "$Name no cumple el formato seguro esperado."
    }
}

$dbName = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"
$dbUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"

Assert-SafeIdentifier $dbName "POSTGRES_DB"
Assert-SafeIdentifier $dbUser "POSTGRES_USER"

$verifyPath = "/workspace/database/postgresql/tests/verify_initial_migration.sql"

docker compose exec -T postgres `
    psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1 -f $verifyPath

if ($LASTEXITCODE -ne 0) {
    throw "La verificacion de la base fisica local fallo."
}

Write-Host "OK: base local contiene la linea base fisica y semillas de BL-MVP-011."
