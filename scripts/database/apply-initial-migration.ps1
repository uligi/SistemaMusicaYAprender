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
$dbPort = Get-DotEnvValue "POSTGRES_PORT" "5432"

Assert-SafeIdentifier $dbName "POSTGRES_DB"
Assert-SafeIdentifier $dbUser "POSTGRES_USER"

$secretPath = Join-Path $Root "secrets\local\postgres_password"
if (-not (Test-Path $secretPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_password."
}

# El DDL cambia temporalmente a jp_owner; ese rol debe poder crear los
# esquemas físicos dentro de la base objetivo.
& "$PSScriptRoot/grant-owner-database-create.ps1" -Database $dbName

Write-Host "Aplicando migracion EF Core embebida a '$dbName'..."

dotnet run `
    --project tools/DatabaseMigrator/MusicaAprender.DatabaseMigrator.csproj `
    -- `
    --host 127.0.0.1 `
    --port $dbPort `
    --database $dbName `
    --username $dbUser `
    --password-file $secretPath

if ($LASTEXITCODE -ne 0) {
    throw "DatabaseMigrator fallo con codigo de salida $LASTEXITCODE."
}

Write-Host "OK: migracion inicial aplicada a la base local."
